import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';

void main() {
  test(
    'completion persists future target, mode switch, override and frozen history',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final w = WorkoutRepository(db);
      final sessions = SessionRepository(db, w);
      final p = await w.create('program', {
        'name': 'P',
        'cycle': ['A'],
        'anchor': '2026-10-19',
      });
      final workout = await w.create('workout', {'name': 'W'}, parentId: p);
      final exercise = await w.create('exercise', {
        'name': 'E',
        'type': 'weighted',
        'load': 100,
        'loadUnit': 'lb',
        'sets': 2,
        'reps': 10,
        'progression': 'Progress',
        'increment': 2.5,
        'successCount': 1,
      });
      final entry = await w.create('entry', {
        'name': 'E',
        'exerciseId': exercise,
      }, parentId: workout);
      final session = await sessions.start(workout);
      for (var i = 0; i < 2; i++) {
        await sessions.completeSet(session.id, 0, i);
      }
      final finished = await sessions.finish(session.id);
      final frozen = jsonEncode(finished.data);
      await sessions.finish(session.id);
      expect((await w.resolvedEntry(await w.get(entry)))['load'], 102.5);
      final record = await w.get(exercise);
      await w.edit(exercise, {...record.values, 'progression': 'Maintain'});
      expect((await w.resolvedEntry(await w.get(entry)))['load'], 102.5);
      await w.edit(exercise, {...(await w.get(exercise)).values, 'load': 80});
      expect((await w.resolvedEntry(await w.get(entry)))['load'], 80);
      expect(jsonEncode((await sessions.get(session.id)).data), frozen);
      expect(
        (await sessions.start(workout)).exercises.first['target']['load'],
        80,
      );
    },
  );
}
