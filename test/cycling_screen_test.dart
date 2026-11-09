import 'dart:typed_data';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/ride_history_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'package:fitness_command/features/cycling/data/map_tile_repository.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'fakes/fake_ride_platform.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';
import 'package:fitness_command/features/home/data/rotation_repository.dart';

class OfflineTestTiles extends MapTileRepository {
  OfflineTestTiles(super.db);
  final Future<Uint8List?> empty = Future.value(null);
  @override
  Future<Uint8List?> tile(int z, int x, int y) => empty;
}

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late FakeRidePlatform platform;
  late OfflineTestTiles tiles;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    platform = FakeRidePlatform();
    tiles = OfflineTestTiles(db);
  });
  tearDown(() async {
    tiles.close();
    await platform.stream.close();
    await db.close();
  });
  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      rotationClockProvider.overrideWithValue(() => DateTime(2026, 10, 19)),
      ridePlatformProvider.overrideWithValue(platform),
      mapTileRepositoryProvider.overrideWithValue(tiles),
    ],
    child: const FitnessCommandApp(),
  );
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'ride deletion confirms, cancels and refreshes history and progress',
    (tester) async {
      final repo = RideRepository(db);
      final data = {
        'id': 'delete',
        'status': 'completed',
        'startedAt': 1000,
        'endedAt': 2000,
        'activeMillis': 1000,
        'distanceMetres': 100,
        'acceptedPoints': 2,
      };
      platform.rides['delete'] = data;
      await repo.importCapture(Ride(data), []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ridePlatformProvider.overrideWithValue(platform),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  RideHistorySection(),
                  RideHistorySection(progress: true),
                ],
              ),
            ),
          ),
        ),
      );
      await flush(tester);
      expect(find.text('1 saved rides'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete this ride? This will permanently remove the ride and its recorded data.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await flush(tester);
      expect(find.byTooltip('Delete ride'), findsOneWidget);
      expect(await tester.runAsync(() => repo.get('delete')), isNotNull);
      await tester.runAsync(
        () => db.customStatement(
          "CREATE TRIGGER fail_delete BEFORE DELETE ON ride_sessions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
        ),
      );
      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await flush(tester);
      expect(find.textContaining('Could not delete ride:'), findsOneWidget);
      expect(find.byTooltip('Delete ride'), findsOneWidget);
      expect(find.text('1 saved rides'), findsOneWidget);
      await tester.runAsync(
        () => db.customStatement('DROP TRIGGER fail_delete'),
      );
      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await flush(tester);
      expect(find.byTooltip('Delete ride'), findsNothing);
      expect(find.text('1 saved rides'), findsNothing);
      expect(await tester.runAsync(() => repo.get('delete')), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cycling map/stats, explicit start, pause/resume, summary save and integrated history',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      expect(find.text('Current Rotation: Week A'), findsOneWidget);
      await tester.tap(find.byTooltip('Bike ride'));
      await flush(tester);
      expect(find.text('Road Cycling'), findsOneWidget);
      expect(find.text('START WORKOUT').hitTestable(), findsOneWidget);
      expect(platform.starts, 0);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Current speed (mph)').hitTestable(), findsNothing);
      await tester.drag(
        find.text('Distance (mi)').hitTestable().first,
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current speed (mph)').hitTestable(), findsOneWidget);
      await tester.drag(
        find.text('Distance (mi)').hitTestable().first,
        const Offset(0, 280),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current speed (mph)').hitTestable(), findsNothing);

      await tester.drag(
        find.text('Distance (mi)').hitTestable().first,
        const Offset(-350, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('STATISTICS'), findsOneWidget);
      expect(find.text('Current speed (mph)'), findsWidgets);
      final start = find.text('START WORKOUT').hitTestable();
      await tester.tap(start);
      await tester.tap(start);
      await flush(tester);
      expect(platform.starts, 1);
      platform.now = platform.now.add(const Duration(seconds: 3));
      await tester.runAsync(() async {
        platform.fix();
      });
      await flush(tester);
      await tester.tap(find.text('PAUSE').hitTestable());
      await flush(tester);
      expect(find.text('RESUME').hitTestable(), findsOneWidget);
      expect(find.text('FINISH').hitTestable(), findsOneWidget);
      await tester.tap(find.text('RESUME').hitTestable());
      await flush(tester);
      expect(find.text('PAUSE').hitTestable(), findsOneWidget);
      await tester.tap(find.text('PAUSE').hitTestable());
      await flush(tester);
      await tester.tap(find.text('FINISH').hitTestable());
      await flush(tester);
      expect(find.text('Finish ride'), findsOneWidget);
      expect(find.text('Personal Best'), findsNothing);
      await tester.ensureVisible(find.widgetWithText(TextField, 'Description'));
      final descriptionField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Description'),
      );
      expect(descriptionField.controller!.text, '');
      expect(descriptionField.decoration!.hintText, 'Name your ride');
      expect(descriptionField.textCapitalization, TextCapitalization.sentences);
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'standing Bear w Wes',
      );
      expect(
        await tester.runAsync(() => RideRepository(db).history()),
        isEmpty,
      );

      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Ride notes (optional)'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Ride notes (optional)'),
        'test ride',
      );
      await tester.ensureVisible(find.text('SAVE RIDE'));
      await tester.tap(find.text('SAVE RIDE'));
      await flush(tester);
      expect(find.text('Fitness Command'), findsOneWidget);
      final rides = await tester.runAsync(() => RideRepository(db).history());
      expect(rides, hasLength(1));
      expect(rides!.single.notes, 'Test ride');
      expect(rides.single.data['description'], 'Standing Bear w Wes');
      expect(
        savedRideName(personalBestRides(rides).single),
        'Standing Bear w Wes',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await flush(tester);
      expect(find.text('Standing Bear w Wes'), findsOneWidget);
      expect(find.text('Test ride'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Progress'),
        ),
      );
      await flush(tester);
      expect(find.text('Standing Bear w Wes'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await flush(tester);
      await tester.tap(find.text('Standing Bear w Wes'));
      await flush(tester);
      expect(find.text('Distance (mi)'), findsOneWidget);
      expect(find.text('SAVE RIDE'), findsNothing);
      expect(find.text('Personal Best'), findsNothing);
      expect(find.text('Standing Bear w Wes'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'empty new descriptions stay empty in storage and share the fallback PB category',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      for (var n = 0; n < 2; n++) {
        await tester.tap(find.byTooltip('Bike ride'));
        await flush(tester);
        await tester.tap(find.text('START WORKOUT').hitTestable());
        await flush(tester);
        platform.now = platform.now.add(const Duration(seconds: 3));
        await tester.runAsync(() async {
          platform.fix();
        });
        await flush(tester);
        await tester.tap(find.text('PAUSE').hitTestable());
        await flush(tester);
        await tester.tap(find.text('FINISH').hitTestable());
        await flush(tester);
        final field = find.widgetWithText(TextField, 'Description');
        expect(tester.widget<TextField>(field).controller!.text, '');
        await tester.ensureVisible(
          find.widgetWithText(TextField, 'Ride notes (optional)'),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Ride notes (optional)'),
          'test ride',
        );
        await tester.tap(find.text('SAVE RIDE'));
        await flush(tester);
      }
      final rides = (await tester.runAsync(
        () => RideRepository(db).history(),
      ))!;
      expect(rides, hasLength(2));
      expect(rides.every((r) => r.data['description'] == ''), true);
      expect(rides.every((r) => r.notes == 'Test ride'), true);
      expect(rides.every((r) => savedRideName(r) == 'Road Cycling'), true);
      expect(personalBestRides(rides), hasLength(1));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await flush(tester);
      expect(find.text('Road Cycling'), findsNWidgets(2));
      expect(find.text('Test ride'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'denied GPS never starts; audio settings persist; discard requires confirmation',
    (tester) async {
      phone(tester);
      platform.ready['precisePermission'] = false;
      await tester.pumpWidget(app());
      await flush(tester);
      await tester.tap(find.byTooltip('Bike ride'));
      await flush(tester);
      await tester.tap(find.text('START WORKOUT').hitTestable());
      await flush(tester);
      expect(platform.starts, 0);
      await tester.tap(find.byTooltip('Cycling settings'));
      await flush(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every 0.5 mile').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Current speed'));
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(platform.prefs['interval'], 'halfMile');
      expect(platform.prefs['measurements'], contains('speed'));
      platform.ready['precisePermission'] = true;
      await tester.tap(find.text('START WORKOUT').hitTestable());
      await flush(tester);
      await tester.tap(find.text('PAUSE').hitTestable());
      await flush(tester);
      await tester.tap(find.text('FINISH').hitTestable());
      await flush(tester);
      await tester.ensureVisible(find.text('Discard ride'));
      await tester.tap(find.text('Discard ride'));
      await tester.pumpAndSettle();
      expect(find.text('Discard recorded ride?'), findsOneWidget);
      await tester.tap(find.text('Keep ride'));
      await tester.pumpAndSettle();
      expect(platform.rides.values.single['status'], 'review');
      await tester.ensureVisible(find.text('Discard ride'));
      await tester.tap(find.text('Discard ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await flush(tester);
      expect(find.text('Fitness Command'), findsOneWidget);
      expect(
        await tester.runAsync(() => RideRepository(db).history()),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'leaving cycling does not pause background capture or create a duplicate on return',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      await tester.tap(find.byTooltip('Bike ride'));
      await flush(tester);
      await tester.tap(find.text('START WORKOUT').hitTestable());
      await flush(tester);
      await tester.pageBack();
      await flush(tester);
      expect(platform.rides.values.single['status'], 'recording');
      platform.fix();
      await flush(tester);
      await tester.tap(find.byTooltip('Bike ride'));
      await flush(tester);
      expect(find.text('PAUSE').hitTestable(), findsOneWidget);
      expect(platform.starts, 1);
      final controller = tester
          .element(find.text('Road Cycling'))
          .findAncestorWidgetOfExactType<ProviderScope>();
      expect(controller, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
