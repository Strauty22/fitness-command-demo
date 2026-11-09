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

class LegacyV7 extends AppDatabase {
  LegacyV7(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 7;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
      await enableHistoryEditing();
      await createRideSchema(this);
      await createRideDeletionSchema(this);
      await customStatement(
        'CREATE TABLE ride_annotations (ride_id TEXT PRIMARY KEY REFERENCES ride_sessions(id) ON DELETE CASCADE, name TEXT, personal_best INTEGER NOT NULL DEFAULT 0)',
      );
    },
  );
}

Ride capture(String id, {String? notes, String status = 'completed'}) => Ride({
  'id': id,
  'name': 'Original ride',
  'status': status,
  'startedAt': 1000,
  'endedAt': 61000,
  'activeMillis': 60000,
  'acceptedPoints': 1,
  'distanceMetres': 500,
  'maximumSpeed': 10,
  'notes': ?notes,
});

void main() {
  test(
    'v7 migration and notes edits preserve ride payload, annotations, route and restart persistence',
    () async {
      final dir = await Directory.systemTemp.createTemp('ride_notes');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      final old = LegacyV7(NativeDatabase(file));
      final original = capture('ride', notes: 'Original notes');
      final point = RidePoint(
        sequence: 1,
        segment: 0,
        time: DateTime.utc(2026),
        latitude: 41,
        longitude: -96,
        accuracy: 5,
      );
      await RideRepository(old).importCapture(original, [point]);
      await RideRepository(
        old,
      ).annotate('ride', personalBest: true, name: 'My ride');
      final payload =
          (await old
                  .customSelect('SELECT payload FROM ride_sessions')
                  .getSingle())
              .read<String>('payload');
      final route =
          (await old.customSelect('SELECT * FROM ride_points').getSingle())
              .data;
      await old.close();
      var db = AppDatabase.forTesting(NativeDatabase(file));
      var repo = RideRepository(db);
      expect((await repo.get('ride'))!.notes, 'Original notes');
      final before = (await repo.get('ride'))!.data;
      await repo.saveNotes('ride', 'Edited notes\nSecond line');
      expect((await repo.get('ride'))!.data, {
        ...before,
        'notes': 'Edited notes\nSecond line',
      });
      await repo.importCapture(original, [point]);
      expect((await repo.history()).single.notes, 'Edited notes\nSecond line');
      await repo.annotate('ride', personalBest: false);
      expect((await repo.get('ride'))!.notes, 'Edited notes\nSecond line');
      await repo.annotate('ride', personalBest: true);
      expect(
        (await db.customSelect('SELECT payload FROM ride_sessions').getSingle())
            .read<String>('payload'),
        payload,
      );
      expect(
        (await db.customSelect('SELECT * FROM ride_points').getSingle()).data,
        route,
      );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      repo = RideRepository(db);
      expect((await repo.get('ride'))!.notes, 'Edited notes\nSecond line');
      await repo.saveNotes('ride', '');
      expect((await repo.history()).single.notes, '');
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      repo = RideRepository(db);
      expect((await repo.get('ride'))!.notes, '');
      expect((await repo.get('ride'))!.personalBest, true);
      expect((await repo.get('ride'))!.data['name'], 'My ride');
      expect(await repo.history(), hasLength(1));
      await db.close();
    },
  );

  test(
    'notes can be added without an existing annotation and reject unsaved or missing rides',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RideRepository(db);
      await repo.importCapture(capture('empty'), []);
      await repo.saveNotes('empty', 'Added later');
      expect((await repo.get('empty'))!.notes, 'Added later');
      expect((await repo.get('empty'))!.personalBest, false);
      expect((await repo.get('empty'))!.data['name'], 'Original ride');
      await repo.importCapture(capture('review', status: 'review'), []);
      await expectLater(repo.saveNotes('review', 'No'), throwsStateError);
      await expectLater(repo.saveNotes('missing', 'No'), throwsStateError);
      expect(await repo.history(), hasLength(1));
    },
  );
}
