import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/features/history/history_data.dart';
import 'package:fitness_command/features/history/progress_screen.dart';
import 'package:fitness_command/features/history/progress_records.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/session_exercise_card.dart';
import 'package:fitness_command/features/cycling/data/ride_controller.dart';
import 'personal_bests_test.dart' as fixtures;

class NoSyncRideController extends RideController {
  @override
  Future<void> sync() async {}
}

void main() {
  testWidgets(
    'completed actual sets show a subtle PB without changing set controls',
    (tester) async {
      final exercise = fixtures.exercise(1, 'Press', [
        fixtures.actual(100),
        fixtures.actual(120, completed: false),
      ]);
      final active = fixtures.session(2, [exercise], status: 'active');
      final prior = fixtures.session(1, [
        fixtures.exercise(1, 'Press', [fixtures.actual(90)]),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionHistoryProvider.overrideWith((ref) async => [prior]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SessionExerciseCard(
                session: active,
                index: 0,
                saving: false,
                operate: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PB'), findsOneWidget);
      expect(find.byKey(const ValueKey('complete-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('complete-0-1')), findsOneWidget);
      (exercise['actualSets'] as List).first['reps'] = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionHistoryProvider.overrideWith((ref) async => [prior]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SessionExerciseCard(
                session: active,
                index: 0,
                saving: false,
                operate: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PB'), findsNothing);
    },
  );

  testWidgets(
    'Progress shows separate totals, ride PB cards, exercise PB and existing performance',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = fixtures.session(1, [
        fixtures.exercise(1, 'Press', [fixtures.actual(100)]),
      ]);
      final ride = fixtures.ride('ride', 'Standing Bear Solo', 5);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            combinedHistoryProvider.overrideWith(
              (ref) async => [
                HistoryEntry.strength(saved),
                HistoryEntry.cycling(ride),
              ],
            ),
            sessionHistoryProvider.overrideWith((ref) async => [saved]),
            rideControllerProvider.overrideWith(NoSyncRideController.new),
            rideHistoryProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: ProgressScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total Rides'), findsOneWidget);
      expect(find.text('Total Strength Workouts'), findsOneWidget);
      expect(find.byType(RideHistoryCard), findsOneWidget);
      expect(find.text('Standing Bear Solo'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Personal Best Exercises'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('100 lb'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Exercise Performance'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(ExpansionTile), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 393.0, 600.0]) {
    testWidgets('totals have equal dimensions at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [combinedHistoryProvider.overrideWith((ref) async => [])],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ProgressRecords(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rides = find.ancestor(
        of: find.text('Total Rides'),
        matching: find.byType(Card),
      );
      final strength = find.ancestor(
        of: find.text('Total Strength Workouts'),
        matching: find.byType(Card),
      );
      expect(tester.getSize(rides), tester.getSize(strength));
      expect(tester.getTopLeft(rides).dy, tester.getTopLeft(strength).dy);
      expect(tester.takeException(), isNull);
    });
  }
}
