import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/custom_workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/exercises/data/exercise_library_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';

const timed = WorkoutExerciseDraft({
  'name': 'Travel hold',
  'type': 'timedHold',
  'sets': 2,
  'durationSeconds': 35,
  'restSeconds': 15,
  'notes': 'Keep steady',
  'progression': 'Manual',
});

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late CustomWorkoutRepository custom;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    custom = CustomWorkoutRepository(workouts);
  });
  tearDown(() => db.close());

  test(
    'associations match selectable workouts and preserve starter records',
    () async {
      final originals = await ensureCompactWorkouts(workouts);
      final customId = await custom.save(
        name: 'Active custom',
        notes: '',
        exercises: [timed],
      );
      final selectable = {...originals.map((w) => w.id), customId};
      final before = await db
          .customSelect('SELECT * FROM management_records ORDER BY id')
          .get();
      final library = ExerciseLibraryRepository(workouts);
      final visible = <int>{};
      for (final exercise in await workouts.list('exercise')) {
        final uses = await library.usages(exercise.id);
        expect(uses.every((u) => selectable.contains(u.workout.id)), true);
        visible.addAll(uses.map((u) => u.workout.id));
      }
      expect(visible, selectable);
      final starter = (await workouts.list(
        'program',
      )).firstWhere((p) => p.name == 'Starter strength');
      expect(await workouts.list('workout', parentId: starter.id), isNotEmpty);
      final after = await db
          .customSelect('SELECT * FROM management_records ORDER BY id')
          .get();
      expect(
        after.map((r) => r.data).toList(),
        before.map((r) => r.data).toList(),
      );
    },
  );

  test(
    'create, edit, reorder, remove and delete preserve six originals and snapshots',
    () async {
      final originals = await ensureCompactWorkouts(workouts);
      final allBefore = {
        for (final kind in [
          'program',
          'workout',
          'exercise',
          'entry',
          'schedule',
        ])
          for (final record in await workouts.list(kind, includeArchived: true))
            record.id: jsonEncode(record.values),
      };
      final exercisesBefore = (await workouts.list('exercise')).length;
      final schedulesBefore = (await workouts.list('schedule')).length;
      final shared = (await workouts.list(
        'exercise',
      )).firstWhere((e) => e.name.toLowerCase() == 'chest press');
      final uses = await ExerciseLibraryRepository(workouts).usages(shared.id);
      final existing = WorkoutExerciseDraft({
        ...exerciseDraftValues(shared, uses.first.target),
        'load': 17,
        'sets': 3,
        'reps': 6,
        'progression': 'Manual',
      }, exerciseId: shared.id);
      final id = await custom.save(
        name: ' Travel Workout ',
        notes: 'Hotel gym',
        exercises: [existing, timed],
      );
      expect((await custom.list()).single.name, 'Travel Workout');
      expect((await workouts.list('schedule')).length, schedulesBefore);
      final entries = await custom.entries(id);
      expect(entries.map((e) => e.exerciseId).first, shared.id);
      final newId = entries.last.exerciseId!;
      expect((await workouts.get(newId)).name, timed.name);
      expect(
        (await ExerciseLibraryRepository(
          workouts,
        ).usages(newId)).single.workout.id,
        id,
      );
      expect((await workouts.list('exercise')).length, exercisesBefore + 1);
      for (final record in allBefore.entries) {
        expect(
          jsonEncode((await workouts.get(record.key)).values),
          record.value,
        );
      }
      final sessions = SessionRepository(db, workouts);
      final completed = await sessions.start(id);
      expect(completed.name, 'Travel Workout');
      expect(completed.data['notes'], 'Hotel gym');
      await sessions.tapSet(completed.id, 0, 0);
      await sessions.tapSet(completed.id, 0, 0);
      expect(
        (await sessions.get(
          completed.id,
        )).exercises[0]['actualSets'][0]['reps'],
        5,
      );
      await sessions.tapSet(completed.id, 1, 0);
      expect(
        (await sessions.get(
          completed.id,
        )).exercises[1]['actualSets'][0]['durationSeconds'],
        35,
      );
      await sessions.saveNotes(completed.id, 'Finished at hotel');
      await sessions.finish(completed.id);
      final history = jsonEncode((await sessions.get(completed.id)).data);
      final snapshot =
          (await db
                  .customSelect('SELECT payload FROM completed_snapshots')
                  .getSingle())
              .read<String>('payload');
      final active = await sessions.start(id);
      await sessions.tapSet(active.id, 0, 0);
      final activeData = jsonEncode((await sessions.get(active.id)).data);
      await custom.save(
        workoutId: id,
        name: 'Recovery',
        notes: 'Updated',
        exercises: [
          entries.last,
          entries.first.edited({...entries.first.values, 'reps': 8}),
        ],
      );
      var updated = await custom.entries(id);
      expect(updated.map((e) => e.entryId).toList(), [
        entries.last.entryId,
        entries.first.entryId,
      ]);
      expect(updated.last.values['reps'], 8);
      await custom.save(
        workoutId: id,
        name: 'Recovery',
        notes: '',
        exercises: [updated.first],
      );
      expect((await workouts.get(entries.first.entryId!)).archived, true);
      expect((await custom.entries(id)).single.exerciseId, newId);
      expect(jsonEncode((await sessions.get(active.id)).data), activeData);
      final second = await custom.save(
        name: 'Reuse hold',
        notes: '',
        exercises: [
          WorkoutExerciseDraft(
            exerciseDraftValues(await workouts.get(newId)),
            exerciseId: newId,
          ),
        ],
      );
      expect((await custom.entries(second)).single.exerciseId, newId);
      await WorkoutDiscoveryRepository(workouts).selectWorkout(id);
      await custom.delete(id);
      final remainingUses = await ExerciseLibraryRepository(
        workouts,
      ).usages(newId);
      expect(remainingUses.map((u) => u.workout.id), [second]);
      expect(
        (await ExerciseLibraryRepository(
          workouts,
        ).usages(shared.id)).every((u) => u.workout.id != id),
        true,
      );
      for (final original in originals) {
        for (final entry in await workouts.list(
          'entry',
          parentId: original.id,
        )) {
          final uses = await ExerciseLibraryRepository(
            workouts,
          ).usages(entry.values['exerciseId'] as int);
          expect(uses.any((u) => u.workout.id == original.id), true);
          expect(
            uses.every(
              (u) => !originals.any(
                (v) => v.values['sourceWorkoutId'] == u.workout.id,
              ),
            ),
            true,
          );
        }
      }
      expect((await custom.list()).map((w) => w.id).toList(), [second]);
      expect(
        await WorkoutDiscoveryRepository(workouts).selectedWorkout(),
        isNull,
      );
      expect((await workouts.get(newId)).archived, false);
      expect(jsonEncode((await sessions.get(active.id)).data), activeData);
      expect(jsonEncode((await sessions.get(completed.id)).data), history);
      expect(
        (await db
                .customSelect('SELECT payload FROM completed_snapshots')
                .getSingle())
            .read<String>('payload'),
        snapshot,
      );
      expect(
        (await ensureCompactWorkouts(workouts)).map((w) => w.id),
        originals.map((w) => w.id),
      );
      for (final record in allBefore.entries) {
        expect(
          jsonEncode((await workouts.get(record.key)).values),
          record.value,
        );
      }
      await expectLater(custom.delete(originals.first.id), throwsStateError);
      await expectLater(
        custom.save(
          workoutId: originals.first.id,
          name: 'Oops',
          notes: '',
          exercises: [timed],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'validation and duplicate prevention leave no partially saved records',
    () async {
      final existingId = await workouts.create('exercise', {
        'name': 'Travel Hold',
        'type': 'timedHold',
        'durationSeconds': 20,
      });
      for (final name in ['', '   ']) {
        await expectLater(
          custom.save(name: name, notes: '', exercises: [timed]),
          throwsArgumentError,
        );
      }
      await expectLater(
        custom.save(name: 'Empty', notes: '', exercises: []),
        throwsArgumentError,
      );
      await expectLater(
        custom.save(
          name: 'Duplicate',
          notes: '',
          exercises: [
            timed.edited({...timed.values, 'name': '  TRAVEL   hold '}),
          ],
        ),
        throwsA(isA<DuplicateExercise>()),
      );
      expect(await workouts.list('program'), isEmpty);
      expect(await workouts.list('workout'), isEmpty);
      expect((await workouts.list('exercise')).single.id, existingId);
      await expectLater(
        custom.save(
          name: 'Invalid',
          notes: '',
          exercises: [
            timed.edited({...timed.values, 'name': 'Another', 'sets': 1.5}),
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        custom.save(
          name: 'Missing',
          notes: '',
          exercises: [WorkoutExerciseDraft(timed.values, exerciseId: 99999)],
        ),
        throwsArgumentError,
      );
      await db.customStatement(
        "CREATE TRIGGER reject_custom_entry BEFORE INSERT ON management_records WHEN NEW.kind = 'entry' BEGIN SELECT RAISE(ABORT, 'Simulated failure'); END",
      );
      await expectLater(
        custom.save(
          name: 'Rollback',
          notes: '',
          exercises: [
            timed.edited({...timed.values, 'name': 'Unique hold'}),
          ],
        ),
        throwsA(anything),
      );
      expect(await workouts.list('program'), isEmpty);
      expect(await workouts.list('workout'), isEmpty);
      expect((await workouts.list('exercise')).single.id, existingId);
    },
  );

  test(
    'custom template and reusable exercise persist after database reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp('custom_workout');
      final file = File('${directory.path}/app.sqlite');
      final first = AppDatabase.forTesting(NativeDatabase(file));
      late int id, exerciseId, sessionId;
      try {
        final repo = WorkoutRepository(first);
        final service = CustomWorkoutRepository(repo);
        id = await service.save(
          name: 'Persistent workout',
          notes: 'Offline',
          exercises: [timed],
        );
        exerciseId = (await service.entries(id)).single.exerciseId!;
        final sessions = SessionRepository(first, repo);
        sessionId = (await sessions.start(id)).id;
        await sessions.tapSet(sessionId, 0, 0);
        await sessions.finish(sessionId);
      } finally {
        await first.close();
      }
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final repo = WorkoutRepository(reopened);
        final service = CustomWorkoutRepository(repo);
        expect((await service.list()).single.id, id);
        final entry = (await service.entries(id)).single;
        expect(entry.exerciseId, exerciseId);
        expect(entry.values['durationSeconds'], 35);
        expect(entry.values['restSeconds'], 15);
        final history = await SessionRepository(reopened, repo).get(sessionId);
        expect(history.status, 'completed');
        expect(history.completedSets, 1);
        expect(history.data['notes'], 'Offline');
      } finally {
        await reopened.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
