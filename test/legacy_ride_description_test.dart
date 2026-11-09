import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fitness_command/features/history/history_data.dart';
import 'package:fitness_command/features/history/progress_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';

Ride legacyRide(String id, String description, double mph) => Ride({
  'id': id,
  'status': 'completed',
  'name': 'Road Cycling',
  'startedAt': 0,
  'endedAt': 3600000,
  'activeMillis': 3600000,
  'acceptedPoints': 1,
  'distanceMetres': mph * metresPerMile,
  'notes': description,
  'personalBest': false,
});

void main() {
  test(
    'three legacy rides use their saved descriptions for two PB categories',
    () {
      final rides = [
        legacyRide('solo1', 'Standing Bear Solo', 9.5),
        legacyRide('solo2', ' standing bear SOLO ', 10.2),
        legacyRide('wes', 'Standing Bear w Wes', 8.1),
      ];
      final before = rides.map((r) => jsonEncode(r.data)).toList();
      final records = personalBestRides(rides);
      expect(records.map((r) => r.id), ['solo2', 'wes']);
      expect(records.map(savedRideName), [
        'standing bear SOLO',
        'Standing Bear w Wes',
      ]);
      expect(rides.map((r) => jsonEncode(r.data)).toList(), before);
      expect(personalBestRides([rides.first, rides.last]).map((r) => r.id), [
        'solo1',
        'wes',
      ]);
    },
  );

  test(
    'explicit descriptions and meaningful names keep unrelated notes separate',
    () {
      final legacy = legacyRide('legacy', 'Original legacy description', 10);
      expect(
        savedRideName(
          Ride({...legacy.data, 'description': 'Tranquility Solo'}),
        ),
        'Tranquility Solo',
      );
      expect(
        savedRideName(Ride({...legacy.data, 'name': 'My saved name'})),
        'My saved name',
      );
      expect(
        savedRideName(Ride({...legacy.data, 'title': 'Old saved title'})),
        'Old saved title',
      );
      // Clearing an explicitly saved description must not resurrect legacy text.
      expect(
        savedRideName(Ride({...legacy.data, 'description': ''})),
        'Road Cycling',
      );
      expect(
        savedRideName(Ride({...legacy.data, 'notes': ''})),
        'Road Cycling',
      );
    },
  );

  test(
    'repository includes all three legacy captures, supports recategorization and preserves saved data',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RideRepository(db);
      final rides = [
        legacyRide('solo1', 'Standing Bear Solo', 9.5),
        legacyRide('solo2', 'Standing Bear Solo', 10.2),
        legacyRide('wes', 'Standing Bear w Wes', 8.1),
      ];
      final point = RidePoint(
        sequence: 1,
        segment: 0,
        time: DateTime.utc(2026),
        latitude: 41,
        longitude: -96,
        accuracy: 5,
      );
      for (final ride in rides) {
        await repo.importCapture(ride, [point]);
      }
      await repo.annotate('wes', personalBest: false, name: 'Road Cycling');
      final payloads =
          (await db
                  .customSelect('SELECT * FROM ride_sessions ORDER BY id')
                  .get())
              .map((r) => r.data)
              .toList();
      final routes =
          (await db
                  .customSelect('SELECT * FROM ride_points ORDER BY ride_id')
                  .get())
              .map((r) => r.data)
              .toList();
      final history = await repo.history();
      expect(history, hasLength(3));
      expect(personalBestRides(history).map((r) => r.id), ['solo2', 'wes']);
      await repo.saveDescription('solo2', 'Tranquility Solo');
      expect(personalBestRides(await repo.history()).map(savedRideName), [
        'Standing Bear Solo',
        'Standing Bear w Wes',
        'Tranquility Solo',
      ]);
      expect((await repo.get('solo2'))!.notes, 'Standing Bear Solo');
      expect(
        (await db.customSelect('SELECT * FROM ride_sessions ORDER BY id').get())
            .map((r) => r.data)
            .toList(),
        payloads,
      );
      expect(
        (await db
                .customSelect('SELECT * FROM ride_points ORDER BY ride_id')
                .get())
            .map((r) => r.data)
            .toList(),
        routes,
      );
      await repo.deleteHistory('solo2');
      expect(personalBestRides(await repo.history()).map((r) => r.id), [
        'solo1',
        'wes',
      ]);
    },
  );

  testWidgets(
    'legacy description appears once in the title with original metric/date formatting',
    (tester) async {
      final ride = legacyRide('wes', 'Standing Bear w Wes', 11);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RideHistoryCard(ride: ride)),
        ),
      );
      expect(find.text('Standing Bear w Wes'), findsOneWidget);
      expect(find.text('Road Cycling'), findsNothing);
      expect(find.text('11.00 mi'), findsOneWidget);
      expect(find.text('11.0 mph'), findsOneWidget);
      expect(find.text('1:00:00'), findsOneWidget);
      final card = tester.widget<WorkoutHistoryCard>(
        find.byType(WorkoutHistoryCard),
      );
      expect(card.name, 'Standing Bear w Wes');
      expect(card.date, ride.ended);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideHistoryCard(
              ride: Ride({...ride.data, 'description': 'Tranquility Solo'}),
            ),
          ),
        ),
      );
      expect(find.text('Tranquility Solo'), findsOneWidget);
      expect(find.text('Standing Bear w Wes'), findsOneWidget);
    },
  );
  testWidgets(
    'Progress includes three saved legacy rides in two description-based PB cards',
    (tester) async {
      final rides = [
        legacyRide('solo1', 'Standing Bear Solo', 9.5),
        legacyRide('solo2', 'Standing Bear Solo', 10.2),
        legacyRide('wes', 'Standing Bear w Wes', 8.1),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            combinedHistoryProvider.overrideWith(
              (ref) async => rides.map(HistoryEntry.cycling).toList(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ProgressRecords()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(RideHistoryCard), findsNWidgets(2));
      expect(find.text('Standing Bear Solo'), findsOneWidget);
      expect(find.text('Standing Bear w Wes'), findsOneWidget);
      expect(find.text('Road Cycling'), findsNothing);
      expect(find.text('10.2 mph'), findsOneWidget);
      expect(find.text('8.1 mph'), findsOneWidget);
      expect(find.text('9.5 mph'), findsNothing);
    },
  );
}
