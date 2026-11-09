import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/app/router.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/cycling/data/map_tile_repository.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'fakes/fake_ride_platform.dart';
import 'cycling_screen_test.dart' show OfflineTestTiles;
import 'ride_notes_repository_test.dart' show capture;

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final initial in ['', 'Saved notes', 'saved notes']) {
    testWidgets(
      'History ride notes add/edit/cancel/clear (initial: "$initial")',
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
          () => repo.importCapture(capture('ride', notes: initial), []),
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
        await tester.tap(find.text('Original ride'));
        await flush(tester);
        Future<void> edit() async {
          final button = find.byTooltip('Edit notes');
          await Scrollable.ensureVisible(
            tester.element(button),
            alignment: 0.4,
          );
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await edit();
        final field = find.widgetWithText(TextField, 'Ride notes');
        expect(tester.widget<TextField>(field).controller!.text, initial);
        expect(
          tester.widget<TextField>(field).textCapitalization,
          TextCapitalization.sentences,
        );
        await tester.enterText(field, 'Unsaved draft');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((await tester.runAsync(() => repo.get('ride')))!.notes, initial);
        await edit();
        expect(tester.widget<TextField>(field).controller!.text, initial);
        await tester.enterText(field, 'updated ride notes\nSecond line');
        await tester.tap(find.text('Save'));
        await flush(tester);
        expect(find.text('Updated ride notes\nSecond line'), findsOneWidget);
        expect(
          (await tester.runAsync(() => repo.get('ride')))!.notes,
          'Updated ride notes\nSecond line',
        );
        await tester.pageBack();
        await flush(tester);
        expect(find.text('Updated ride notes\nSecond line'), findsOneWidget);
        await tester.tap(find.text('Original ride'));
        await flush(tester);
        await edit();
        expect(
          tester.widget<TextField>(field).controller!.text,
          'Updated ride notes\nSecond line',
        );
        await tester.enterText(field, '');
        await tester.tap(find.text('Save'));
        await flush(tester);
        expect(find.text('No notes'), findsOneWidget);
        expect((await tester.runAsync(() => repo.get('ride')))!.notes, '');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
