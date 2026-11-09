import 'dart:convert';
import 'package:test/test.dart';
import 'package:fitness_command/features/strength/data/progression_engine.dart';

void main() {
  final target = <String, dynamic>{
    'type': 'weighted',
    'load': 100,
    'loadUnit': 'lb',
    'sets': 2,
    'reps': 10,
    'progression': 'Progress',
    'increment': 2.5,
    'successCount': 2,
    'failureCount': 2,
    'deloadPercent': 10,
  };
  List<Map<String, dynamic>> sets([int reps = 10]) =>
      List.generate(2, (_) => {'completed': true, 'load': 100, 'reps': reps});
  test('consecutive success, fractional increment and immutable inputs', () {
    final before = jsonEncode([target, sets()]);
    final first = ProgressionEngine.evaluate(target, sets(), {});
    expect(first['load'], 100);
    expect(ProgressionEngine.evaluate(target, sets(), first)['load'], 102.5);
    expect(jsonEncode([target, sets()]), before);
  });
  test('failures reset successes and deload only at configured threshold', () {
    final first = ProgressionEngine.evaluate(target, sets(8), {'wins': 1});
    expect(first['wins'], 0);
    expect(first['load'], 100);
    final second = ProgressionEngine.evaluate(target, sets(8), first);
    expect(second['load'], 90);
    expect(second['losses'], 0);
    expect(
      ProgressionEngine.evaluate(
        {...target, 'failureCount': 0},
        sets(8),
        first,
      )['load'],
      100,
    );
  });
  test(
    'missing, incomplete and lighter sets fail; allowed failures configurable',
    () {
      for (final actual in [
        <Map<String, dynamic>>[],
        [
          {'completed': false},
        ],
        [
          {'completed': true, 'reps': 10, 'load': 99},
        ],
      ]) {
        expect(ProgressionEngine.evaluate(target, actual, {})['losses'], 1);
      }
      expect(
        ProgressionEngine.evaluate(
          {...target, 'allowedFailedSets': 1},
          [sets().first],
          {},
        )['wins'],
        1,
      );
    },
  );
  test(
    'maintain, manual, skipped, unknown loads and bodyweight never auto change',
    () {
      for (final t in [
        {...target, 'progression': 'Maintain'},
        {...target, 'progression': 'Manual'},
        {...target, 'load': null},
        {...target, 'loadUnit': null},
        {...target, 'type': 'bodyweight'},
        {...target, 'reps': null},
      ]) {
        expect(ProgressionEngine.evaluate(t, sets(), {}), isEmpty);
      }
      expect(
        ProgressionEngine.evaluate(target, sets(), {}, skipped: true),
        isEmpty,
      );
    },
  );
  test(
    'timed external load uses duration; actual excess never becomes target',
    () {
      final t = {
        ...target,
        'reps': null,
        'durationSeconds': 30,
        'successCount': 1,
        'type': 'timedHold',
      };
      expect(
        ProgressionEngine.evaluate(t, [
          for (var i = 0; i < 2; i++)
            {'completed': true, 'durationSeconds': 45, 'load': 150},
        ], {})['load'],
        102.5,
      );
    },
  );
  test('invalid rules rejected', () {
    for (final pair in [
      ('successCount', 0),
      ('failureCount', -1),
      ('allowedFailedSets', 0.5),
      ('deloadPercent', 101),
    ]) {
      expect(
        () => ProgressionEngine.evaluate(
          {...target, pair.$1: pair.$2},
          sets(),
          {},
        ),
        throwsArgumentError,
      );
    }
  });
}
