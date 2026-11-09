import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/session_screen.dart';
import 'package:fitness_command/features/workout/data/personal_workout_seed.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'imported workout supports alternative selection and session target editing',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workouts = WorkoutRepository(db);
      final sessions = SessionRepository(db, workouts);
      final active = await tester.runAsync(() async {
        await seedPersonalWorkouts(workouts);
        return sessions.start((await workouts.list('workout')).first.id);
      });
      Future<void> flush() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(home: SessionScreen(sessionId: active!.id)),
        ),
      );
      await flush();
      await tester.tap(find.text('Warmup').first);
      await flush();
      expect(find.text('Jump rope'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('complete-0-0')));
      await tester.tap(find.byKey(const ValueKey('complete-0-0')));
      await flush();
      await tester.tap(find.byKey(const ValueKey('exercise-details-0')));
      await flush();
      final selector = find.byKey(const ValueKey('alternative-0-0'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option B: Full-body athletic warmup').last);
      await flush();
      expect(find.text('Full-body athletic warmup'), findsWidgets);
      await tester.enterText(find.widgetWithText(TextField, 'Sets'), '2');
      await tester.enterText(
        find.widgetWithText(TextField, 'Target seconds'),
        '45',
      );
      await tester.tap(find.text('Save'));
      await flush();
      final saved = await tester.runAsync(() => sessions.get(active.id));
      expect(saved!.exercises.first['target']['durationSeconds'], 45);
      expect(saved.exercises.first['actualSets'], hasLength(2));
      expect(saved.completedSets, 1); // Recorded Option A survives switching.
      await tester.pumpWidget(const SizedBox());
    },
  );
}
