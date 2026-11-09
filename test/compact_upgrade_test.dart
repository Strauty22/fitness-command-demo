import 'package:fitness_command/features/strength/compact_prescription.dart';
import 'package:fitness_command/features/workout/data/personal_workout_seed.dart';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';

void main() {
  test(
    'old imported snapshots display pounds without changing stored measurements',
    () {
      final old = <String, dynamic>{
        'importKey': personalPlanKey,
        'load': 70,
        'reps': 10,
      };
      expect(compactPrescription(old, 2), '2\u00d710  70 lb');
      expect(old.containsKey('loadUnit'), false);
      expect(displayLoadUnit({'load': 70}), '');
      expect(displayLoadUnit({...old, 'loadUnit': 'kg'}), 'kg');
    },
  );

  test(
    'six variants reuse identities, select options, preserve history and upgrade once',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = WorkoutRepository(db);
      await repo.initialize();
      final sources = await repo.list('workout');
      final source = sources.singleWhere((w) => w.name == 'Tuesday');
      final exercises = await repo.list('exercise');
      final sessions = SessionRepository(db, repo);
      final active = await sessions.start(source.id);
      await sessions.completeSet(active.id, 1, 0);
      final finished = await sessions.finish(active.id);
      final historical = jsonEncode(finished.data);
      final unrelated = sources.first;
      final legacy = jsonEncode(
        (await repo.list(
          'entry',
          parentId: unrelated.id,
        )).map((e) => e.values).toList(),
      );
      var variants = await ensureCompactWorkouts(repo);
      expect(variants.map((w) => w.name), compactVariantNames);
      expect(
        (await repo.list('exercise')).map((e) => e.id),
        exercises.map((e) => e.id),
      );
      for (final variant in variants) {
        final original = sources.singleWhere(
          (s) => s.name == variant.name.split(' ').first,
        );
        final before = await repo.list('entry', parentId: original.id);
        final after = await repo.list('entry', parentId: variant.id);
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          final options = before[i].values['alternatives'] as List?;
          final option =
              variant.name.endsWith('B') &&
                  options != null &&
                  options.length > 1
              ? 1
              : 0;
          final expected = options == null
              ? before[i].values
              : options[option] as Map;
          expect(after[i].values['exerciseId'], expected['exerciseId']);
          expect(after[i].values['load'], expected['load']);
          expect(after[i].values['loadUnit'], 'lb');
        }
      }
      final count = (await repo.list('workout')).length;
      final entry = (await repo.list(
        'entry',
        parentId: variants.first.id,
      )).first;
      await repo.edit(entry.id, {...entry.values, 'loadUnit': 'kg'});
      variants = await ensureCompactWorkouts(repo);
      expect(variants.length, 6);
      expect((await repo.list('workout')).length, count);
      expect((await repo.get(entry.id)).values['loadUnit'], 'kg');
      expect(jsonEncode((await sessions.get(finished.id)).data), historical);
      expect(
        jsonEncode(
          (await repo.list(
            'entry',
            parentId: unrelated.id,
          )).map((e) => e.values).toList(),
        ),
        legacy,
      );
      expect(await sessions.unfinished(), isNull);
    },
  );
}
