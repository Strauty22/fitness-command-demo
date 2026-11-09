import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/custom_workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/home/data/rotation_repository.dart';
import 'package:fitness_command/features/strength/session_screen.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    await ensureCompactWorkouts(workouts);
  });
  tearDown(() => db.close());
  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      managementReadyProvider.overrideWith((ref) async {}),
      rotationClockProvider.overrideWithValue(() => DateTime(2026, 10, 19)),
    ],
    child: const FitnessCommandApp(),
  );
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await flush(tester);
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('rotation refreshes on resume and reopening Home', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 24, 23, 59);
    Widget timedApp() => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        managementReadyProvider.overrideWith((ref) async {}),
        rotationClockProvider.overrideWithValue(() => now),
      ],
      child: const FitnessCommandApp(),
    );
    await tester.pumpWidget(timedApp());
    await flush(tester);
    expect(find.text('Current Rotation: Week A'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 25);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(find.text('Current Rotation: Week B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    now = DateTime(2026, 11, 1);
    await tester.pumpWidget(timedApp());
    await flush(tester);
    expect(find.text('Current Rotation: Week A'), findsOneWidget);
    expect(
      (await tester.runAsync(
        () => RotationRepository(workouts).load(),
      ))!.anchor,
      DateTime(2026, 10, 19),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'rotation is informational, persisted week displays and plus opens builder',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      final label = find.text('Current Rotation: Week A');
      final plus = find.byTooltip('Create Workout');
      expect(find.byIcon(Icons.swap_vert), findsNothing);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byTooltip('Change rotation'), findsNothing);
      expect(tester.getRect(plus).right, greaterThan(380));
      final rowPosition = tester.getTopLeft(label);
      final navigation = tester.getTopLeft(find.byType(NavigationBar));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label), rowPosition);
      expect(tester.getTopLeft(find.byType(NavigationBar)), navigation);
      expect(find.byTooltip('Rotation settings'), findsNothing);
      await tap(tester, label);
      expect(find.text('Week B (manual)'), findsNothing);
      await tester.runAsync(
        () => RotationRepository(workouts).save(override: 1),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await flush(tester);
      expect(find.text('Current Rotation: Week A'), findsOneWidget);
      await tap(tester, find.byTooltip('Create Workout'));
      expect(find.text('Create Workout'), findsOneWidget);
      await tap(tester, find.text('Save Workout'));
      expect(find.textContaining('Workout name is required'), findsOneWidget);
      await tester.pageBack();
      await flush(tester);
      expect(
        (await tester.runAsync(
          () => CustomWorkoutRepository(workouts).list(),
        ))!,
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => SessionRepository(db, workouts).unfinished(),
        ),
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new bodyweight exercise validates its name and can be reused from the library',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(app());
      await flush(tester);
      await tap(tester, find.byTooltip('Create Workout'));
      await enter(tester, 'Workout Name (required)', 'Bodyweight travel');
      await tap(tester, find.text('Add Exercise'));
      expect(find.text('Add Exercise'), findsOneWidget);
      expect(find.text('Choose Existing Exercise'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Search exercises'),
        findsOneWidget,
      );
      final create = find.widgetWithText(ListTile, 'Create New Exercise');
      expect(create, findsOneWidget);
      expect(
        tester.getRect(create).top,
        greaterThanOrEqualTo(
          tester
              .getRect(find.widgetWithText(TextField, 'Search exercises'))
              .bottom,
        ),
      );
      await enter(tester, 'Search exercises', 'no matching exercise 12345');
      expect(find.text('No matching exercises.'), findsOneWidget);
      expect(create, findsOneWidget);
      await tap(tester, find.text('Create New Exercise'));
      await tap(tester, find.text('Cancel'));
      expect(
        find.widgetWithText(TextField, 'Search exercises'),
        findsOneWidget,
      );
      expect(find.text('No matching exercises.'), findsOneWidget);
      await tap(tester, find.text('Create New Exercise'));
      await tap(tester, find.text('Save Exercise'));
      expect(find.textContaining('Name is required'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Travel pushup');
      await tap(tester, find.text('Weight and reps'));
      await tap(tester, find.text('Bodyweight').last);
      await enter(tester, 'Sets', '3');
      await enter(tester, 'Reps', '12');
      await tap(tester, find.text('Save Exercise'));
      await tap(tester, find.text('Save Workout'));
      final created = (await tester.runAsync(
        () => workouts.list('exercise'),
      ))!.singleWhere((e) => e.name == 'Travel pushup');
      expect(created.values['type'], 'bodyweight');
      expect(created.values['sets'], 3);
      expect(created.values['reps'], 12);
      await tap(tester, find.byTooltip('Create Workout'));
      await enter(tester, 'Workout Name (required)', 'Reuse bodyweight');
      await tap(tester, find.text('Add Exercise'));
      await enter(tester, 'Search exercises', 'Travel pushup');
      await tap(tester, find.byKey(ValueKey('choose-exercise-${created.id}')));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Reps'))
            .controller!
            .text,
        '12',
      );
      await tap(tester, find.text('Save Exercise'));
      await tap(tester, find.text('Save Workout'));
      final custom = (await tester.runAsync(
        () => CustomWorkoutRepository(workouts).list(),
      ))!;
      expect(custom, hasLength(2));
      final entries = (await tester.runAsync(
        () => CustomWorkoutRepository(workouts).entries(custom.last.id),
      ))!;
      expect(entries.single.exerciseId, created.id);
      expect(
        (await tester.runAsync(
          () => workouts.list('exercise'),
        ))!.where((e) => e.name == 'Travel pushup'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'build existing and new exercises, prevent duplicates, reorder, execute, edit and confirm deletion',
    (tester) async {
      phone(tester);
      final sessions = SessionRepository(db, workouts);
      final originalEntries = await workouts.list('entry');
      final originals = {
        for (final e in originalEntries) e.id: jsonEncode(e.values),
      };
      final libraryBefore = await workouts.list('exercise');
      await tester.pumpWidget(app());
      await flush(tester);
      await tap(tester, find.byTooltip('Create Workout'));
      await enter(tester, 'Workout Name (required)', 'Travel');
      await enter(tester, 'Workout notes (optional)', 'Hotel gym');
      await tap(tester, find.text('Add Exercise'));
      await enter(tester, 'Search exercises', 'chest press');
      await tap(
        tester,
        find.byKey(
          ValueKey(
            'choose-exercise-${libraryBefore.firstWhere((e) => e.name.toLowerCase() == 'chest press').id}',
          ),
        ),
      );
      expect(find.text('Change All Workouts'), findsNothing);
      expect(find.text('Change This Workout Only'), findsNothing);
      await enter(tester, 'Weight / external load', '19');
      await enter(tester, 'Sets', '2');
      await enter(tester, 'Reps', '6');
      await tap(tester, find.text('Save Exercise'));
      await tap(tester, find.text('Add Exercise'));
      await tap(tester, find.text('Create New Exercise'));
      await tester.enterText(
        find.byType(TextFormField).first,
        'Travel balance',
      );
      await tap(tester, find.text('Weight and reps'));
      await tap(tester, find.text('Timed hold').last);
      await enter(tester, 'Sets', '1');
      await enter(tester, 'Duration (seconds)', '45');
      await enter(tester, 'Rest duration (seconds, optional)', '0');
      await tap(tester, find.text('Save Exercise'));
      // New identities are not written until the complete workout is saved.
      expect(
        (await tester.runAsync(() => workouts.list('exercise')))!.length,
        libraryBefore.length,
      );
      await tap(tester, find.text('Add Exercise'));
      await tap(tester, find.text('Create New Exercise'));
      await tester.enterText(
        find.byType(TextFormField).first,
        '  CHEST   PRESS  ',
      );
      await tap(tester, find.text('Save Exercise'));
      expect(find.text('Exercise already exists'), findsOneWidget);
      await tap(tester, find.text('Use Existing Exercise'));
      final duplicateCard = find.byKey(const ValueKey('draft-exercise-2'));
      await tap(
        tester,
        find.descendant(
          of: duplicateCard,
          matching: find.byTooltip('Remove exercise'),
        ),
      );
      final timedCard = find.byKey(const ValueKey('draft-exercise-1'));
      await tap(
        tester,
        find.descendant(of: timedCard, matching: find.byTooltip('Move up')),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('draft-exercise-0')),
          matching: find.text('Travel balance'),
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Save Workout'));
      expect(find.text('Fitness Command'), findsOneWidget);
      expect(await tester.runAsync(sessions.unfinished), isNull);
      final custom = (await tester.runAsync(
        () => CustomWorkoutRepository(workouts).list(),
      ))!.single;
      final entries = (await tester.runAsync(
        () => CustomWorkoutRepository(workouts).entries(custom.id),
      ))!;
      expect(entries.first.values['durationSeconds'], 45);
      expect(entries.last.values['reps'], 6);
      expect(entries.last.values['load'], 19);
      expect(
        (await tester.runAsync(() => workouts.list('exercise')))!.length,
        libraryBefore.length + 1,
      );
      for (final e in originals.entries) {
        expect(
          jsonEncode(
            (await tester.runAsync(() => workouts.get(e.key)))!.values,
          ),
          e.value,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await flush(tester);
      await tap(tester, find.byKey(ValueKey('workout-preview-${custom.id}')));
      expect(find.text('Hotel gym'), findsOneWidget);
      await tap(tester, find.text('Start Workout'));
      expect(find.byType(SessionScreen), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('complete-0-0')));
      await tap(tester, find.byKey(const ValueKey('complete-1-0')));
      await tap(tester, find.byKey(const ValueKey('complete-1-0')));
      final active = (await tester.runAsync(sessions.unfinished))!;
      expect(active.exercises[1]['actualSets'][0]['reps'], 5);
      expect(active.exercises[0]['actualSets'][0]['durationSeconds'], 45);
      expect(active.data['notes'], 'Hotel gym');
      await tap(tester, find.text('Finish'));
      await tap(tester, find.text('Save workout'));
      await tap(tester, find.text('DONE'));
      final history = (await tester.runAsync(sessions.history))!.single;
      expect(history.status, 'completed');
      expect(history.name, 'Travel');
      final historyData = jsonEncode(history.data);
      await tap(tester, find.byKey(ValueKey('workout-preview-${custom.id}')));
      await tap(tester, find.byTooltip('Manage workout'));
      await tap(tester, find.text('Edit Workout'));
      await enter(tester, 'Workout Name (required)', 'Travel updated');
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('draft-exercise-0')),
          matching: find.text('Edit Exercise'),
        ),
      );
      await enter(tester, 'Duration (seconds)', '50');
      await tap(tester, find.text('Save Exercise'));
      await tap(tester, find.text('Save Workout'));
      expect(find.text('Travel updated'), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => CustomWorkoutRepository(workouts).entries(custom.id),
        ))!.first.values['durationSeconds'],
        50,
      );
      await tap(tester, find.byTooltip('Manage workout'));
      await tap(tester, find.text('Delete Workout'));
      await tap(tester, find.text('Cancel'));
      expect(
        (await tester.runAsync(
          () => CustomWorkoutRepository(workouts).list(),
        ))!,
        hasLength(1),
      );
      await tap(tester, find.byTooltip('Manage workout'));
      await tap(tester, find.text('Delete Workout'));
      await tap(tester, find.widgetWithText(FilledButton, 'Delete Workout'));
      expect(
        (await tester.runAsync(
          () => CustomWorkoutRepository(workouts).list(),
        ))!,
        isEmpty,
      );
      expect(
        jsonEncode((await tester.runAsync(sessions.history))!.single.data),
        historyData,
      );
      for (final name in compactVariantNames) {
        expect(find.text(name), findsOneWidget);
      }
      final created = (await tester.runAsync(
        () => workouts.list('exercise'),
      ))!.where((e) => e.name == 'Travel balance');
      expect(created, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
