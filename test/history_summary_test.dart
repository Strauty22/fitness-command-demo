import 'dart:convert';
import 'dart:io';
import 'package:fitness_command/app/router.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/app/app.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'package:fitness_command/features/history/history_data.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'fakes/fake_ride_platform.dart';

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pumpAndSettle();
}

Future<int> seed(AppDatabase db) async {
  final workouts = WorkoutRepository(db);
  await workouts.seed();
  var clock = DateTime(2026, 11, 6, 9, 13);
  final sessions = SessionRepository(db, workouts, clock: () => clock);
  final workout = (await workouts.list('workout')).first;
  final entry = (await workouts.list('entry', parentId: workout.id))[2];
  await workouts.edit(entry.id, {...entry.values, 'loadUnit': 'lb'});
  final session = await sessions.start(workout.id);
  await sessions.editSet(session.id, 2, 0, {'reps': 10, 'load': 70});
  await sessions.completeSet(session.id, 2, 0);
  clock = DateTime(2026, 11, 6, 9, 45);
  await sessions.finish(session.id);
  await RideRepository(db).importCapture(
    Ride({
      'id': 'ride',
      'name': 'Morning Bike Loop',
      'status': 'completed',
      'startedAt': DateTime(2026, 11, 7, 9).millisecondsSinceEpoch,
      'endedAt': DateTime(2026, 11, 7, 9, 16, 42).millisecondsSinceEpoch,
      'activeMillis': 1002000,
      'acceptedPoints': 2,
      'distanceMetres': 4264.76,
      'notes': 'A quiet ride through the park.',
    }),
    [],
  );
  return session.id;
}

void main() {
  test(
    'count includes saved sessions once, excludes cancelled/live, responds to deletion and restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('fitness_count');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      final id = await seed(db);
      var container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      expect(await container.read(completedWorkoutCountProvider.future), 2);
      final sessions = SessionRepository(db, WorkoutRepository(db));
      final original = jsonEncode((await sessions.get(id)).data);
      final cancelled = await sessions.start(
        (await WorkoutRepository(db).list('workout')).first.id,
      );
      await sessions.finish(cancelled.id, cancel: true);
      await sessions.start(
        (await WorkoutRepository(db).list('workout')).first.id,
      );
      container.read(sessionRevisionProvider.notifier).refresh();
      expect(await container.read(completedWorkoutCountProvider.future), 2);
      expect(
        (await container.read(combinedHistoryProvider.future)).first.ride!.id,
        'ride',
      );
      await RideRepository(db).deleteHistory('ride');
      container.read(rideRevisionProvider.notifier).refresh();
      expect(await container.read(completedWorkoutCountProvider.future), 1);
      expect(jsonEncode((await sessions.get(id)).data), original);
      container.dispose();
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      expect(await container.read(completedWorkoutCountProvider.future), 1);
      await container.read(sessionRepositoryProvider).deleteHistory(id);
      container.read(sessionRevisionProvider.notifier).refresh();
      expect(await container.read(completedWorkoutCountProvider.future), 0);
      container.dispose();
      await db.close();
    },
  );

  testWidgets(
    'mixed history cards show clean dates and recorded data, open details and confirm deletion',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final platform = FakeRidePlatform();
      addTearDown(db.close);
      addTearDown(platform.stream.close);
      await tester.runAsync(() => seed(db));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            ridePlatformProvider.overrideWithValue(platform),
          ],
          child: const RepaintBoundary(
            key: ValueKey('preview'),
            child: FitnessCommandApp(),
          ),
        ),
      );
      await flush(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await flush(tester);
      expect(find.byType(RideHistoryCard), findsOneWidget);
      expect(find.byType(StrengthHistoryCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(RideHistoryCard)).dy,
        lessThan(tester.getTopLeft(find.byType(StrengthHistoryCard)).dy),
      );
      expect(find.text('Sat, Nov 7, 2026'), findsOneWidget);
      expect(find.text('2.65 mi'), findsOneWidget);
      expect(find.text('16:42'), findsOneWidget);
      expect(find.textContaining('09:45'), findsNothing);
      expect(find.textContaining(' ? '), findsNothing);
      await tester.tap(find.text('Morning Bike Loop'));
      await flush(tester);
      expect(find.text('A quiet ride through the park.'), findsOneWidget);
      await tester.pageBack();
      await flush(tester);
      final card = tester.widget<StrengthHistoryCard>(
        find.byType(StrengthHistoryCard),
      );
      await tester.tap(find.text(card.session.name));
      await flush(tester);
      expect(find.text('Finish'), findsNothing);
      await tester.pageBack();
      await flush(tester);
      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await flush(tester);
      expect(find.byType(RideHistoryCard), findsOneWidget);
      await tester.tap(find.byTooltip('Delete ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await flush(tester);
      expect(find.byType(RideHistoryCard), findsNothing);
      expect(find.byType(StrengthHistoryCard), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'completion reads saved data and combined count; DONE never saves twice',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final platform = FakeRidePlatform();
      addTearDown(platform.stream.close);
      final id = (await tester.runAsync(() => seed(db)))!;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ridePlatformProvider.overrideWithValue(platform),
        ],
      );
      addTearDown(container.dispose);
      container.read(routerProvider).go('/completed/$id');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: ValueKey('preview'),
            child: FitnessCommandApp(),
          ),
        ),
      );
      await flush(tester);
      expect(find.text('Workout 2 done!'), findsOneWidget);
      expect(find.text('Fantastic!'), findsOneWidget);
      expect(find.text('700 lb'), findsOneWidget);
      expect(find.text('32 min'), findsNWidgets(2));
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('DONE'));
      await flush(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        await tester.runAsync(
          () => container.read(completedWorkoutCountProvider.future),
        ),
        2,
      );
      expect(
        await tester.runAsync(
          () => SessionRepository(db, WorkoutRepository(db)).history(),
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
