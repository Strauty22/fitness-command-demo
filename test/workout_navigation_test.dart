import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/session_screen.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late SessionRepository sessions;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    sessions = SessionRepository(db, workouts);
    await ensureCompactWorkouts(workouts);
  });
  tearDown(() => db.close());
  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      managementReadyProvider.overrideWith((ref) async {}),
    ],
    child: const FitnessCommandApp(),
  );
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  testWidgets(
    'six compact choices, fixed tabs, bike access, previews never start sessions',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      for (final name in compactVariantNames) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(ListTile), findsNWidgets(6));
      expect(find.text('Start Workout'), findsNothing);
      expect(find.textContaining('Target:'), findsNothing);
      final position = tester.getTopLeft(find.byType(NavigationBar));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(NavigationBar)), position);
      for (final name in [
        'Exercises',
        'History',
        'Progress',
        'Settings',
        'Home',
      ]) {
        await tester.tap(tab(name));
        await flush(tester);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          [
            'Home',
            'Exercises',
            'History',
            'Progress',
            'Settings',
          ].indexOf(name),
        );
      }
      await tester.tap(find.byTooltip('Bike ride'));
      await flush(tester);
      expect(find.text('Road Cycling'), findsOneWidget);
      await tester.pageBack();
      await flush(tester);
      await tester.tap(find.text('Thursday B'));
      await flush(tester);
      expect(find.text('Workout Preview'), findsOneWidget);
      expect(await tester.runAsync(sessions.unfinished), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      final selected = await tester.runAsync(
        () => WorkoutDiscoveryRepository(workouts).selectedWorkout(),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await flush(tester);
      expect(
        await tester.runAsync(
          () => WorkoutDiscoveryRepository(workouts).selectedWorkout(),
        ),
        selected,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_off), findsNothing);
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(tile.trailing, isNull);
        expect(tile.selected, false);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'phone workflow logs, edits via sheet, finishes and reopens without resume',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      await tester.tap(find.text('Tuesday A'));
      await flush(tester);
      expect(await tester.runAsync(sessions.unfinished), isNull);
      await tester.tap(find.text('Start Workout'));
      await tester.tap(find.text('Start Workout'));
      await flush(tester);
      expect(find.byType(SessionScreen), findsOneWidget);
      expect(find.text('Saved on device'), findsNothing);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Finish workout'), findsNothing);
      expect(find.text('Edit session targets'), findsNothing);
      expect(
        find.byKey(const ValueKey('exercise-details-4')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('complete-1-0')));
      await flush(tester);
      expect((await tester.runAsync(sessions.unfinished))!.completedSets, 1);
      await tester.tap(find.byKey(const ValueKey('exercise-details-1')));
      await flush(tester);
      expect(find.widgetWithText(TextField, 'Sets'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Target reps'),
        '6',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(
        (await tester.runAsync(
          sessions.unfinished,
        ))!.exercises[1]['target']['reps'],
        6,
      );
      await tester.longPress(find.byKey(const ValueKey('complete-1-0')));
      await flush(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Actual reps'),
        '3',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(
        (await tester.runAsync(
          sessions.unfinished,
        ))!.exercises[1]['actualSets'][0]['reps'],
        3,
      );
      await tester.tap(find.text('Warmup'));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('complete-0-0')));
      await flush(tester);
      expect(
        (await tester.runAsync(
          sessions.unfinished,
        ))!.exercises[0]['actualSets'][0]['durationSeconds'],
        300,
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save workout'));
      await flush(tester);
      expect(find.text('Workout complete'), findsOneWidget);
      await tester.tap(find.text('DONE'));
      await flush(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await flush(tester);
      expect(find.text('Resume Workout'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      final history = (await tester.runAsync(sessions.history))!.single;
      expect(history.completedSets, 2);
      await tester.tap(tab('History'));
      await flush(tester);
      await tester.tap(find.text(history.name));
      await flush(tester);
      await tester.longPress(find.byKey(const ValueKey('complete-1-0')));
      await flush(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Actual reps'),
        '4',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(
        (await tester.runAsync(
          () => sessions.get(history.id),
        ))!.exercises[1]['actualSets'][0]['reps'],
        4,
      );
      await tester.pageBack();
      await flush(tester);
      await tester.tap(find.byTooltip('Delete workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await flush(tester);
      expect(await tester.runAsync(sessions.history), hasLength(1));
      await tester.tap(find.byTooltip('Delete workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await flush(tester);
      expect(await tester.runAsync(sessions.history), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'genuine active workout has resume and confirmed discard without duplicates',
    (tester) async {
      final variants = await tester.runAsync(
        () => ensureCompactWorkouts(workouts),
      );
      final active = await tester.runAsync(
        () => sessions.start(variants!.first.id),
      );
      await tester.pumpWidget(app());
      await flush(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Resume Workout'), findsOneWidget);
      await tester.tap(find.text('Resume Workout'));
      await flush(tester);
      expect((await tester.runAsync(sessions.unfinished))!.id, active!.id);
      await tester.tap(find.byTooltip('Workout options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep logging'));
      await flush(tester);
      expect(await tester.runAsync(sessions.unfinished), isNotNull);
      await tester.tap(find.byTooltip('Workout options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel workout'));
      await flush(tester);
      expect(await tester.runAsync(sessions.unfinished), isNull);
      expect(
        (await tester.runAsync(() => sessions.get(active.id)))!.status,
        'cancelled',
      );
      expect(await tester.runAsync(sessions.history), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
