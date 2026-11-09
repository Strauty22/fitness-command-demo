import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/core/database/management_schema.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late SessionRepository sessions;
  late DateTime now;
  late int workoutId;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    now = DateTime.utc(2026, 10, 20, 12);
    sessions = SessionRepository(db, workouts, clock: () => now);
    await workouts.seed();
    workoutId = (await workouts.list('workout')).first.id;
  });
  tearDown(() => db.close());

  test(
    'all starter workouts can be completed without changing prescribed targets',
    () async {
      for (final workout in await workouts.list('workout')) {
        final original = (await workouts.list(
          'entry',
          parentId: workout.id,
        )).map((e) => jsonEncode(e.values)).toList();
        final session = await sessions.start(workout.id);
        for (
          var exerciseIndex = 0;
          exerciseIndex < session.exercises.length;
          exerciseIndex++
        ) {
          final count =
              (session.exercises[exerciseIndex]['actualSets'] as List).length;
          for (var setIndex = 0; setIndex < count; setIndex++) {
            await sessions.completeSet(session.id, exerciseIndex, setIndex);
          }
        }
        final completed = await sessions.finish(session.id);
        expect(completed.completedSets, completed.totalSets);
        expect(
          (await workouts.list(
            'entry',
            parentId: workout.id,
          )).map((e) => jsonEncode(e.values)).toList(),
          original,
        );
      }
      expect(await sessions.history(), hasLength(4));
    },
  );

  test('start freezes ordered targets without claiming actuals', () async {
    final session = await sessions.start(workoutId);
    expect(session.exercises, hasLength(13));
    expect(session.exercises.first['name'], 'Jump rope');
    expect(session.exercises[2]['target']['sets'], 2);
    expect(session.exercises[2]['target']['reps'], 10);
    expect(session.exercises[2]['target']['load'], 10);
    expect(session.completedSets, 0);
    expect(session.exercises[2]['actualSets'][0], {'completed': false});
    final entry = (await workouts.list('entry', parentId: workoutId))[2];
    await workouts.edit(entry.id, {...entry.values, 'sets': 5, 'load': 999});
    final exercise = await workouts.get(entry.values['exerciseId'] as int);
    await workouts.edit(exercise.id, {...exercise.values, 'name': 'Changed'});
    await workouts.archive(workoutId, true);
    final recovered = await sessions.get(session.id);
    expect(recovered.exercises[2]['name'], 'Goblet squat');
    expect(recovered.exercises[2]['target']['load'], 10);
    expect(recovered.exercises[2]['actualSets'], hasLength(2));
    await expectLater(sessions.start(workoutId), throwsStateError);
  });

  test(
    'one tap copies targets, edits actuals only, repeated tap is idempotent',
    () async {
      final session = await sessions.start(workoutId);
      await sessions.editSet(session.id, 2, 0, {'reps': 8, 'load': 12.5});
      final completed = await sessions.completeSet(session.id, 2, 0);
      expect(completed.exercises[2]['actualSets'][0]['reps'], 8);
      expect(completed.exercises[2]['actualSets'][0]['load'], 12.5);
      expect(completed.exercises[2]['target']['load'], 10);
      expect(completed.restRemaining(now), 90);
      now = now.add(const Duration(seconds: 20));
      final repeated = await sessions.completeSet(session.id, 2, 0);
      expect(repeated.completedSets, 1);
      expect(repeated.restRemaining(now), 70);
      final undone = await sessions.undoSet(session.id, 2, 0);
      expect(undone.completedSets, 0);
      expect(undone.restRemaining(now), 0);
      expect(undone.exercises[2]['actualSets'][0]['load'], 12.5);
      expect(
        () => sessions.editSet(session.id, 2, 0, {'reps': -1}),
        throwsArgumentError,
      );
      expect(
        () => sessions.editSet(session.id, 2, 0, {'reps': 1.5}),
        throwsArgumentError,
      );
    },
  );

  test('rapid updates do not lose different sets or draft changes', () async {
    final session = await sessions.start(workoutId);
    await Future.wait([
      sessions.editSet(session.id, 2, 0, {'reps': 7}),
      sessions.editSet(session.id, 2, 1, {'load': 15}),
      sessions.completeSet(session.id, 1, 0),
    ]);
    final saved = await sessions.get(session.id);
    expect(saved.exercises[2]['actualSets'][0]['reps'], 7);
    expect(saved.exercises[2]['actualSets'][1]['load'], 15);
    expect(saved.completedSets, 1);
  });

  test(
    'timer settings, pause/resume and expiration use persisted clock time',
    () async {
      final session = await sessions.start(workoutId);
      await sessions.configureRest(session.id, 30);
      final logged = await sessions.completeSet(session.id, 2, 0);
      expect(logged.restRemaining(now), 30);
      now = now.add(const Duration(seconds: 10));
      final paused = await sessions.pause(session.id);
      expect(paused.status, 'paused');
      now = now.add(const Duration(hours: 1));
      expect((await sessions.get(session.id)).restRemaining(now), 20);
      await expectLater(
        sessions.completeSet(session.id, 2, 1),
        throwsStateError,
      );
      final resumed = await sessions.resume(session.id);
      expect(resumed.restRemaining(now), 20);
      now = now.add(const Duration(seconds: 21));
      expect((await sessions.get(session.id)).restRemaining(now), 0);
      await sessions.configureRest(session.id, 0);
      expect(
        (await sessions.completeSet(session.id, 2, 1)).restRemaining(now),
        0,
      );
      expect(() => sessions.configureRest(session.id, -1), throwsArgumentError);
    },
  );

  test(
    'skipping preserves performed sets; completion keeps partial immutable history',
    () async {
      final session = await sessions.start(workoutId);
      await sessions.completeSet(session.id, 2, 0);
      await sessions.skip(session.id, 2, true);
      await sessions.skip(session.id, 12, true);
      await expectLater(
        sessions.completeSet(session.id, 2, 1),
        throwsStateError,
      );
      final beforeFinish = await sessions.get(session.id);
      expect(beforeFinish.completedSets, 1);
      final finished = await sessions.finish(session.id);
      expect(finished.status, 'completed');
      expect(finished.completedSets, 1);
      expect(finished.exercises[2]['skipped'], true);
      expect(await sessions.unfinished(), isNull);
      await sessions.finish(session.id);
      expect(
        await db.customSelect('SELECT * FROM completed_snapshots').get(),
        hasLength(1),
      );
      final snapshot =
          (await db
                  .customSelect('SELECT payload FROM completed_snapshots')
                  .getSingle())
              .read<String>('payload');
      expect(jsonDecode(snapshot)['exercises'][2]['actualSets'][0]['load'], 10);
      await expectLater(
        sessions.editSet(session.id, 2, 0, {'load': 99}),
        throwsStateError,
      );
      await expectLater(
        db.customStatement(
          "UPDATE strength_sessions SET payload = '{}' WHERE id = ${session.id}",
        ),
        throwsA(anything),
      );
      expect((await sessions.history()).single.id, session.id);
    },
  );

  test(
    'cancel preserves saved actuals but does not count as previous performance',
    () async {
      final session = await sessions.start(workoutId);
      await sessions.completeSet(session.id, 2, 0);
      final cancelled = await sessions.finish(session.id, cancel: true);
      expect(cancelled.status, 'cancelled');
      expect(cancelled.completedSets, 1);
      expect(
        await sessions.previous(cancelled.exercises[2]['exerciseId'] as int),
        isNull,
      );
      expect(
        await db.customSelect('SELECT * FROM completed_snapshots').get(),
        isEmpty,
      );
      expect(await sessions.unfinished(), isNull);
      final next = await sessions.start(workoutId);
      expect(next.id, isNot(session.id));
    },
  );

  test(
    'previous performance follows exercise identity across templates',
    () async {
      final session = await sessions.start(workoutId);
      await sessions.editSet(session.id, 1, 0, {'reps': 3});
      await sessions.completeSet(session.id, 1, 0);
      await sessions.finish(session.id);
      final other = (await workouts.list('workout'))[2];
      final next = await sessions.start(other.id);
      expect(next.exercises[1]['name'], 'Pull-ups');
      expect(next.exercises[1]['previous']['sets'][0]['reps'], 3);
      expect(
        next.exercises[2]['previous'],
        isNull,
      ); // Bodyweight squat is separate.
    },
  );

  test(
    'timed, unknown-rep and distance actuals retain their measurement type',
    () async {
      final timed = await sessions.start(workoutId);
      final saved = await sessions.completeSet(timed.id, 0, 0);
      expect(saved.exercises[0]['actualSets'][0]['durationSeconds'], 300);
      expect(saved.exercises[0]['actualSets'][0].containsKey('reps'), false);
      await sessions.finish(timed.id, cancel: true);
      final thursday = (await workouts.list('workout'))[1];
      final quality = await sessions.start(thursday.id);
      final logged = await sessions.completeSet(quality.id, 1, 0);
      expect(logged.exercises[1]['actualSets'][0].containsKey('reps'), false);
      await sessions.finish(quality.id, cancel: true);
      final exerciseId = await workouts.create('exercise', {
        'name': 'Row distance',
        'type': 'distance',
      });
      final custom = await workouts.create('workout', {
        'name': 'Distance',
      }, parentId: (await workouts.list('program')).single.id);
      await workouts.create('entry', {
        'name': 'Row',
        'exerciseId': exerciseId,
        'distance': 500,
        'distanceUnit': 'm',
        'sets': 1,
      }, parentId: custom);
      final distance = await sessions.start(custom);
      await sessions.editSet(distance.id, 0, 0, {'distance': 450});
      expect(
        (await sessions.completeSet(
          distance.id,
          0,
          0,
        )).exercises[0]['actualSets'][0]['distance'],
        450,
      );
    },
  );

  test(
    'file reopen recovers actual drafts, skips, pause and timer settings',
    () async {
      final dir = await Directory.systemTemp.createTemp('strength_recovery');
      final file = File('${dir.path}/sessions.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      final initialWorkouts = WorkoutRepository(first);
      final initial = SessionRepository(
        first,
        initialWorkouts,
        clock: () => now,
      );
      await initialWorkouts.seed();
      final session = await initial.start(
        (await initialWorkouts.list('workout')).first.id,
      );
      await initial.configureRest(session.id, 45);
      await initial.completeSet(session.id, 2, 0);
      await initial.editSet(session.id, 2, 1, {'reps': 6, 'load': 17.5});
      await initial.skip(session.id, 12, true);
      await initial.pause(session.id);
      await first.close();
      now = now.add(const Duration(minutes: 5));
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final recoveredRepo = SessionRepository(
          reopened,
          WorkoutRepository(reopened),
          clock: () => now,
        );
        final recovered = (await recoveredRepo.unfinished())!;
        expect(recovered.id, session.id);
        expect(recovered.status, 'paused');
        expect(recovered.completedSets, 1);
        expect(recovered.exercises[2]['actualSets'][1]['reps'], 6);
        expect(recovered.exercises[2]['actualSets'][1]['load'], 17.5);
        expect(recovered.exercises[12]['skipped'], true);
        expect(recovered.restRemaining(now), 45);
        await recoveredRepo.resume(session.id);
        await recoveredRepo.completeSet(session.id, 2, 1);
        final finished = await recoveredRepo.finish(session.id);
        expect(finished.completedSets, 2);
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'active timer and cleared actual values recover across file reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('active_recovery');
      final file = File('${dir.path}/active.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      final w = WorkoutRepository(first);
      final r = SessionRepository(first, w, clock: () => now);
      await w.seed();
      final active = await r.start((await w.list('workout')).first.id);
      await r.editSet(active.id, 2, 0, {'load': null, 'reps': 0});
      await r.completeSet(active.id, 2, 0);
      await first.close();
      now = now.add(const Duration(seconds: 15));
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final recovered = SessionRepository(
          reopened,
          WorkoutRepository(reopened),
          clock: () => now,
        );
        final session = (await recovered.unfinished())!;
        expect(session.status, 'active');
        expect(session.restRemaining(now), 75);
        expect(session.exercises[2]['actualSets'][0]['load'], isNull);
        expect(session.exercises[2]['actualSets'][0]['reps'], 0);
        now = now.add(const Duration(minutes: 2));
        expect((await recovered.get(active.id)).restRemaining(now), 0);
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'version 2 migration preserves templates and completed snapshots',
    () async {
      final dir = await Directory.systemTemp.createTemp('strength_migration');
      final file = File('${dir.path}/v2.sqlite');
      final old = _VersionTwo(NativeDatabase(file));
      final oldWorkouts = WorkoutRepository(old);
      await oldWorkouts.seed();
      final id = (await oldWorkouts.list('workout')).first.id;
      await oldWorkouts.snapshot(id, now);
      await old.close();
      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final repository = WorkoutRepository(upgraded);
        expect(await repository.list('workout'), hasLength(4));
        expect(
          await upgraded
              .customSelect('SELECT * FROM completed_snapshots')
              .get(),
          hasLength(1),
        );
        final newSession = await SessionRepository(
          upgraded,
          repository,
        ).start(id);
        expect(newSession.exercises, hasLength(13));
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 9);
      } finally {
        await upgraded.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

class _VersionTwo extends AppDatabase {
  _VersionTwo(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (_) => createManagementSchema(this));
}
