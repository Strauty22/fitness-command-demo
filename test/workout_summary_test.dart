import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/features/history/workout_summary.dart';
import 'package:fitness_command/features/strength/data/strength_session.dart';

Map<String, dynamic> exercise(
  String name,
  List<Map<String, dynamic>> sets, {
  String type = 'weighted',
  String? unit = 'lb',
}) => {
  'name': name,
  'target': {'type': type, 'loadUnit': unit, 'reps': 99, 'load': 999},
  'actualSets': sets,
};
StrengthSession session(List<Map<String, dynamic>> exercises) =>
    StrengthSession(
      1,
      'completed',
      DateTime(2026, 11, 6, 9),
      DateTime(2026, 11, 6, 9, 32),
      {'workoutName': 'Tuesday A', 'exercises': exercises},
    );
void main() {
  test('dates have no clock; durations and numbers remain readable', () {
    expect(historyDate(DateTime(2026, 11, 6, 9, 45)), 'Fri, Nov 6, 2026');
    expect(summaryDuration(const Duration(minutes: 32)), '32 min');
    expect(summaryDuration(const Duration(minutes: 16, seconds: 42)), '16:42');
    expect(groupedNumber(2100), '2,100');
    expect(summaryNumber(2.25), '2.25');
  });
  test(
    'top three performed exercises preserve order and omit unfinished sets',
    () {
      final saved = session([
        exercise('Not performed', [
          {'completed': false, 'reps': 10},
        ]),
        for (final name in ['First', 'Second', 'Third', 'Fourth'])
          exercise(name, [
            {'completed': true, 'reps': 10, 'load': 70},
            {'completed': false},
          ]),
      ]);
      expect(summaryExercises(saved).map((e) => e['name']), [
        'First',
        'Second',
        'Third',
      ]);
      expect(exerciseSummary(saved.exercises[1]), '1\u00d710 reps / 70 lb');
      expect(strengthDuration(saved), const Duration(minutes: 32));
    },
  );
  test(
    'varying actuals are explicit; identical actuals group; no prescription fallback',
    () {
      final saved = exercise('Press', [
        {'completed': true, 'reps': 10, 'load': 70},
        {'completed': true, 'reps': 8, 'load': 65},
        {'completed': false, 'reps': 10, 'load': 999},
      ]);
      expect(exerciseSummary(saved), '10 reps / 70 lb; 8 reps / 65 lb');
      expect(
        exerciseSummary(
          exercise('Unknown', [
            {'completed': true},
          ]),
        ),
        '1\u00d7reps unrecorded / load unrecorded',
      );
      expect(
        exerciseSummary(
          exercise('Hold', [
            {'completed': true, 'durationSeconds': 45},
            {'completed': true, 'durationSeconds': 45},
          ], type: 'timed'),
        ),
        '2\u00d70:45',
      );
    },
  );
  test(
    'volume uses actual completed lifting sets and converts kg; skips unknown units',
    () {
      final saved = session([
        exercise('Press', [
          {'completed': true, 'reps': 10, 'load': 70},
          {'completed': true, 'reps': 8, 'load': 65},
          {'completed': false, 'reps': 100, 'load': 999},
        ]),
        exercise('Kg', [
          {'completed': true, 'reps': 2, 'load': 10},
        ], unit: 'kg'),
        exercise('Unknown', [
          {'completed': true, 'reps': 10, 'load': 90},
        ], unit: null),
        exercise('Hold', [
          {'completed': true, 'reps': 10, 'load': 900, 'durationSeconds': 30},
        ], type: 'timed'),
      ]);
      expect(
        liftingVolumePounds(saved),
        closeTo(1220 + 20 * 2.2046226218, .0001),
      );
    },
  );
  test(
    'completed alternatives are retained and unperformed alternatives are omitted',
    () {
      final saved = session([
        {
          ...exercise('Current', [
            {'completed': false},
          ]),
          'selectedAlternative': 1,
          'alternativeStates': {
            '0': exercise('Earlier', [
              {'completed': true, 'reps': 5, 'load': 20},
            ]),
          },
        },
      ]);
      expect(summaryExercises(saved).single['name'], 'Earlier');
      expect(liftingVolumePounds(saved), 100);
    },
  );
}
