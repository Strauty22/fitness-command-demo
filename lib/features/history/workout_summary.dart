import '../strength/compact_prescription.dart';
import '../strength/data/strength_session.dart';

String historyDate(DateTime date) {
  final local = date.toLocal();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[local.weekday - 1]}, ${months[local.month - 1]} ${local.day}, ${local.year}';
}

String summaryNumber(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String groupedNumber(num value) => summaryNumber(
  value,
).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

String summaryDuration(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  if (seconds >= 60 && seconds % 60 == 0) return '${seconds ~/ 60} min';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> completedActuals(Map<String, dynamic> exercise) =>
    (exercise['actualSets'] as List)
        .where((s) => s['completed'] == true)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

List<Map<String, dynamic>> summaryExercises(StrengthSession session) => session
    .loggedExercises
    .where((e) => completedActuals(e).isNotEmpty)
    .take(3)
    .toList();

String actualSummary(Map<String, dynamic> exercise, Map<String, dynamic> set) {
  final target = exercise['target'] as Map;
  final type = target['type'] as String? ?? 'weighted';
  final parts = <String>[];
  if (type.startsWith('timed')) {
    parts.add(
      set['durationSeconds'] is num
          ? summaryDuration(
              Duration(
                milliseconds: ((set['durationSeconds'] as num) * 1000).round(),
              ),
            )
          : 'time unrecorded',
    );
  } else if (type == 'distance') {
    parts.add(
      set['distance'] is num
          ? '${summaryNumber(set['distance'] as num)} ${unitLabel(target['distanceUnit'], 'units unconfirmed')}'
          : 'distance unrecorded',
    );
  } else {
    parts.add(
      set['reps'] is num
          ? '${summaryNumber(set['reps'] as num)} reps'
          : 'reps unrecorded',
    );
  }
  if (set['load'] is num) {
    parts.add(
      '${summaryNumber(set['load'] as num)} ${unitLabel(displayLoadUnit(Map<String, dynamic>.from(target)), 'units unconfirmed')}',
    );
  } else if (type == 'bodyweight') {
    parts.add('BW');
  } else if (type == 'weighted') {
    parts.add('load unrecorded');
  }
  return parts.join(' / ');
}

String exerciseSummary(Map<String, dynamic> exercise) {
  final results = completedActuals(
    exercise,
  ).map((s) => actualSummary(exercise, s)).toList();
  if (results.isEmpty) return '';
  if (results.every((s) => s == results.first)) {
    return '${results.length}\u00d7${results.first}';
  }
  return results.join('; ');
}

/// Only known external lifting loads count; unknown units and assistance do not.
double liftingVolumePounds(StrengthSession session) {
  double volume = 0;
  for (final exercise in session.loggedExercises) {
    final target = exercise['target'] as Map;
    final type = target['type'] ?? 'weighted';
    if (type != 'weighted' && type != 'bodyweight') continue;
    if (target['assisted'] == true) continue;
    for (final set in completedActuals(exercise)) {
      final reps = set['reps'], load = set['load'];
      if (reps is! num || load is! num || reps < 0 || load < 0) continue;
      final unit = displayLoadUnit({
        ...Map<String, dynamic>.from(target),
        if (set.containsKey('loadUnit')) 'loadUnit': set['loadUnit'],
      }).toLowerCase();
      final factor = switch (unit) {
        'lb' || 'lbs' => 1.0,
        'kg' => 2.2046226218,
        _ => 0.0,
      };
      volume += reps * load * factor;
    }
  }
  return volume;
}

Duration strengthDuration(StrengthSession session) =>
    (session.endedAt ?? session.startedAt).difference(session.startedAt);
