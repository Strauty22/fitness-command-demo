import 'dart:io';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/core/database/management_schema.dart';
import 'package:fitness_command/core/database/session_schema.dart';
import 'package:fitness_command/core/database/ride_schema.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';

class LegacyV8 extends AppDatabase {
  LegacyV8(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 8;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
      await enableHistoryEditing();
      await createRideSchema(this);
      await createRideDeletionSchema(this);
      await customStatement(
        'CREATE TABLE ride_annotations (ride_id TEXT PRIMARY KEY REFERENCES ride_sessions(id) ON DELETE CASCADE, name TEXT, personal_best INTEGER NOT NULL DEFAULT 0, notes TEXT)',
      );
    },
  );
}

Ride capture(String id, int millis) => Ride({
  'id': id,
  'status': 'completed',
  'startedAt': 0,
  'endedAt': millis,
  'activeMillis': millis,
  'distanceMetres': 5000,
  'acceptedPoints': 1,
  'description': 'Standing Bear Solo',
  'name': 'Road Cycling',
  'notes': 'Original notes',
});

void main() {
  test(
    'v8 descriptions survive migration/edit/restart and recategorize PBs without changing capture',
    () async {
      final dir = await Directory.systemTemp.createTemp('ride_description');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/rides.sqlite');
      final old = LegacyV8(NativeDatabase(file));
      final slow = capture('slow', 1000000), fast = capture('fast', 500000);
      await RideRepository(old).importCapture(slow, []);
      await RideRepository(old).importCapture(fast, []);
      await RideRepository(
        old,
      ).annotate('fast', personalBest: false, name: 'Legacy name');
      await RideRepository(old).saveNotes('fast', 'Edited notes');
      final before =
          (await old
                  .customSelect('SELECT * FROM ride_sessions ORDER BY id')
                  .get())
              .map((r) => r.data)
              .toList();
      await old.close();
      var db = AppDatabase.forTesting(NativeDatabase(file));
      var repo = RideRepository(db);
      expect(savedRideName((await repo.get('fast'))!), 'Standing Bear Solo');
      expect(personalBestRides(await repo.history()).single.id, 'fast');
      await repo.saveDescription('fast', ' Standing Bear w Wes ');
      expect(personalBestRides(await repo.history()).map((r) => r.id), [
        'slow',
        'fast',
      ]);
      expect((await repo.get('fast'))!.notes, 'Edited notes');
      expect((await repo.get('fast'))!.data['name'], 'Legacy name');
      await repo.importCapture(fast, []);
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      repo = RideRepository(db);
      expect(savedRideName((await repo.get('fast'))!), 'Standing Bear w Wes');
      expect((await repo.get('fast'))!.notes, 'Edited notes');
      expect(
        (await db.customSelect('SELECT * FROM ride_sessions ORDER BY id').get())
            .map((r) => r.data)
            .toList(),
        before,
      );
      await repo.saveDescription('fast', 'standing bear SOLO');
      expect(personalBestRides(await repo.history()).single.id, 'fast');
      await repo.deleteHistory('fast');
      expect(personalBestRides(await repo.history()).single.id, 'slow');
      await repo.deleteHistory('slow');
      expect(personalBestRides(await repo.history()), isEmpty);
      await expectLater(
        repo.saveDescription('fast', 'Missing'),
        throwsStateError,
      );
      await db.close();
    },
  );
}
