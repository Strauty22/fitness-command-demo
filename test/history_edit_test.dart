import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/core/database/management_schema.dart';
import 'package:fitness_command/core/database/session_schema.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';
import 'package:fitness_command/features/strength/data/strength_session.dart';

class LegacyDatabase extends AppDatabase {
  LegacyDatabase(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
    },
  );
}

void main() {
  test(
    'working loads respect manual edits, mode, units and latest actuals',
    () {
      final target = <String, dynamic>{
        'type': 'weighted',
        'load': 20,
        'loadUnit': 'kg',
        'progression': 'Manual',
        'sets': 2,
        'reps': 5,
      };
      final previous = <String, dynamic>{
        'target': {...target},
        'sets': [
          {'load': 22},
          {'load': 24},
        ],
      };
      expect(workingTarget(target, previous)['load'], 24);
      expect(
        workingTarget(target, {
          'target': workingTarget(target, previous),
          'sets': [
            {'load': 26},
          ],
        })['load'],
        26,
      );
      expect(workingTarget({...target, 'load': 30}, previous)['load'], 30);
      expect(
        workingTarget({...target, 'progression': 'Maintain'}, previous)['load'],
        20,
      );
      expect(
        workingTarget({...target, 'progression': 'Progress'}, previous)['load'],
        20,
      );
      expect(
        workingTarget({...target, 'loadUnit': 'lb'}, previous)['load'],
        20,
      );
      expect(workingTarget(target, null)['load'], 20);
      expect(target['load'], 20);
    },
  );

  test(
    'v3 migration preserves data, edits snapshots atomically, deletes only selected history',
    () async {
      final dir = await Directory.systemTemp.createTemp('history_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final old = LegacyDatabase(NativeDatabase(file));
      final workouts = WorkoutRepository(old);
      await workouts.seed();
      final sessions = SessionRepository(old, workouts);
      final template = (await workouts.list('workout')).first;
      final session = await sessions.start(template.id);
      await sessions.completeSet(session.id, 2, 0);
      await sessions.finish(session.id);
      await WorkoutDiscoveryRepository(workouts).selectWorkout(template.id);
      final before = jsonEncode((await workouts.get(template.id)).values);
      await old.close();
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final repo = SessionRepository(db, WorkoutRepository(db));
      try {
        expect((await repo.history()).single.id, session.id);
        expect(
          await WorkoutDiscoveryRepository(
            WorkoutRepository(db),
          ).selectedWorkout(),
          template.id,
        );
        expect(await repo.unfinished(), isNull);
        await repo.editHistorySet(session.id, 2, 0, {'load': 22, 'reps': 8});
        expect(
          (await repo.get(session.id)).exercises[2]['actualSets'][0]['load'],
          22,
        );
        final snapshot = await db
            .customSelect('SELECT payload FROM completed_snapshots')
            .getSingle();
        expect(
          jsonDecode(
            snapshot.read<String>('payload'),
          )['exercises'][2]['actualSets'][0]['reps'],
          8,
        );
        await expectLater(
          repo.editHistorySet(session.id, 2, 0, {'load': -1}),
          throwsArgumentError,
        );
        await expectLater(
          repo.editHistorySet(session.id, 99, 0, {'load': 1}),
          throwsRangeError,
        );
        expect(
          await db.customSelect('SELECT * FROM history_edit_permission').get(),
          isEmpty,
        );
        await expectLater(
          db.customStatement("UPDATE strength_sessions SET payload = '{}'"),
          throwsA(anything),
        );
        final next = await repo.start(template.id);
        await expectLater(repo.deleteHistory(next.id), throwsStateError);
        await repo.finish(next.id);
        await repo.deleteHistory(session.id);
        expect((await repo.history()).single.id, next.id);
        expect(
          await db.customSelect('SELECT * FROM completed_snapshots').get(),
          hasLength(1),
        );
        expect(
          jsonEncode((await WorkoutRepository(db).get(template.id)).values),
          before,
        );
      } finally {
        await db.close();
      }
    },
  );
}
