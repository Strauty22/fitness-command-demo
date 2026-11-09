import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/history/workout_history_card.dart';
import 'package:fitness_command/features/strength/data/strength_session.dart';
import 'package:fitness_command/features/cycling/data/ride.dart';

Map<String, dynamic> exercise(
  int id,
  String name,
  List<Map<String, dynamic>> sets, {
  String unit = 'lb',
  num prescription = 999,
}) => {
  'exerciseId': id,
  'name': name,
  'target': {'type': 'weighted', 'load': prescription, 'loadUnit': unit},
  'actualSets': sets,
};
Map<String, dynamic> actual(
  num? load, {
  num reps = 1,
  bool completed = true,
  String? time,
}) => {'load': load, 'reps': reps, 'completed': completed, 'completedAt': time};
StrengthSession session(
  int id,
  List<Map<String, dynamic>> exercises, {
  String status = 'completed',
}) => StrengthSession(
  id,
  status,
  DateTime.utc(2026, 11, id, 9),
  DateTime.utc(2026, 11, id, 10),
  {'workoutName': 'Workout', 'exercises': exercises},
);
Ride ride(
  String id,
  String name,
  double speed, {
  bool marked = true,
  String status = 'completed',
}) => Ride({
  'id': id,
  'name': name,
  'status': status,
  'personalBest': marked,
  'startedAt': 0,
  'endedAt': 1000000,
  'activeMillis': 1000000,
  'acceptedPoints': 2,
  'distanceMetres': speed * 1000,
});

void main() {
  test(
    'strength PB uses actual positive-rep completed sets, stable IDs and earliest tie',
    () {
      final first = session(1, [
        exercise(1, 'Chest Press', [
          actual(100),
          actual(200, reps: 0),
          actual(300, completed: false),
          actual(null),
        ]),
      ]);
      final tie = session(2, [
        exercise(1, 'Renamed press', [actual(100)]),
      ]);
      final cancelled = session(3, [
        exercise(1, 'Press', [actual(500)]),
      ], status: 'cancelled');
      final active = session(4, [
        exercise(1, 'Press', [actual(600)]),
      ], status: 'active');
      final other = session(5, [
        exercise(2, 'Arm curl', [actual(65)]),
        exercise(3, 'Unperformed', [actual(null)]),
        exercise(4, 'Unknown units', [actual(900)], unit: ''),
      ]);
      final bests = exerciseBests([tie, other, cancelled, active, first]);
      expect(bests.map((b) => b.name), ['Arm curl', 'Chest Press']);
      expect(bests.last.pounds, 100);
      expect(bests.last.sessionId, 1);
      final higher = session(6, [
        exercise(1, 'Renamed press', [actual(110)]),
      ]);
      expect(exerciseBests([first, tie, higher]).single.pounds, 110);
      expect(exerciseBests([first, tie]).single.sessionId, 1);
      expect(exerciseBests([tie]).single.sessionId, 2);
    },
  );

  test(
    'records count distinct exercises and in-workout indicators ignore incomplete and tied loads',
    () {
      final prior = session(1, [
        exercise(1, 'Press', [actual(100)]),
      ]);
      final current = session(2, [
        exercise(1, 'Press', [actual(105), actual(110)]),
        exercise(2, 'Curl', [actual(65)]),
        exercise(3, 'Squat', [actual(150, reps: 0)]),
      ]);
      expect(newExerciseRecords(current, [prior, current]), {'id:1', 'id:2'});
      final live = session(3, [
        exercise(1, 'Press', [actual(110), actual(120, completed: false)]),
      ], status: 'active');
      expect(newExerciseRecords(live, [prior, current]), isEmpty);
      (live.exercises.single['actualSets'] as List).add(actual(120));
      expect(newExerciseRecords(live, [prior, current]), {'id:1'});
      expect(
        exerciseBests([
          prior,
          current,
          live,
        ]).firstWhere((b) => b.key == 'id:1').pounds,
        110,
      );
      expect(
        newExerciseRecords(session(4, live.exercises, status: 'cancelled'), [
          prior,
        ]),
        isEmpty,
      );
    },
  );

  test('units and completion timestamps are read from actuals', () {
    final e = exercise(1, 'Press', [
      {...actual(50), 'loadUnit': 'lb', 'completedAt': '2026-11-01T09:15:00Z'},
    ], unit: 'kg');
    final best = exerciseBests([
      session(1, [e]),
    ]).single;
    expect(best.pounds, 50);
    expect(best.date, DateTime.utc(2026, 11, 1, 9, 15));
    expect(
      completedPounds(e, {...actual(10), 'loadUnit': 'kg'}),
      closeTo(22.046226218, 0.0001),
    );
  });

  test(
    'ride records group only normalized names and select fastest completed ride regardless of legacy flag',
    () {
      final slow = ride('slow', 'Standing Bear Solo', 10.2);
      final fastest = ride('fast', ' standing bear SOLO ', 11.4);
      final unmarked = ride(
        'unmarked',
        'Standing Bear Solo',
        12.1,
        marked: false,
      );
      final wesley = ride('wesley', 'Standing Bear w Wesley', 7.4);
      final tranquility = ride('tranquility', 'Tranquility Solo', 10.1);
      final discarded = ride(
        'discarded',
        'Standing Bear Solo',
        50,
        status: 'discarded',
      );
      final bests = personalBestRides([
        slow,
        fastest,
        unmarked,
        wesley,
        tranquility,
        discarded,
      ]);
      expect(bests.map((r) => r.id), ['unmarked', 'wesley', 'tranquility']);
      expect(bests.first.data['name'], 'Standing Bear Solo');
      expect(personalBestRides([slow, unmarked]).single.id, 'unmarked');
      expect(personalBestRides([unmarked]).single.id, 'unmarked');
      expect(
        personalBestRides([
          Ride({...fastest.data, 'personalBest': false}),
          slow,
        ]).single.id,
        'fast',
      );
    },
  );
  test(
    'ride ties retain earliest completion and descriptions take precedence over generic names',
    () {
      final later = Ride({
        ...ride('later', 'Road Cycling', 10, marked: false).data,
        'description': ' Standing Bear Solo ',
      });
      final earlier = Ride({
        ...later.data,
        'id': 'earlier',
        'description': 'standing bear SOLO',
        'startedAt': -1000000,
        'endedAt': 0,
      });
      final other = Ride({
        ...later.data,
        'id': 'other',
        'description': 'Standing Bear w Wes',
      });
      expect(personalBestRides([later, earlier, other]).map((r) => r.id), [
        'earlier',
        'other',
      ]);
      expect(personalBestRides([earlier, later]).single.id, 'earlier');
      expect(savedRideName(later), 'Standing Bear Solo');
      expect(
        savedRideName(
          Ride({...later.data, 'description': ' ', 'name': 'Legacy loop'}),
        ),
        'Legacy loop',
      );
      expect(
        savedRideName(
          Ride({...later.data, 'description': '', 'name': '', 'title': ' '}),
        ),
        'Road Cycling',
      );
      expect(
        personalBestRides([
          Ride({...later.data, 'status': 'review'}),
        ]),
        isEmpty,
      );
      expect(
        personalBestRides([
          Ride({...later.data, 'status': 'cancelled'}),
        ]),
        isEmpty,
      );
    },
  );
}
