import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/exercises/data/exercise_library_repository.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/data/workout_discovery.dart';
import 'package:fitness_command/features/home/data/rotation_repository.dart';
import 'package:fitness_command/features/strength/session_screen.dart';

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

void main() {
  testWidgets(
    'plain cards and fixed informational week switching never affect workout selection',
    (tester) async {
      phone(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workouts = WorkoutRepository(db);
      final variants = await tester.runAsync(
        () => ensureCompactWorkouts(workouts),
      );
      final selected = variants!.last.id;
      await tester.runAsync(
        () => WorkoutDiscoveryRepository(workouts).selectWorkout(selected),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            managementReadyProvider.overrideWith((ref) async {}),
            rotationClockProvider.overrideWithValue(
              () => DateTime(2026, 10, 19),
            ),
          ],
          child: const FitnessCommandApp(),
        ),
      );
      await flush(tester);
      expect(find.text('Current Rotation: Week A'), findsOneWidget);
      final rotationPosition = tester.getTopLeft(
        find.text('Current Rotation: Week A'),
      );
      final navPosition = tester.getTopLeft(find.byType(NavigationBar));
      expect(rotationPosition.dy, lessThan(navPosition.dy));
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Current Rotation: Week A')),
        rotationPosition,
      );
      await tester.tap(find.text('Current Rotation: Week A'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Rotation settings'), findsNothing);
      expect(find.text('Week B (manual)'), findsNothing);
      expect(
        await tester.runAsync(
          () => WorkoutDiscoveryRepository(workouts).selectedWorkout(),
        ),
        selected,
      );
      expect(
        await tester.runAsync(
          () => SessionRepository(db, workouts).unfinished(),
        ),
        isNull,
      );
      for (final name in compactVariantNames) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_off), findsNothing);
      expect(find.text('Current Rotation: Week A'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'circle displays actual reps through zero, reset, reopening and manual editing',
    (tester) async {
      phone(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workouts = WorkoutRepository(db);
      final sessions = SessionRepository(db, workouts);
      final active = await tester.runAsync(() async {
        await workouts.seed();
        final workout = (await workouts.list('workout')).first;
        final entry = (await workouts.list('entry', parentId: workout.id))[2];
        await workouts.edit(entry.id, {...entry.values, 'reps': 3});
        return sessions.start(workout.id);
      });
      Widget app() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: SessionScreen(sessionId: active!.id)),
      );
      await tester.pumpWidget(app());
      await flush(tester);
      final circle = find.byKey(const ValueKey('complete-2-0'));
      await tester.ensureVisible(circle);
      Finder label(String value) =>
          find.descendant(of: circle, matching: find.text(value));
      expect(label('3'), findsOneWidget);
      for (final reps in [3, 2, 1, 0]) {
        await tester.tap(circle);
        await flush(tester);
        expect(label('$reps'), findsOneWidget);
        expect(
          (await tester.runAsync(
            () => sessions.get(active!.id),
          ))!.completedSets,
          1,
        );
      }
      await tester.tap(circle);
      await flush(tester);
      expect(label('3'), findsOneWidget);
      expect(
        (await tester.runAsync(() => sessions.get(active!.id)))!.completedSets,
        0,
      );
      await tester.tap(circle);
      await flush(tester);
      await tester.tap(circle);
      await flush(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await flush(tester);
      await tester.ensureVisible(circle);
      expect(label('2'), findsOneWidget);
      await tester.longPress(circle);
      await flush(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Actual reps'),
        '7',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      expect(label('7'), findsOneWidget);
      await tester.tap(circle);
      await flush(tester);
      expect(label('6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'exercise search and both explicit save scopes preserve independent prescriptions and history',
    (tester) async {
      phone(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workouts = WorkoutRepository(db);
      final sessions = SessionRepository(db, workouts);
      final variants = await tester.runAsync(
        () => ensureCompactWorkouts(workouts),
      );
      final exercise = (await tester.runAsync(
        () => workouts.list('exercise'),
      ))!.firstWhere((e) => e.name.toLowerCase() == 'chest press');
      final library = ExerciseLibraryRepository(workouts);
      final uses = (await tester.runAsync(() => library.usages(exercise.id)))!;
      final snapshot = await tester.runAsync(() async {
        final active = await sessions.start(variants!.first.id);
        await sessions.finish(active.id);
        return jsonEncode((await sessions.get(active.id)).data);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            managementReadyProvider.overrideWith((ref) async {}),
          ],
          child: const FitnessCommandApp(),
        ),
      );
      await flush(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Exercises'),
        ),
      );
      await flush(tester);
      expect(find.text('Programs'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search exercises'),
        'chest press',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('library-exercise-${exercise.id}')));
      await flush(tester);
      await tester.tap(find.text('Edit Exercise'));
      await flush(tester);
      expect(find.text('Edit prescription'), findsNothing);
      await tester.tap(find.byTooltip('Rename exercise'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        uses.first.target['exerciseName'],
      );
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextFormField), 'Discard this');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this'), findsNothing);
      await tester.tap(find.byTooltip('Rename exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Workout press');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Weight / external load'),
        '81',
      );
      await tester.ensureVisible(find.text('Change This Workout Only'));
      await tester.tap(find.text('Change This Workout Only'));
      await flush(tester);
      final after = (await tester.runAsync(() => library.usages(exercise.id)))!;
      for (var i = 0; i < after.length; i++) {
        expect(
          after[i].target['load'],
          uses[i].workout.id == uses.first.workout.id
              ? 81
              : uses[i].target['load'],
        );
        expect(
          after[i].target['exerciseName'],
          uses[i].workout.id == uses.first.workout.id
              ? 'Workout press'
              : uses[i].target['exerciseName'],
        );
        expect(after[i].target['sets'], uses[i].target['sets']);
        expect(after[i].target['reps'], uses[i].target['reps']);
      }
      await tester.ensureVisible(find.text('Edit Exercise'));
      await tester.tap(find.text('Edit Exercise'));
      await flush(tester);
      await tester.tap(find.byTooltip('Rename exercise'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Workout press'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'Shared press');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Weight / external load'),
        '82',
      );
      await tester.ensureVisible(find.text('Change All Workouts'));
      await tester.tap(find.text('Change All Workouts'));
      await flush(tester);
      final all = (await tester.runAsync(() => library.usages(exercise.id)))!;
      for (var i = 0; i < all.length; i++) {
        expect(all[i].target['load'], 82);
        expect(all[i].target['exerciseName'], 'Shared press');
        expect(all[i].target['sets'], uses[i].target['sets']);
        expect(all[i].target['reps'], uses[i].target['reps']);
      }
      expect(find.text('Shared press'), findsWidgets);
      expect(
        jsonEncode((await tester.runAsync(sessions.history))!.single.data),
        snapshot,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
