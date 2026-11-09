import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/app/router.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/ride_description_editor.dart';
import 'package:fitness_command/features/cycling/data/map_tile_repository.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'fakes/fake_ride_platform.dart';
import 'cycling_screen_test.dart' show OfflineTestTiles;
import 'ride_description_test.dart' show capture;
import 'ride_notes_screen_test.dart' show flush;

void main() {
  testWidgets(
    'description titles History/details/Progress and editing refreshes the category',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final platform = FakeRidePlatform();
      final tiles = OfflineTestTiles(db);
      addTearDown(db.close);
      addTearDown(platform.stream.close);
      addTearDown(tiles.close);
      final repo = RideRepository(db);
      await tester.runAsync(
        () => repo.importCapture(capture('ride', 1000000), []),
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ridePlatformProvider.overrideWithValue(platform),
          mapTileRepositoryProvider.overrideWithValue(tiles),
        ],
      );
      addTearDown(container.dispose);
      container.read(routerProvider).go('/history');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FitnessCommandApp(),
        ),
      );
      await flush(tester);
      expect(find.text('Standing Bear Solo'), findsOneWidget);
      expect(find.text('Road Cycling'), findsNothing);
      await tester.tap(find.text('Standing Bear Solo'));
      await flush(tester);
      expect(find.text('Standing Bear Solo'), findsWidgets);
      expect(find.text('Personal Best'), findsNothing);
      Future<void> edit() async {
        final button = find.byTooltip('Edit description');
        await Scrollable.ensureVisible(tester.element(button), alignment: 0.4);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await edit();
      final field = find.widgetWithText(TextField, 'Description');
      expect(
        tester.widget<TextField>(field).textCapitalization,
        TextCapitalization.sentences,
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Standing Bear Solo',
      );
      await tester.enterText(field, 'Discard this change');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => repo.get('ride')))!.data['description'],
        'Standing Bear Solo',
      );
      await edit();
      await tester.enterText(field, 'tranquility Solo');
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(find.text('Tranquility Solo'), findsWidgets);
      expect(
        (await tester.runAsync(() => repo.get('ride')))!.notes,
        'Original notes',
      );
      await tester.pageBack();
      await flush(tester);
      expect(find.text('Tranquility Solo'), findsOneWidget);
      container.read(routerProvider).go('/progress');
      await flush(tester);
      expect(find.text('Tranquility Solo'), findsOneWidget);
      expect(find.text('Standing Bear Solo'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'opening and saving an existing description without typing preserves exact saved text',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RideRepository(db);
      final ride = Ride({
        ...capture('saved', 1000000).data,
        'description': ' standing Bear w Wes ',
      });
      await tester.runAsync(() => repo.importCapture(ride, []));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(body: SavedRideDescription(ride: ride)),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Edit description'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Description');
      expect(
        tester.widget<TextField>(field).controller!.text,
        ' standing Bear w Wes ',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(
        (await tester.runAsync(() => repo.get('saved')))!.data['description'],
        ' standing Bear w Wes ',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
