import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/strength/session_screen.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SessionRepository repo;
  late int sessionId;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final workouts = WorkoutRepository(db);
    repo = SessionRepository(db, workouts);
    final program = await workouts.create('program', {
      'name': 'Test program',
      'sets': 2,
      'reps': 10,
      'cycle': ['A'],
      'anchor': '2026-10-19',
    });
    final workout = await workouts.create('workout', {
      'name': 'Gym test',
    }, parentId: program);
    final exercise = await workouts.create('exercise', {
      'name': 'Squat',
      'type': 'weighted',
      'load': 20,
      'loadUnit': 'kg',
      'restSeconds': 30,
    });
    await workouts.create('entry', {
      'name': 'Squat',
      'exerciseId': exercise,
    }, parentId: workout);
    sessionId = (await repo.start(workout)).id;
  });
  tearDown(() => db.close());
  Future<void> settleStorage(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Widget screen() => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: SessionScreen(sessionId: sessionId)),
  );

  testWidgets('one-tap completion persists and opens a running rest timer', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await settleStorage(tester);
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('2\u00d710  20 kg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('complete-0-0')));
    await settleStorage(tester);
    final saved = await tester.runAsync(() => repo.get(sessionId));
    expect(saved!.completedSets, 1);
    expect(find.textContaining('Rest 00:'), findsOneWidget);
    expect(find.byKey(const ValueKey('complete-0-0')), findsOneWidget);
    // Disposing the screen cannot discard the committed set.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await settleStorage(tester);
    expect(find.byKey(const ValueKey('complete-0-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'actual changes save before dialog dismissal and leave targets intact',
    (tester) async {
      await tester.pumpWidget(screen());
      await settleStorage(tester);
      await tester.longPress(find.byKey(const ValueKey('complete-0-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Actual reps'),
        '7',
      );
      await tester.tap(find.text('Save'));
      await settleStorage(tester);
      final saved = await tester.runAsync(() => repo.get(sessionId));
      expect(saved!.exercises[0]['actualSets'][0]['reps'], 7);
      expect(saved.exercises[0]['target']['reps'], 10);
      expect(saved.completedSets, 0);
      expect(find.text('10'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
