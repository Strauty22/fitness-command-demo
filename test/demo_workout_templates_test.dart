import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/demo/sample_data.dart';
import 'package:fitness_command/demo/workout_templates.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/workout/data/custom_workout_repository.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  late Map<String, dynamic> source;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db);
    source =
        jsonDecode(await File(workoutTemplatesAsset).readAsString())
            as Map<String, dynamic>;
  });
  tearDown(() => db.close());

  test(
    'imports all asset workouts, targets, alternatives and local identities',
    () async {
      await applyDemoWorkoutTemplates(db, source);
      final variants = await ensureCompactWorkouts(repo);
      final custom = await CustomWorkoutRepository(repo).list();
      for (final raw in source['workouts'] as List) {
        final workout = raw as Map;
        final target = (workout['customWorkout'] == true ? custom : variants)
            .singleWhere((w) => w.name == workout['name']);
        final entries = await repo.list('entry', parentId: target.id);
        final exported = (workout['entries'] as List).cast<Map>().toList()
          ..sort(
            (a, b) => (a['position'] as int).compareTo(b['position'] as int),
          );
        expect(entries.length, exported.length, reason: target.name);
        for (var i = 0; i < entries.length; i++) {
          final expected = {
            ...exported[i]['prescription'] as Map,
            ...exported[i]['overrides'] as Map,
          };
          final actual = entries[i].values;
          for (final field in expected.keys.where(
            (key) => key != 'exerciseId' && key != 'exerciseName',
          )) {
            expect(
              actual[field],
              expected[field],
              reason: '${target.name} $i $field',
            );
          }
          expect(
            (await repo.get(actual['exerciseId'] as int)).name,
            expected['exerciseName'],
          );
          final options = exported[i]['alternatives'] as List?;
          if (options != null) {
            expect(
              actual['selectedAlternative'],
              exported[i]['selectedAlternative'],
            );
            final imported = actual['alternatives'] as List;
            expect(imported.length, options.length);
            for (var j = 0; j < options.length; j++) {
              expect(
                (await repo.get(imported[j]['exerciseId'] as int)).name,
                options[j]['exerciseName'],
              );
              expect(imported[j]['load'], options[j]['load']);
              expect(
                imported[j]['durationSeconds'],
                options[j]['durationSeconds'],
              );
            }
          }
        }
      }
    },
  );

  test(
    'upgrade preserves sample history, snapshots, active actuals and later edits',
    () async {
      await seedDemo(db);
      final variants = await ensureCompactWorkouts(repo);
      final sessions = SessionRepository(db, repo);
      final active = await sessions.start(variants.first.id);
      await sessions.completeSet(active.id, 0, 0);
      Future<String> historyTables() async => jsonEncode([
        for (final table in [
          'strength_sessions',
          'completed_snapshots',
          'ride_sessions',
          'ride_points',
          'ride_annotations',
        ])
          (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
              .map((row) => row.data)
              .toList(),
      ]);
      final before = await historyTables();
      await applyDemoWorkoutTemplates(db, source);
      expect(await historyTables(), before);
      expect(
        (await ensureCompactWorkouts(repo)).map((w) => w.id),
        variants.map((w) => w.id),
      );
      final entry = (await repo.list(
        'entry',
        parentId: variants.first.id,
      )).first;
      await repo.edit(entry.id, {...entry.values, 'durationSeconds': 123});
      final count = (await repo.list('workout')).length;
      await applyDemoWorkoutTemplates(db, source);
      expect((await repo.get(entry.id)).values['durationSeconds'], 123);
      expect((await repo.list('workout')).length, count);
      expect(await historyTables(), before);
    },
  );

  test('invalid template rolls back the entire update', () async {
    await seedDemo(db);
    final before = jsonEncode(
      (await db
              .customSelect('SELECT * FROM management_records ORDER BY id')
              .get())
          .map((row) => row.data)
          .toList(),
    );
    (source['workouts'] as List).last['entries'][0]['overrides']['sets'] = -1;
    await expectLater(
      applyDemoWorkoutTemplates(db, source),
      throwsArgumentError,
    );
    expect(
      jsonEncode(
        (await db
                .customSelect('SELECT * FROM management_records ORDER BY id')
                .get())
            .map((row) => row.data)
            .toList(),
      ),
      before,
    );
  });
}
