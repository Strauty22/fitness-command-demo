import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/personal_workout_seed.dart';
import 'package:fitness_command/features/workout/data/workout_alternatives.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  late SessionRepository sessions;
  Future<List<WorkoutRecord>> imported() async {
    final program = (await repo.list(
      'program',
    )).singleWhere((p) => p.values['importKey'] == personalPlanKey);
    return repo.list('workout', parentId: program.id);
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db);
    sessions = SessionRepository(db, repo);
  });
  tearDown(() => db.close());

  test(
    'additive import preserves all existing rows and history, including edits and archives',
    () async {
      await repo.seed();
      final p = (await repo.list('program')).single;
      await repo.edit(p.id, {
        ...p.values,
        'name': 'User edited',
        'weekOverride': 1,
      });
      final w = (await repo.list('workout')).first;
      final entry = (await repo.list('entry', parentId: w.id)).first;
      await repo.edit(entry.id, {...entry.values, 'notes': 'User edit'});
      final oldSession = await sessions.start(w.id);
      await sessions.completeSet(oldSession.id, 0, 0);
      final finished = await sessions.finish(oldSession.id);
      final oldHistory = jsonEncode(finished.data);
      final before = {
        for (final row
            in await db.customSelect('SELECT * FROM management_records').get())
          row.read<int>('id'): jsonEncode(row.data),
      };
      await repo.initialize();
      await repo.initialize();
      for (final row
          in await db.customSelect('SELECT * FROM management_records').get()) {
        final original = before[row.read<int>('id')];
        if (original != null) expect(jsonEncode(row.data), original);
      }
      expect(jsonEncode((await sessions.get(finished.id)).data), oldHistory);
      expect((await repo.list('schedule')).length, 9);
      final workouts = await imported();
      expect(workouts.map((w) => w.name), ['Tuesday', 'Thursday', 'Saturday']);
      final edited = (await repo.list(
        'entry',
        parentId: workouts.first.id,
      )).first;
      await repo.edit(edited.id, {...edited.values, 'durationSeconds': 420});
      await repo.archive(workouts.first.parentId!, true);
      await repo.initialize();
      expect((await repo.get(edited.id)).values['durationSeconds'], 420);
      expect(
        (await repo.list(
          'program',
          includeArchived: true,
        )).where((p) => p.values['importKey'] == personalPlanKey),
        hasLength(1),
      );
    },
  );

  test(
    'every imported name, category, alternative, starting load and prescription matches spreadsheet',
    () async {
      await seedPersonalWorkouts(repo);
      final workouts = await imported();
      const categories = [
        'Warmup',
        'Fresh Pull',
        'Squat',
        'Primary Push',
        'Primary Pull',
        'Hinge',
        'Secondary Push',
        'Secondary Pull',
        'Carry',
        'Obliques',
        'Abs',
        'Posture',
        'Optional Finisher',
        'Optional Balance',
      ];
      const tuesday = [
        'Jump rope|Full-body athletic warmup||',
        'Pull-ups|Pull-ups||',
        'Goblet squat|Bodyweight squat|10|',
        'Chest press|Decline push-ups|70|',
        'Seated row|Cable row|110|90',
        'Back extension|Machine deadlift||70',
        'Shoulder press|Lateral raise|70|10',
        'Lat pulldown|Face pull|60|40',
        'Farmer carry|Suitcase carry||',
        'Pallof press|Cable chop|50|50',
        'Physio Ball Cable Roll Up|Physio Ball Cable Roll Up|10|10',
        'Face pull|Band pull-apart|50|',
        'Leg curl|Arm curl|10|60',
        'Single-leg stand|Single-leg RDL reach||',
      ];
      const thursday = [
        'Full-body athletic warmup|Jump rope||',
        'Negative pull-ups|Chin-ups||',
        'Bodyweight squat|Goblet squat||10',
        'Lat pulldown|Chin-ups|60|',
        'Decline push-ups|Chest press||70',
        'DB Romanian deadlift|Back extension|20|',
        'Cable row|Seated row|90|110',
        'Shoulder press|Triceps press|70|30',
        'Suitcase carry|Farmer carry||',
        'Cable chop|Pallof press|50|50',
        'Plank|Plank||',
        'Face pull|Band pull-apart|50|',
        'Leg curl|Lateral raise|10|10',
        'Single-leg RDL reach|Single-leg stand||',
      ];
      for (var w = 0; w < 2; w++) {
        final entries = await repo.list('entry', parentId: workouts[w].id);
        expect(entries, hasLength(14));
        final expectedCategories = [...categories];
        if (w == 1) {
          expectedCategories[3] = 'Primary Pull';
          expectedCategories[4] = 'Primary Push';
          expectedCategories[6] = 'Secondary Pull';
          expectedCategories[7] = 'Secondary Push';
        }
        expect(entries.map((e) => e.values['category']), expectedCategories);
        final expected = w == 0 ? tuesday : thursday;
        for (var i = 0; i < entries.length; i++) {
          expect(entries[i].values['selectedAlternative'], 0);
          final row = expected[i].split('|');
          for (var option = 0; option < 2; option++) {
            final target = await repo.resolvedEntry(
              entries[i],
              alternative: option,
            );
            expect(target['exerciseName'], row[option]);
            expect(target['load'], num.tryParse(row[option + 2]));
            expect(target['loadUnit'], isNull);
            expect(target['progression'], 'Manual');
            expect(target['optional'], i >= 12);
            expect(
              target['sets'],
              i == 0
                  ? 1
                  : w == 0 && i == 10
                  ? 3
                  : 2,
            );
            final timed = i == 0 || i == 8 || i == 13 || w == 1 && i == 10;
            expect(
              target['reps'],
              timed || i == 1
                  ? null
                  : i == 11
                  ? 12
                  : i == 10
                  ? 5
                  : 10,
            );
            expect(target['repsMax'], i == 11 ? 15 : null);
            expect(
              target['durationSeconds'],
              timed
                  ? i == 0
                        ? 300
                        : 30
                  : null,
            );
            expect(target['durationMaxSeconds'], i == 8 ? 45 : null);
            expect(target['repsUnknown'], i == 1);
            if (i == 8) expect(target['notes'], contains('Grain bucket'));
            if (i == 13 || i == 8 && w == 1) {
              expect(
                (target['notes'] as String).toLowerCase(),
                contains('per side'),
              );
            }
          }
        }
      }
      final heavy = await repo.list('entry', parentId: workouts.last.id);
      expect(heavy.map((e) => e.name), [
        'Full-body athletic warmup',
        'Loaded Squat',
        'Chest Press',
        'Lat Pulldown',
        'Machine Deadlift',
        'Rear Fly on Yoga Ball',
        'Curl Ups',
      ]);
      expect(heavy.map((e) => e.values['category']), [
        'Warmup',
        'Squat',
        'Push',
        'Pull',
        'Hinge',
        'Pull',
        'Abs',
      ]);
      expect(heavy.map((e) => e.values['load']), [
        null,
        120,
        90,
        90,
        100,
        20,
        null,
      ]);
      for (var i = 0; i < heavy.length; i++) {
        final t = await repo.resolvedEntry(heavy[i]);
        expect(t['sets'], i == 0 ? 1 : 3);
        expect(t['reps'], i == 0 ? null : 5);
        expect(t['durationSeconds'], isNull);
      }
      expect(await repo.list('schedule'), isEmpty);
      expect(
        (await repo.list(
          'exercise',
        )).where((e) => e.name.toLowerCase() == 'chest press'),
        hasLength(1),
      );
    },
  );

  test(
    'each workout starts and completes, quality and timed actuals persist without automatic increases',
    () async {
      await seedPersonalWorkouts(repo);
      for (final workout in await imported()) {
        final entries = await repo.list('entry', parentId: workout.id);
        final original = entries.map((e) => jsonEncode(e.values)).toList();
        final session = await sessions.start(workout.id);
        expect(
          session.exercises.map((e) => e['name']),
          entries.map((e) => e.name),
        );
        for (var i = 0; i < session.exercises.length; i++) {
          if (session.exercises[i]['target']['optional'] == true) {
            await sessions.skip(session.id, i, true);
            continue;
          }
          for (
            var set = 0;
            set < (session.exercises[i]['actualSets'] as List).length;
            set++
          ) {
            final target = session.exercises[i]['target'] as Map;
            await sessions.editSet(session.id, i, set, {
              if ((target['type'] as String).startsWith('timed'))
                'durationSeconds': 40
              else
                'reps': target['reps'] ?? 4,
              if (target['load'] != null) 'load': target['load'],
            });
            await sessions.completeSet(session.id, i, set);
          }
        }
        final finished = await sessions.finish(session.id);
        expect(finished.status, 'completed');
        expect(finished.completedSets, greaterThan(0));
        expect(
          (await repo.list(
            'entry',
            parentId: workout.id,
          )).map((e) => jsonEncode(e.values)).toList(),
          original,
        );
        expect(
          (await sessions.start(workout.id)).exercises.first['previous'],
          isNotNull,
        );
        await sessions.finish((await sessions.unfinished())!.id, cancel: true);
      }
    },
  );

  test(
    'switching A/B preserves both identities, actuals, targets and immutable history',
    () async {
      await seedPersonalWorkouts(repo);
      final tuesday = (await imported()).first;
      final session = await sessions.start(tuesday.id);
      final originalId = session.exercises[2]['exerciseId'];
      await sessions.editSet(session.id, 2, 0, {'load': 15, 'reps': 8});
      await sessions.completeSet(session.id, 2, 0);
      var changed = await sessions.switchAlternative(session.id, 2, 1);
      final otherId = changed.exercises[2]['exerciseId'];
      expect(otherId, isNot(originalId));
      expect(changed.exercises[2]['name'], 'Bodyweight squat');
      expect(changed.exercises[2]['target']['load'], isNull);
      await sessions.editSet(session.id, 2, 0, {'reps': 12});
      await sessions.completeSet(session.id, 2, 0);
      changed = await sessions.switchAlternative(session.id, 2, 0);
      expect(changed.exercises[2]['actualSets'][0]['load'], 15);
      expect(changed.completedSets, 2);
      final finished = await sessions.finish(session.id);
      final frozen = jsonEncode(finished.data);
      expect(
        (await sessions.previous(originalId as int))!['sets'][0]['load'],
        15,
      );
      expect((await sessions.previous(otherId as int))!['sets'][0]['reps'], 12);
      final entry = (await repo.list('entry', parentId: tuesday.id))[2];
      await repo.edit(entry.id, selectWorkoutAlternative(entry.values, 1));
      await repo.edit(entry.id, {
        ...(await repo.get(entry.id)).values,
        'reps': 20,
      });
      final next = await sessions.start(tuesday.id);
      expect(next.exercises[2]['name'], 'Bodyweight squat');
      expect(next.exercises[2]['target']['reps'], 20);
      expect(
        (await repo.resolvedEntry(
          await repo.get(entry.id),
          alternative: 0,
        ))['load'],
        10,
      );
      expect(jsonEncode((await sessions.get(finished.id)).data), frozen);
      await expectLater(
        sessions.switchAlternative(finished.id, 2, 1),
        throwsStateError,
      );
    },
  );

  test(
    'session target changes and previous actuals preserve template targets and recorded sets',
    () async {
      await seedPersonalWorkouts(repo);
      final workout = (await imported()).last;
      var session = await sessions.start(workout.id);
      await sessions.editSet(session.id, 1, 0, {'load': 125, 'reps': 4});
      await sessions.completeSet(session.id, 1, 0);
      await sessions.finish(session.id);
      session = await sessions.start(workout.id);
      session = await sessions.usePrevious(session.id, 1);
      expect(session.exercises[1]['actualSets'][0]['load'], 125);
      expect(session.exercises[1]['actualSets'][0]['completed'], false);
      expect(session.exercises[1]['target']['load'], 125);
      await sessions.completeSet(session.id, 1, 0);
      session = await sessions.editTargets(session.id, 1, {
        'sets': 4,
        'load': 130,
        'reps': 6,
      });
      expect(session.exercises[1]['actualSets'], hasLength(4));
      expect(session.exercises[1]['actualSets'][0]['load'], 125);
      expect(session.exercises[1]['target']['load'], 130);
      await sessions.editSet(session.id, 1, 3, {'reps': 3});
      await expectLater(
        sessions.editTargets(session.id, 1, {'sets': 3}),
        throwsStateError,
      );
      await expectLater(
        sessions.editTargets(session.id, 1, {'sets': 0}),
        throwsArgumentError,
      );
      final entry = (await repo.list('entry', parentId: workout.id))[1];
      expect((await repo.resolvedEntry(entry))['load'], 120);
    },
  );

  test(
    'copying into an existing rotating program leaves its schedule and overrides unchanged',
    () async {
      await repo.initialize();
      final original = (await repo.list('program')).first;
      await repo.edit(original.id, {...original.values, 'weekOverride': 1});
      final rules = (await repo.list(
        'schedule',
      )).map((r) => jsonEncode(r.values)).toList();
      final source = (await imported()).first;
      final copiedId = await repo.copyWorkoutToProgram(source.id, original.id);
      expect((await repo.get(copiedId)).parentId, original.id);
      expect(await repo.list('entry', parentId: copiedId), hasLength(14));
      expect(
        (await repo.list('schedule')).map((r) => jsonEncode(r.values)).toList(),
        rules,
      );
      expect((await repo.get(original.id)).values['weekOverride'], 1);
      expect(
        (await repo.get(original.id)).values['anchor'],
        original.values['anchor'],
      );
    },
  );

  test(
    'import and unfinished alternative actuals survive reopening without duplicates',
    () async {
      final dir = await Directory.systemTemp.createTemp('personal_plan_');
      final file = File('${dir.path}/plan.sqlite');
      final firstDb = AppDatabase.forTesting(NativeDatabase(file));
      final first = WorkoutRepository(firstDb);
      await first.initialize();
      final program = (await first.list(
        'program',
      )).singleWhere((p) => p.values['importKey'] == personalPlanKey);
      final workout = (await first.list('workout', parentId: program.id)).first;
      final firstSessions = SessionRepository(firstDb, first);
      final active = await firstSessions.start(workout.id);
      await firstSessions.editSet(active.id, 2, 0, {'load': 11, 'reps': 9});
      await firstSessions.switchAlternative(active.id, 2, 1);
      await firstDb.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final second = WorkoutRepository(reopened);
        await second.initialize();
        expect(
          await second.list('workout', parentId: program.id),
          hasLength(3),
        );
        final recovered = SessionRepository(reopened, second);
        expect(
          (await recovered.unfinished())!.exercises[2]['name'],
          'Bodyweight squat',
        );
        expect(
          (await recovered.switchAlternative(
            active.id,
            2,
            0,
          )).exercises[2]['actualSets'][0]['load'],
          11,
        );
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
