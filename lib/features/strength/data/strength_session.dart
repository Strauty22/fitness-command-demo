import 'dart:convert';
import 'package:drift/drift.dart';

Map<String, dynamic> copyJson(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class StrengthSession {
  final int id;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Map<String, dynamic> data;
  StrengthSession(
    this.id,
    this.status,
    this.startedAt,
    this.endedAt,
    this.data,
  );
  factory StrengthSession.fromRow(QueryRow row) => StrengthSession(
    row.read<int>('id'),
    row.read<String>('status'),
    DateTime.parse(row.read<String>('started_at')),
    DateTime.tryParse(row.readNullable<String>('ended_at') ?? ''),
    Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')) as Map),
  );
  String get name => data['workoutName'] as String;
  bool get unfinished => status == 'active' || status == 'paused';
  List<Map<String, dynamic>> get exercises =>
      (data['exercises'] as List).cast<Map<String, dynamic>>();

  /// Include actuals recorded before switching to a different alternative.
  Iterable<Map<String, dynamic>> get loggedExercises sync* {
    for (final exercise in exercises) {
      yield exercise;
      final states = exercise['alternativeStates'] as Map? ?? {};
      for (final state in states.entries) {
        if (state.key == '${exercise['selectedAlternative']}') continue;
        final saved = Map<String, dynamic>.from(state.value as Map);
        if ((saved['actualSets'] as List).any(
          (s) => (s as Map).length > 1 || s['completed'] == true,
        )) {
          yield {
            ...saved,
            'selectedAlternative': int.parse(state.key as String),
          };
        }
      }
    }
  }

  int get completedSets => loggedExercises.fold(
    0,
    (sum, e) =>
        sum +
        (e['actualSets'] as List).where((s) => s['completed'] == true).length,
  );
  int get totalSets => loggedExercises.fold(
    0,
    (sum, e) => sum + (e['actualSets'] as List).length,
  );
  int restRemaining(DateTime now) {
    if (status == 'paused') return data['pausedRestSeconds'] as int? ?? 0;
    final deadline = DateTime.tryParse(data['restUntil'] as String? ?? '');
    if (deadline == null || !unfinished) return 0;
    final milliseconds = deadline.difference(now.toUtc()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }
}

String unitLabel(dynamic value, String fallback) =>
    value is String && value.trim().isNotEmpty ? value : fallback;

/// Explicit actuals replace ranges and quality guidance in a set's display.
String setMeasurementText(
  Map<String, dynamic> target,
  Map<String, dynamic> actual,
) => measurementText({
  ...target,
  ...actual,
  if (actual.containsKey('reps')) 'repsMax': null,
  if (actual.containsKey('reps')) 'repsUnknown': false,
  if (actual.containsKey('durationSeconds')) 'durationMaxSeconds': null,
});

String measurementText(Map<String, dynamic> values, {String? type}) {
  final resolvedType = type ?? values['type'] as String? ?? 'weighted';
  final parts = <String>[];
  final completed = values['completed'] == true;
  if (resolvedType.startsWith('timed')) {
    parts.add(
      '${values['durationSeconds'] ?? '?'}${completed || values['durationMaxSeconds'] == null ? '' : '–${values['durationMaxSeconds']}'} sec',
    );
  } else if (resolvedType == 'distance') {
    parts.add(
      '${values['distance'] ?? '?'} ${unitLabel(values['distanceUnit'], 'distance units unconfirmed')}',
    );
  } else {
    parts.add(
      values['repsUnknown'] == true && !completed
          ? 'quality set (reps as able)'
          : '${values['reps'] ?? '?'}${completed || values['repsMax'] == null ? '' : '–${values['repsMax']}'} reps',
    );
  }
  if (values['load'] != null) {
    parts.add(
      '${values['load']} ${unitLabel(values['loadUnit'], 'load (unit unconfirmed)')}',
    );
  } else if (resolvedType == 'weighted') {
    parts.add('load unknown');
  } else if (resolvedType == 'bodyweight') {
    parts.add('bodyweight');
  }
  return parts.join(' / ');
}

/// Reuse manual working loads only while the configured prescription is unchanged.
/// Explicit template edits and Progress/Maintain targets always take precedence.
Map<String, dynamic> workingTarget(
  Map<String, dynamic> target,
  Map<String, dynamic>? previous,
) {
  if (target['progression'] != 'Manual' || previous == null) return target;
  final old = previous['target'] as Map;
  for (final key in [
    'type',
    'loadUnit',
    'load',
    'sets',
    'reps',
    'durationSeconds',
    'distance',
    'distanceUnit',
  ]) {
    final oldValue = key == 'load' && old.containsKey('configuredLoad')
        ? old['configuredLoad']
        : old[key];
    if (oldValue != target[key]) return target;
  }
  final sets = previous['sets'] as List;
  final load = sets.isEmpty ? null : (sets.last as Map)['load'];
  if (load is! num || !load.isFinite || load < 0) return target;
  return {...target, 'configuredLoad': target['load'], 'load': load};
}
