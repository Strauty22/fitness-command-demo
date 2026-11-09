import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/workout_alternatives.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';
import 'package:fitness_command/features/home/data/rotation_repository.dart';
import 'package:fitness_command/features/exercises/data/exercise_library_repository.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late SessionRepository sessions;
  late int exerciseId, otherId, w1, w2, w3, entry1, entry2, entry3;
  Future<void> fixture(AppDatabase database) async {
    workouts = WorkoutRepository(database);
    sessions = SessionRepository(database, workouts);
    final program = await workouts.create('program', {
      'name': 'Original',
      'cycle': ['Week A', 'Week B'],
      'anchor': '2026-10-19',
      'sets': 2,
      'reps': 10,
    });
    exerciseId = await workouts.create('exercise', {
      'name': 'Chest Press',
      'type': 'weighted',
      'load': 70,
      'loadUnit': 'lb',
      'progression': 'Manual',
    });
    otherId = await workouts.create('exercise', {
      'name': 'Squat',
      'type': 'bodyweight',
    });
    w1 = await workouts.create('workout', {
      'name': 'Tuesday A',
      'customWorkout': true,
    }, parentId: program);
    w2 = await workouts.create('workout', {
      'name': 'Thursday B',
      'customWorkout': true,
    }, parentId: program);
    w3 = await workouts.create('workout', {
      'name': 'Saturday A',
      'customWorkout': true,
    }, parentId: program);
    entry1 = await workouts.create('entry', {
      'name': 'Chest Press',
      'exerciseId': exerciseId,
      'load': 70,
      'sets': 2,
      'reps': 10,
      'notes': 'Tuesday note',
    }, parentId: w1);
    final alternatives = [
      {
        'name': 'Squat',
        'exerciseId': otherId,
        'type': 'bodyweight',
        'sets': 2,
        'reps': 8,
        'notes': 'Other exercise',
      },
      {
        'name': 'Chest Press',
        'exerciseId': exerciseId,
        'type': 'weighted',
        'load': 70,
        'sets': 2,
        'reps': 10,
        'notes': 'Alternative note',
      },
    ];
    entry2 = await workouts.create(
      'entry',
      selectWorkoutAlternative({
        'alternatives': alternatives,
        'category': 'Push',
      }, 0),
      parentId: w2,
    );
    entry3 = await workouts.create('entry', {
      'name': 'Chest Press',
      'exerciseId': exerciseId,
      'load': 90,
      'sets': 3,
      'reps': 5,
      'notes': 'Saturday note',
    }, parentId: w3);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await fixture(db);
  });
  tearDown(() => db.close());

  test(
    'rep cycle records actuals down to zero and resets without extra sets or timer restart',
    () async {
      final started = await sessions.start(w1);
      final first = await sessions.tapSet(started.id, 0, 0);
      final rest = first.data['restUntil'];
      expect(first.exercises[0]['actualSets'][0]['reps'], 10);
      for (var n = 9; n >= 0; n--) {
        final next = await sessions.tapSet(started.id, 0, 0);
        expect(next.exercises[0]['actualSets'][0]['reps'], n);
        expect(next.exercises[0]['actualSets'][0]['completed'], true);
        expect(next.completedSets, 1);
        expect(next.totalSets, 2);
        expect(next.data['restUntil'], rest);
      }
      final reset = await sessions.tapSet(started.id, 0, 0);
      expect(reset.exercises[0]['actualSets'][0], {'completed': false});
      expect(reset.completedSets, 0);
      expect(reset.exercises[0]['target']['reps'], 10);
      expect(reset.data.containsKey('restUntil'), false);
      await sessions.tapSet(started.id, 0, 0);
      await sessions.editSet(started.id, 0, 0, {'reps': 4});
      expect(
        (await sessions.tapSet(
          started.id,
          0,
          0,
        )).exercises[0]['actualSets'][0]['reps'],
        3,
      );
      await sessions.pause(started.id);
      await expectLater(sessions.tapSet(started.id, 0, 0), throwsStateError);
      await sessions.finish(started.id);
      await expectLater(sessions.tapSet(started.id, 0, 0), throwsStateError);
    },
  );

  test(
    'different reps, bodyweight and timed sets keep their own semantics',
    () async {
      final body = await sessions.start(w2);
      expect(
        (await sessions.tapSet(
          body.id,
          0,
          0,
        )).exercises[0]['actualSets'][0]['reps'],
        8,
      );
      expect(
        (await sessions.tapSet(
          body.id,
          0,
          0,
        )).exercises[0]['actualSets'][0]['reps'],
        7,
      );
      await sessions.finish(body.id);
      final heavy = await sessions.start(w3);
      expect(
        (await sessions.tapSet(
          heavy.id,
          0,
          0,
        )).exercises[0]['actualSets'][0]['reps'],
        5,
      );
      await sessions.finish(heavy.id);
      final timed = await workouts.create('exercise', {
        'name': 'Hold',
        'type': 'timedHold',
        'durationSeconds': 30,
      });
      final entry = await workouts.get(entry1);
      await workouts.edit(entry.id, {
        ...entry.values,
        'exerciseId': timed,
        'type': 'timedHold',
        'durationSeconds': 30,
      });
      final active = await sessions.start(w1);
      await sessions.tapSet(active.id, 0, 0);
      final undone = await sessions.tapSet(active.id, 0, 0);
      expect(undone.completedSets, 0);
      expect(undone.exercises[0]['actualSets'][0]['durationSeconds'], 30);
    },
  );

  test(
    'rotation reuses original anchor automatically independently of saved override and sessions',
    () async {
      final discovery = WorkoutDiscoveryRepository(workouts);
      await discovery.selectWorkout(w3);
      final repo = RotationRepository(workouts);
      var rotation = await repo.load();
      expect(rotation.anchor, DateTime(2026, 10, 19));
      expect(rotation.week(DateTime(2026, 10, 25)), 1);
      expect(rotation.week(DateTime(2026, 10, 26)), 1);
      expect(rotation.week(DateTime(2026, 11, 2)), 0);
      expect(rotation.week(DateTime(2026, 10, 18)), 0);
      await repo.save(override: 1);
      rotation = await repo.load();
      expect(rotation.week(DateTime(2026, 10, 19)), 0);
      await repo.save();
      expect((await repo.load()).week(DateTime(2026, 10, 19)), 0);
      expect(await discovery.selectedWorkout(), w3);
      expect(await sessions.unfinished(), isNull);
      expect((await workouts.list('workout')).length, 3);
    },
  );

  test(
    'missing anchor stays unset despite override until explicitly configured',
    () async {
      final empty = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final repo = RotationRepository(WorkoutRepository(empty));
        expect((await repo.load()).week(DateTime(2026)), isNull);
        await repo.save(override: 0);
        expect((await repo.load()).week(DateTime(2026)), isNull);
        await repo.save(anchor: DateTime(2026, 11, 4));
        expect((await repo.load()).week(DateTime(2026, 11, 8)), 1);
        expect((await repo.load()).week(DateTime(2026, 11, 9)), 1);
      } finally {
        await empty.close();
      }
    },
  );

  test('automatic rotation changes at local Sunday midnight across years', () {
    final rotation = RotationState(DateTime(2026, 12, 30), 0);
    expect(rotation.week(DateTime(2027, 1, 2, 23, 59, 59)), 0);
    expect(rotation.week(DateTime(2027, 1, 3)), 1);
    expect(rotation.week(DateTime(2027, 1, 10)), 0);
    expect(rotation.week(DateTime(2026, 12, 26)), 1);
    final leap = RotationState(DateTime(2028, 2, 29), null);
    expect(leap.week(DateTime(2028, 3, 4, 23, 59)), 0);
    expect(leap.week(DateTime(2028, 3, 5)), 1);
  });

  test(
    'associations exclude archived entries, workouts and programs without deleting data',
    () async {
      final library = ExerciseLibraryRepository(workouts);
      final completed = await sessions.start(w1);
      await sessions.tapSet(completed.id, 0, 0);
      await sessions.finish(completed.id);
      final history = jsonEncode((await sessions.get(completed.id)).data);
      final snapshot =
          (await db
                  .customSelect('SELECT payload FROM completed_snapshots')
                  .getSingle())
              .read<String>('payload');
      await workouts.archive(w1, true);
      await workouts.archive(entry2, true);
      expect((await library.usages(exerciseId)).map((u) => u.workout.id), [w3]);
      expect((await workouts.get(exerciseId)).archived, false);
      expect(jsonEncode((await sessions.get(completed.id)).data), history);
      expect(
        (await db
                .customSelect('SELECT payload FROM completed_snapshots')
                .getSingle())
            .read<String>('payload'),
        snapshot,
      );
      await workouts.archive((await workouts.get(w3)).parentId!, true);
      expect(await library.usages(exerciseId), isEmpty);
      expect((await workouts.get(entry1)).values['exerciseId'], exerciseId);
    },
  );

  test(
    'single workout edit isolates its prescription; all edit touches only explicit fields and matching alternatives',
    () async {
      final library = ExerciseLibraryRepository(workouts);
      expect((await library.usages(exerciseId)).length, 3);
      final recorded = await sessions.start(w1);
      await sessions.tapSet(recorded.id, 0, 0);
      await sessions.finish(recorded.id);
      final history = jsonEncode((await sessions.get(recorded.id)).data);
      final snapshot =
          (await db
                  .customSelect('SELECT payload FROM completed_snapshots')
                  .getSingle())
              .read<String>('payload');
      final active = await sessions.start(w3);
      final activeData = jsonEncode(active.data);
      final other = jsonEncode(
        (await workouts.get(entry2)).values['alternatives'][0],
      );
      await library.update(exerciseId, {'load': 80}, workoutId: w1);
      expect((await workouts.get(entry1)).values['load'], 80);
      expect((await workouts.get(entry3)).values['load'], 90);
      expect((await workouts.get(exerciseId)).values['load'], 70);
      await library.update(exerciseId, {'load': 85});
      expect((await workouts.get(entry1)).values['load'], 85);
      final saturday = (await workouts.get(entry3)).values;
      expect(saturday['load'], 85);
      expect(saturday['sets'], 3);
      expect(saturday['reps'], 5);
      expect(saturday['notes'], 'Saturday note');
      final alternative = (await workouts.get(entry2)).values;
      expect(alternative['exerciseId'], otherId);
      expect(alternative['alternatives'][1]['load'], 85);
      expect(alternative['selectedAlternative'], 0);
      expect(jsonEncode(alternative['alternatives'][0]), other);
      expect((await workouts.get(exerciseId)).values['load'], 85);
      expect((await workouts.list('exercise')).length, 2);
      expect(jsonEncode((await sessions.get(active.id)).data), activeData);
      expect(jsonEncode((await sessions.get(recorded.id)).data), history);
      expect(
        (await db
                .customSelect('SELECT payload FROM completed_snapshots')
                .getSingle())
            .read<String>('payload'),
        snapshot,
      );
      await expectLater(
        library.update(exerciseId, {'load': -5}),
        throwsArgumentError,
      );
      expect((await workouts.get(entry1)).values['load'], 85);
      await expectLater(
        library.update(exerciseId, {'load': 1}, workoutId: 9999),
        throwsStateError,
      );
    },
  );

  test(
    'renames preserve identity, targets, alternatives, active sets and history',
    () async {
      final library = ExerciseLibraryRepository(workouts);
      final unrelated = await workouts.create('exercise', {
        'name': 'Chest Press',
        'type': 'weighted',
      });
      final unrelatedEntry = await workouts.create('entry', {
        'name': 'Chest Press',
        'exerciseId': unrelated,
      }, parentId: w1);
      final completed = await sessions.start(w1);
      await sessions.tapSet(completed.id, 0, 0);
      await sessions.finish(completed.id);
      final history = jsonEncode((await sessions.get(completed.id)).data);
      final snapshots =
          (await db
                  .customSelect('SELECT payload FROM completed_snapshots')
                  .get())
              .map((row) => row.read<String>('payload'))
              .toList();
      final active = await sessions.start(w3);
      await sessions.tapSet(active.id, 0, 0);
      final activeData = jsonEncode((await sessions.get(active.id)).data);
      final before = {
        for (final e in await workouts.list('entry')) e.id: e.values,
      };
      final canonical = (await workouts.get(exerciseId)).values;
      await library.update(exerciseId, {
        'name': '  Tuesday Press  ',
      }, workoutId: w1);
      expect((await workouts.get(exerciseId)).name, 'Chest Press');
      expect(
        (await workouts.resolvedEntry(
          await workouts.get(entry1),
        ))['exerciseName'],
        'Tuesday Press',
      );
      expect((await workouts.get(entry3)).values, before[entry3]);
      expect((await workouts.get(entry2)).values, before[entry2]);
      await library.update(exerciseId, {'name': 'Machine Press'});
      expect((await workouts.get(exerciseId)).values, {
        ...canonical,
        'name': 'Machine Press',
      });
      for (final id in [entry1, entry3]) {
        expect((await workouts.get(id)).values, {
          ...before[id]!,
          'name': 'Machine Press',
          'displayName': 'Machine Press',
        });
        expect(
          (await workouts.resolvedEntry(
            await workouts.get(id),
          ))['exerciseName'],
          'Machine Press',
        );
      }
      final options =
          (await workouts.get(entry2)).values['alternatives'] as List;
      expect(options[0], (before[entry2]!['alternatives'] as List)[0]);
      expect(options[1], {
        ...(before[entry2]!['alternatives'] as List)[1] as Map,
        'name': 'Machine Press',
        'displayName': 'Machine Press',
      });
      expect(
        (await workouts.resolvedEntry(
          await workouts.get(entry2),
          alternative: 1,
        ))['exerciseName'],
        'Machine Press',
      );
      expect(
        (await workouts.get(unrelatedEntry)).values,
        before[unrelatedEntry],
      );
      expect((await workouts.get(unrelated)).name, 'Chest Press');
      expect((await workouts.list('exercise')).length, 3);
      expect(jsonEncode((await sessions.get(active.id)).data), activeData);
      expect(jsonEncode((await sessions.get(completed.id)).data), history);
      expect(
        (await db.customSelect('SELECT payload FROM completed_snapshots').get())
            .map((row) => row.read<String>('payload'))
            .toList(),
        snapshots,
      );
      await expectLater(
        library.update(exerciseId, {'name': '  '}),
        throwsArgumentError,
      );
      expect((await workouts.get(exerciseId)).name, 'Machine Press');
      await sessions.finish(active.id);
      final future = await sessions.start(w1);
      expect(future.exercises.first['name'], 'Machine Press');
      expect(future.exercises.first['exerciseId'], exerciseId);
    },
  );

  test(
    'universal update rolls back every template when a later write fails',
    () async {
      await db.customStatement(
        "CREATE TRIGGER reject_test_update BEFORE UPDATE ON management_records WHEN OLD.id = $entry3 BEGIN SELECT RAISE(ABORT, 'Simulated write failure'); END",
      );
      await expectLater(
        ExerciseLibraryRepository(workouts).update(exerciseId, {'load': 99}),
        throwsA(anything),
      );
      expect((await workouts.get(entry1)).values['load'], 70);
      expect(
        (await workouts.get(entry2)).values['alternatives'][1]['load'],
        70,
      );
      expect((await workouts.get(entry3)).values['load'], 90);
      expect((await workouts.get(exerciseId)).values['load'], 70);
    },
  );

  test(
    'library edits support bodyweight and timed prescriptions without changing identities',
    () async {
      final library = ExerciseLibraryRepository(workouts);
      await library.update(otherId, {'reps': 12}, workoutId: w2);
      final body = (await workouts.get(entry2)).values;
      expect(body['type'], 'bodyweight');
      expect(body['exerciseId'], otherId);
      expect(body['reps'], 12);
      expect(body['alternatives'][1]['reps'], 10);
      final timedId = await workouts.create('exercise', {
        'name': 'Timed hold',
        'type': 'timedHold',
        'durationSeconds': 30,
      });
      final one = await workouts.create('entry', {
        'name': 'Timed hold',
        'exerciseId': timedId,
        'sets': 2,
        'durationSeconds': 30,
        'type': 'timedHold',
      }, parentId: w1);
      final two = await workouts.create('entry', {
        'name': 'Timed hold',
        'exerciseId': timedId,
        'sets': 3,
        'durationSeconds': 45,
        'type': 'timedHold',
      }, parentId: w3);
      await library.update(timedId, {'durationSeconds': 60});
      expect((await workouts.get(one)).values['durationSeconds'], 60);
      expect((await workouts.get(two)).values['durationSeconds'], 60);
      expect((await workouts.get(one)).values['sets'], 2);
      expect((await workouts.get(two)).values['sets'], 3);
      expect((await workouts.get(two)).values['exerciseId'], timedId);
    },
  );

  test(
    'rep decrement, rotation override and library edits survive database reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('library_rotation');
      final file = File('${dir.path}/app.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      late int sessionId;
      try {
        await fixture(first);
        sessionId = (await sessions.start(w1)).id;
        await sessions.tapSet(sessionId, 0, 0);
        await sessions.tapSet(sessionId, 0, 0);
        await RotationRepository(workouts).save(override: 1);
        await ExerciseLibraryRepository(
          workouts,
        ).update(exerciseId, {'load': 95, 'name': 'Persisted press'});
        await ExerciseLibraryRepository(
          workouts,
        ).update(exerciseId, {'name': 'Tuesday only'}, workoutId: w1);
      } finally {
        await first.close();
      }
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final repo = WorkoutRepository(reopened);
        expect(
          (await SessionRepository(
            reopened,
            repo,
          ).get(sessionId)).exercises[0]['actualSets'][0]['reps'],
          9,
        );
        expect((await RotationRepository(repo).load()).override, 1);
        expect((await repo.get(entry3)).values['load'], 95);
        expect((await repo.get(exerciseId)).name, 'Persisted press');
        expect(
          (await repo.resolvedEntry(await repo.get(entry1)))['exerciseName'],
          'Tuesday only',
        );
        expect(
          (await repo.resolvedEntry(await repo.get(entry3)))['exerciseName'],
          'Persisted press',
        );
        expect((await repo.get(entry3)).values['reps'], 5);
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
