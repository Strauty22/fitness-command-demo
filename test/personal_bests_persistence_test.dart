import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/core/database/management_schema.dart';
import 'package:fitness_command/core/database/session_schema.dart';
import 'package:fitness_command/core/database/ride_schema.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/history/history_data.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';

class LegacyV6 extends AppDatabase {
  LegacyV6(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 6;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
      await enableHistoryEditing();
      await createRideSchema(this);
      await createRideDeletionSchema(this);
    },
  );
}

Ride capture(
  String id, {
  String status = 'completed',
  int duration = 1000000,
}) => Ride({
  'id': id,
  'name': 'Original name',
  'status': status,
  'startedAt': 0,
  'endedAt': duration,
  'activeMillis': duration,
  'acceptedPoints': 1,
  'distanceMetres': 5000,
  'notes': 'Original notes',
});

void main() {
  test(
    'v6 migration defaults PB false; annotations preserve GPS payload and survive recovery/restart/deletion',
    () async {
      final dir = await Directory.systemTemp.createTemp('pb_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      final old = LegacyV6(NativeDatabase(file));
      final original = capture('old');
      await RideRepository(old).importCapture(original, []);
      final before =
          (await old
                  .customSelect('SELECT payload FROM ride_sessions')
                  .getSingle())
              .read<String>('payload');
      await old.close();
      var db = AppDatabase.forTesting(NativeDatabase(file));
      var repo = RideRepository(db);
      expect((await repo.get('old'))!.personalBest, false);
      await repo.annotate(
        'old',
        personalBest: true,
        name: ' Standing Bear Solo ',
      );
      await repo.importCapture(original, []);
      expect(
        (await db.customSelect('SELECT payload FROM ride_sessions').getSingle())
            .read<String>('payload'),
        before,
      );
      expect((await repo.get('old'))!.notes, 'Original notes');
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      repo = RideRepository(db);
      expect((await repo.get('old'))!.personalBest, true);
      expect((await repo.get('old'))!.data['name'], ' Standing Bear Solo ');
      await repo.importCapture(capture('faster', duration: 500000), []);
      await repo.annotate(
        'faster',
        personalBest: true,
        name: 'standing bear solo',
      );
      expect(personalBestRides(await repo.history()).single.id, 'faster');
      await repo.annotate('faster', personalBest: false);
      expect(personalBestRides(await repo.history()).single.id, 'faster');
      await repo.annotate('faster', personalBest: true);
      await repo.deleteHistory('faster');
      expect(personalBestRides(await repo.history()).single.id, 'old');
      await repo.deleteHistory('old');
      expect(personalBestRides(await repo.history()), isEmpty);
      expect(
        await db.customSelect('SELECT * FROM ride_annotations').get(),
        isEmpty,
      );
      await db.close();
    },
  );

  test(
    'completed history drives counts and PBs; cancellation and unsaved rides remain stored but excluded',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workouts = WorkoutRepository(db);
      final p = await workouts.create('program', {
        'name': 'Test',
        'cycle': ['A'],
        'anchor': '2026-11-01',
      });
      final e = await workouts.create('exercise', {
        'name': 'Press',
        'type': 'weighted',
        'loadUnit': 'lb',
      });
      final w = await workouts.create('workout', {'name': 'Test'}, parentId: p);
      await workouts.create('entry', {
        'name': 'Press',
        'exerciseId': e,
        'sets': 2,
        'reps': 10,
        'load': 100,
        'loadUnit': 'lb',
      }, parentId: w);
      final sessions = SessionRepository(db, workouts);
      final partial = await sessions.start(w);
      await sessions.completeSet(partial.id, 0, 0);
      await sessions.finish(partial.id);
      final snapshot = jsonEncode((await sessions.get(partial.id)).data);
      final cancelled = await sessions.start(w);
      await sessions.editSet(cancelled.id, 0, 0, {'load': 999});
      await sessions.completeSet(cancelled.id, 0, 0);
      await sessions.finish(cancelled.id, cancel: true);
      await sessions.start(w);
      final rides = RideRepository(db);
      await rides.importCapture(capture('saved'), []);
      await rides.importCapture(capture('discarded', status: 'discarded'), []);
      await rides.importCapture(capture('unsaved', status: 'review'), []);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      var entries = await container.read(combinedHistoryProvider.future);
      expect(entries.where((e) => e.ride != null), hasLength(1));
      expect(entries.where((e) => e.session != null), hasLength(1));
      expect(exerciseBests(await sessions.history()).single.pounds, 100);
      expect((await sessions.get(cancelled.id)).status, 'cancelled');
      expect(jsonEncode((await sessions.get(partial.id)).data), snapshot);
      await rides.deleteHistory('saved');
      container.read(rideRevisionProvider.notifier).refresh();
      entries = await container.read(combinedHistoryProvider.future);
      expect(entries.where((e) => e.ride != null), isEmpty);
      await sessions.deleteHistory(partial.id);
      container.read(sessionRevisionProvider.notifier).refresh();
      entries = await container.read(combinedHistoryProvider.future);
      expect(entries, isEmpty);
      expect(exerciseBests(await sessions.history()), isEmpty);
    },
  );
}
