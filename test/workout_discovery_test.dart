import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late WorkoutDiscoveryRepository discovery;
  late SessionRepository sessions;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    discovery = WorkoutDiscoveryRepository(workouts);
    sessions = SessionRepository(db, workouts);
    await workouts.initialize();
  });
  tearDown(() => db.close());

  Future<WorkoutDiscovery> legacyLoad(DateTime now) async {
    final result = await discovery.load(now);
    return WorkoutDiscovery(
      result.programs,
      result.workouts,
      result.programId,
      recommendWorkout(
        programs: result.programs,
        workouts: result.workouts,
        rules: await workouts.list('schedule'),
        now: now,
        programId: result.programId,
      ),
    );
  }

  test(
    'UI discovery is independent of schedules and remembers selection',
    () async {
      final all = await workouts.list('workout');
      await discovery.selectWorkout(all.last.id);
      for (final day in [DateTime(2026, 10, 20), DateTime(2027, 1, 1)]) {
        final result = await discovery.load(day);
        expect(result.recommendation, isNull);
        expect(result.workouts.length, all.length);
        expect(await discovery.selectedWorkout(), all.last.id);
      }
      expect(await sessions.unfinished(), isNull);
    },
  );
  for (final example in [
    (DateTime(2026, 10, 20), 'Tuesday A'),
    (DateTime(2026, 10, 22), 'Thursday A'),
    (DateTime(2026, 10, 27), 'Tuesday B'),
    (DateTime(2026, 10, 29), 'Thursday B'),
  ]) {
    test('scheduled day ${example.$1} recommends ${example.$2}', () async {
      final result = await legacyLoad(example.$1);
      expect(result.recommendation!.workout.name, example.$2);
      expect(result.recommendation!.isToday(example.$1), true);
      expect(await sessions.unfinished(), isNull);
    });
  }

  test(
    'rest and bike days recommend next strength workout across rotation boundary',
    () async {
      final next = (await legacyLoad(DateTime(2026, 10, 23))).recommendation!;
      expect(next.workout.name, 'Tuesday B');
      expect(next.date, DateTime(2026, 10, 27));
      expect(next.isToday(DateTime(2026, 10, 23)), false);
      expect(
        (await legacyLoad(DateTime(2026, 10, 19))).recommendation!.workout.name,
        'Tuesday A',
      );
      expect(
        (await legacyLoad(DateTime(2026, 10, 21))).recommendation!.workout.name,
        'Thursday A',
      );
    },
  );

  test(
    'recommendations respect overrides, archives and unscheduled workouts',
    () async {
      final program = (await workouts.list('program')).first;
      await workouts.edit(program.id, {...program.values, 'weekOverride': 1});
      final result = await legacyLoad(DateTime(2026, 10, 20));
      expect(result.recommendation!.workout.name, 'Tuesday B');
      expect(
        result.workouts.map((w) => w.name),
        containsAll(['Tuesday', 'Thursday', 'Saturday']),
      );
      await workouts.archive(result.recommendation!.workout.id, true);
      expect(
        (await legacyLoad(DateTime(2026, 10, 20))).recommendation!.workout.name,
        'Thursday B',
      );
      await workouts.archive(program.id, true);
      expect((await legacyLoad(DateTime(2026, 10, 20))).recommendation, isNull);
      expect((await legacyLoad(DateTime(2026, 10, 20))).workouts, hasLength(3));
    },
  );

  test(
    'year, leap day, prior anchors and longer cycles use calendar weeks',
    () {
      WorkoutRecord program(DateTime anchor, int length, {int? override}) =>
          WorkoutRecord(1, 'program', null, 0, false, {
            'name': 'P',
            'anchor': anchor.toIso8601String(),
            'cycle': List.generate(length, (i) => '$i'),
            'weekOverride': override,
          });
      final workout = WorkoutRecord(2, 'workout', 1, 0, false, {'name': 'Gym'});
      WorkoutRecord rule(int day, int week, {bool archived = false}) =>
          WorkoutRecord(3, 'schedule', 1, 0, archived, {
            'weekday': day,
            'week': week,
            'workoutId': 2,
          });
      WorkoutRecommendation? next(
        DateTime now,
        DateTime anchor,
        int length,
        int day,
        int week, {
        int? override,
      }) => recommendWorkout(
        programs: [program(anchor, length, override: override)],
        workouts: [workout],
        rules: [rule(day, week)],
        now: now,
      );
      expect(
        next(DateTime(2027, 1, 1), DateTime(2026, 12, 28), 2, 2, 1)!.date,
        DateTime(2027, 1, 5),
      );
      expect(
        next(DateTime(2028, 2, 29), DateTime(2028, 2, 28), 2, 4, 0)!.date,
        DateTime(2028, 3, 2),
      );
      expect(
        next(DateTime(2026, 10, 18), DateTime(2026, 10, 19), 2, 2, 0)!.date,
        DateTime(2026, 10, 20),
      );
      expect(
        next(DateTime(2026, 10, 20), DateTime(2026, 10, 19), 4, 2, 3)!.date,
        DateTime(2026, 11, 10),
      );
      expect(
        next(
          DateTime(2026, 10, 20),
          DateTime(2026, 10, 19),
          2,
          2,
          0,
          override: 1,
        ),
        isNull,
      );
      expect(
        recommendWorkout(
          programs: [program(DateTime(2026, 10, 19), 2)],
          workouts: [workout],
          rules: [rule(2, 0, archived: true)],
          now: DateTime(2026, 10, 20),
        ),
        isNull,
      );
    },
  );

  test(
    'viewing recommendations never starts or advances a workout or edits templates',
    () async {
      final before =
          (await db
                  .customSelect('SELECT * FROM management_records ORDER BY id')
                  .get())
              .map((r) => jsonEncode(r.data))
              .toList();
      for (var i = 0; i < 3; i++) {
        expect(
          (await legacyLoad(
            DateTime(2026, 10, 20),
          )).recommendation!.workout.name,
          'Tuesday A',
        );
      }
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM strength_sessions')
                .getSingle())
            .read<int>('n'),
        0,
      );
      expect(
        (await db
                .customSelect('SELECT * FROM management_records ORDER BY id')
                .get())
            .map((r) => jsonEncode(r.data))
            .toList(),
        before,
      );
    },
  );

  test(
    'replacement cancels intentionally, rejects stale confirmation and rolls back failed starts',
    () async {
      final all = await workouts.list('workout');
      final current = await sessions.start(all.first.id);
      await sessions.completeSet(current.id, 0, 0);
      final empty = await workouts.create('workout', {
        'name': 'Empty',
      }, parentId: all.first.parentId);
      await expectLater(
        sessions.replaceUnfinished(empty, current.id),
        throwsStateError,
      );
      expect((await sessions.unfinished())!.id, current.id);
      expect((await sessions.get(current.id)).completedSets, 1);
      final changed = await sessions.replaceUnfinished(all[1].id, current.id);
      expect(changed.id, isNot(current.id));
      expect((await sessions.get(current.id)).status, 'cancelled');
      expect((await sessions.get(current.id)).completedSets, 1);
      await expectLater(
        sessions.replaceUnfinished(all.first.id, current.id),
        throwsStateError,
      );
      expect((await sessions.unfinished())!.id, changed.id);
    },
  );

  test('concurrent starts cannot create duplicate unfinished sessions', () async {
    final id = (await workouts.list('workout')).first.id;
    final attempts = await Future.wait([
      for (var i = 0; i < 3; i++)
        sessions.start(id).then<Object>((s) => s, onError: (Object e) => e),
    ]);
    expect(attempts.whereType<StateError>(), hasLength(2));
    expect(
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM strength_sessions WHERE status IN ('active','paused')",
              )
              .getSingle())
          .read<int>('n'),
      1,
    );
  });

  test(
    'recommendation preference and genuine session survive database reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workout_discovery_',
      );
      final file = File('${directory.path}/app.sqlite');
      final firstDb = AppDatabase.forTesting(NativeDatabase(file));
      int? id, sessionId;
      try {
        final first = WorkoutRepository(firstDb);
        await first.initialize();
        id = (await first.list('program')).first.id;
        await WorkoutDiscoveryRepository(first).selectProgram(id);
        final current = await SessionRepository(
          firstDb,
          first,
        ).start((await first.list('workout')).first.id);
        sessionId = current.id;
        await SessionRepository(firstDb, first).pause(current.id);
      } finally {
        await firstDb.close();
      }
      final secondDb = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final second = WorkoutRepository(secondDb);
        final result = await WorkoutDiscoveryRepository(
          second,
        ).load(DateTime(2026, 10, 20));
        expect(result.programId, id);
        expect(result.recommendation, isNull);
        expect(
          (await SessionRepository(secondDb, second).unfinished())!.id,
          sessionId,
        );
        final unscheduled = (await second.list('program')).last;
        await WorkoutDiscoveryRepository(second).selectProgram(unscheduled.id);
        expect(
          (await WorkoutDiscoveryRepository(
            second,
          ).load(DateTime(2026, 10, 20))).recommendation,
          isNull,
        );
        expect(await second.list('preference'), hasLength(1));
      } finally {
        await secondDb.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
