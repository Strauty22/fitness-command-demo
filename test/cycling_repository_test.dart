import 'package:fitness_command/features/cycling/widgets/map_projection.dart';
import 'dart:typed_data';
import 'package:fitness_command/features/cycling/data/map_tile_repository.dart';
import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/core/database/management_schema.dart';
import 'package:fitness_command/core/database/session_schema.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/cycling/data/ride_controller.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'fakes/fake_ride_platform.dart';

class LegacyV4 extends AppDatabase {
  LegacyV4(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 4;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
      await enableHistoryEditing();
    },
  );
}

void main() {
  test(
    'ride deletion is atomic, isolated and survives native reimport',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RideRepository(db);
      final workouts = WorkoutRepository(db);
      await workouts.seed();
      final sessions = SessionRepository(db, workouts);
      final session = await sessions.start(
        (await workouts.list('workout')).first.id,
      );
      await sessions.finish(session.id);
      final snapshot = jsonEncode((await sessions.get(session.id)).data);
      Ride ride(String id) => Ride({
        'id': id,
        'status': 'completed',
        'startedAt': 1000,
        'endedAt': 2000,
        'activeMillis': 1000,
        'distanceMetres': 100,
      });
      final point = RidePoint(
        sequence: 1,
        segment: 0,
        time: DateTime.fromMillisecondsSinceEpoch(1000),
        latitude: 41,
        longitude: -87,
        accuracy: 3,
      );
      await repo.importCapture(ride('delete'), [point]);
      await repo.importCapture(ride('keep'), [point]);
      await db.customStatement(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON ride_sessions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        repo.deleteHistory('delete'),
        throwsA(isA<Exception>()),
      );
      expect(await repo.isDeleted('delete'), false);
      expect(await repo.get('delete'), isNotNull);
      expect(await repo.points('delete'), hasLength(1));
      await db.customStatement('DROP TRIGGER fail_delete');
      await repo.deleteHistory('delete');
      await repo.importCapture(ride('delete'), [point]);
      expect(await repo.get('delete'), isNull);
      expect(await repo.lastSequence('delete'), 0);
      expect((await repo.history()).map((r) => r.id), ['keep']);
      expect(await repo.points('keep'), hasLength(1));
      expect(jsonEncode((await sessions.get(session.id)).data), snapshot);
    },
  );

  test(
    'map projection roundtrips locations and wraps without a 180 degree shift',
    () {
      for (final location in [
        (41.88, -87.63),
        (0.0, 0.0),
        (84.0, 179.99),
        (-40.0, -179.99),
      ]) {
        final point = MapProjection.project(location.$1, location.$2, 16);
        final restored = MapProjection.unproject(point, 16);
        expect(restored.$1, closeTo(location.$1, .00001));
        expect(restored.$2, closeTo(location.$2, .00001));
        final wrapped = MapProjection.unproject(
          point + Offset(MapProjection.worldSize(16), 0),
          16,
        );
        expect(wrapped.$2, closeTo(location.$2, .00001));
      }
    },
  );

  test('demo map stays synthetic with or without cached native tiles', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = MapTileRepository(db);
    try {
      expect(await repo.tile(2, 1, 1), isNull);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await db.customStatement(
        'INSERT INTO ride_map_tiles(tile_key,bytes,expires_at,fetched_at) VALUES (?,?,?,?)',
        [
          '2/1/1',
          bytes,
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      expect(await repo.tile(2, 1, 1), isNull);
      // The demo does not display or alter leftover native map cache data.
      final cached = await db
          .customSelect('SELECT bytes FROM ride_map_tiles')
          .getSingle();
      expect(cached.read<Uint8List>('bytes'), bytes);
      repo.retry();
      expect(await repo.tile(2, 1, 1), isNull);
      expect(repo.unavailable.value, false);
    } finally {
      repo.close();
      await db.close();
    }
  });

  test(
    'preview restarts on re-entry, stops while recording and ignores rejected GPS jumps',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory()),
          platform = FakeRidePlatform();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ridePlatformProvider.overrideWithValue(platform),
        ],
      );
      try {
        final controller = container.read(rideControllerProvider.notifier);
        await controller.enter();
        expect(platform.previewEnabled, true);
        await controller.leavePreview();
        expect(platform.previewEnabled, false);
        await controller.enter();
        expect(platform.previewEnabled, true);
        await controller.act('start');
        expect(platform.previewEnabled, false);
        final point = {
          'sequence': 1,
          'time': DateTime.now().millisecondsSinceEpoch,
          'latitude': 41.0,
          'longitude': -87.0,
          'accuracy': 3,
          'reason': 'moving',
        };
        platform.stream.add({'type': 'fix', 'point': point});
        await Future<void>.delayed(Duration.zero);
        expect(container.read(rideControllerProvider).location!.latitude, 41);
        platform.stream.add({
          'type': 'fix',
          'point': {...point, 'latitude': 80.0, 'reason': 'GPS jump'},
        });
        await Future<void>.delayed(Duration.zero);
        expect(container.read(rideControllerProvider).location!.latitude, 41);
      } finally {
        container.dispose();
        await platform.stream.close();
        await db.close();
      }
    },
  );

  test('distance units and unknown measurements remain honest', () {
    expect(gpsDistance(0, 0, 0, 1), closeTo(111194.9266, .1));
    expect(gpsDistance(0, 179.999, 0, -179.999), lessThan(250));
    final ride = Ride({
      'id': 'r',
      'status': 'recording',
      'startedAt': 0,
      'activeSince': 1000,
      'activeMillis': 3000,
      'acceptedPoints': 0,
      'distanceMetres': 0,
    });
    expect(ride.metres, isNull);
    expect(
      ride.averageSpeed(DateTime.fromMillisecondsSinceEpoch(2000)),
      isNull,
    );
    expect(
      ride.activeMilliseconds(DateTime.fromMillisecondsSinceEpoch(2000)),
      4000,
    );
    expect(ride.currentSpeed(DateTime.now()), isNull);
    expect(ride.elevation, isNull);
    expect(ride.maximum, isNull);
    expect(rideDuration(3661000), '1:01:01');
  });
  test(
    'version 4 migration adds rides without altering strength history; route import survives reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('cycling_migration');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final old = LegacyV4(NativeDatabase(file));
      final workouts = WorkoutRepository(old);
      await workouts.seed();
      final sessions = SessionRepository(old, workouts);
      final session = await sessions.start(
        (await workouts.list('workout')).first.id,
      );
      await sessions.finish(session.id);
      final before = jsonEncode((await sessions.get(session.id)).data);
      await old.close();
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final repo = RideRepository(db);
      final ride = Ride({
        'id': 'r',
        'status': 'completed',
        'startedAt': 1000,
        'endedAt': 11000,
        'activeMillis': 8000,
        'acceptedPoints': 2,
        'distanceMetres': 10,
        'movingMillis': 6000,
        'notes': 'Local ride',
      });
      final point = RidePoint(
        sequence: 1,
        segment: 0,
        time: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        latitude: 41,
        longitude: -87,
        accuracy: 3,
      );
      await repo.importCapture(ride, [point]);
      await repo.importCapture(ride, [point]);
      expect(await repo.points('r'), hasLength(1));
      await expectLater(
        repo.importCapture(Ride({...ride.data, 'distanceMetres': 999}), []),
        throwsStateError,
      );
      expect(
        jsonEncode(
          (await SessionRepository(
            db,
            WorkoutRepository(db),
          ).get(session.id)).data,
        ),
        before,
      );
      await db.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect(
          (await RideRepository(reopened).history()).single.notes,
          'Local ride',
        );
        expect(await RideRepository(reopened).points('r'), hasLength(1));
        expect(
          (await reopened.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          9,
        );
      } finally {
        await reopened.close();
      }
    },
  );
  test(
    'native-adapter lifecycle creates only on start, prevents duplicates, mirrors pause/resume/review/save',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final platform = FakeRidePlatform();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ridePlatformProvider.overrideWithValue(platform),
        ],
      );
      try {
        final controller = container.read(rideControllerProvider.notifier);
        await controller.initialize();
        expect(platform.starts, 0);
        expect(await RideRepository(db).history(), isEmpty);
        final starts = await Future.wait([
          controller.act('start'),
          controller.act('start'),
        ]);
        expect(starts.where((r) => r), hasLength(1));
        expect(platform.starts, 1);
        platform.now = platform.now.add(const Duration(seconds: 3));
        platform.fix();
        await controller.sync();
        final id = container.read(rideControllerProvider).ride!.id;
        expect((await RideRepository(db).points(id)), hasLength(1));
        platform.now = platform.now.add(const Duration(seconds: 5));
        expect(await controller.act('pause'), true);
        final paused = container.read(rideControllerProvider).ride!;
        final active = paused.activeMilliseconds(platform.now);
        platform.now = platform.now.add(const Duration(minutes: 2));
        platform.fix();
        expect(paused.activeMilliseconds(platform.now), active);
        expect(await controller.act('resume'), true);
        platform.now = platform.now.add(const Duration(seconds: 3));
        platform.fix();
        await controller.sync();
        final points = await RideRepository(db).points(id);
        expect(points, hasLength(2));
        expect(points.first.segment, isNot(points.last.segment));
        await controller.act('pause');
        await controller.act('review');
        expect(container.read(rideControllerProvider).ride!.status, 'review');
        await controller.act('save', notes: 'Test notes');
        expect((await RideRepository(db).history()).single.notes, 'Test notes');
      } finally {
        container.dispose();
        await platform.stream.close();
        await db.close();
      }
    },
  );
  test(
    'permissions denied creates no ride; captured review recovers and explicit discard removes route',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final platform = FakeRidePlatform();
      platform.ready['precisePermission'] = false;
      var container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ridePlatformProvider.overrideWithValue(platform),
        ],
      );
      try {
        var controller = container.read(rideControllerProvider.notifier);
        await controller.initialize();
        expect(await controller.act('start'), false);
        expect(platform.starts, 0);
        platform.ready['precisePermission'] = true;
        await controller.act('start');
        platform.fix();
        await controller.sync();
        await controller.act('pause');
        await controller.act('review');
        final id = container.read(rideControllerProvider).ride!.id;
        container.dispose();
        container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ridePlatformProvider.overrideWithValue(platform),
          ],
        );
        controller = container.read(rideControllerProvider.notifier);
        await controller.initialize();
        expect(container.read(rideControllerProvider).ride!.status, 'review');
        await controller.act('discard');
        expect(await RideRepository(db).points(id), isEmpty);
        expect(await RideRepository(db).history(), isEmpty);
      } finally {
        container.dispose();
        await platform.stream.close();
        await db.close();
      }
    },
  );
}
