import '../strength/data/strength_session.dart';
import '../strength/compact_prescription.dart';
import '../cycling/data/ride.dart';
import 'workout_history_card.dart';

class ExerciseBest {
  final String key, name;
  final double pounds;
  final DateTime date;
  final int sessionId;
  const ExerciseBest(
    this.key,
    this.name,
    this.pounds,
    this.date,
    this.sessionId,
  );
}

String exerciseRecordKey(Map<String, dynamic> exercise) =>
    exercise['exerciseId'] == null
    ? 'name:${(exercise['name'] as String).trim().toLowerCase()}'
    : 'id:${exercise['exerciseId']}';

// Only actual successful repetitions with a known external load qualify.
double? completedPounds(Map exercise, Map set) {
  final target = Map<String, dynamic>.from(exercise['target'] as Map);
  final reps = set['reps'], load = set['load'];
  if (set['completed'] != true ||
      reps is! num ||
      !reps.isFinite ||
      reps < 1 ||
      load is! num ||
      !load.isFinite ||
      load < 0) {
    return null;
  }
  final unit = displayLoadUnit({
    ...target,
    if (set['loadUnit'] != null) 'loadUnit': set['loadUnit'],
  }).toLowerCase();
  return switch (unit) {
    'lb' || 'lbs' => load.toDouble(),
    'kg' => load * 2.2046226218,
    _ => null,
  };
}

List<ExerciseBest> exerciseBests(Iterable<StrengthSession> sessions) {
  final records = <String, ExerciseBest>{};
  for (final session in sessions.where((s) => s.status == 'completed')) {
    for (final exercise in session.loggedExercises) {
      for (final raw in exercise['actualSets'] as List) {
        final set = raw as Map;
        final load = completedPounds(exercise, set);
        if (load == null) continue;
        final key = exerciseRecordKey(exercise);
        final date =
            DateTime.tryParse(set['completedAt'] as String? ?? '') ??
            session.endedAt ??
            session.startedAt;
        final candidate = ExerciseBest(
          key,
          exercise['name'] as String,
          load,
          date,
          session.id,
        );
        final old = records[key];
        if (old == null ||
            load > old.pounds ||
            load == old.pounds &&
                (date.isBefore(old.date) ||
                    date.isAtSameMomentAs(old.date) &&
                        session.id < old.sessionId)) {
          records[key] = candidate;
        }
      }
    }
  }
  return records.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

// Compute records against previously finished workouts; active actuals are used
// only for the in-workout indicator, never for lifetime totals or Progress.
Set<String> newExerciseRecords(
  StrengthSession session,
  Iterable<StrengthSession> history,
) {
  if (session.status != 'completed' && !session.unfinished) return {};
  final previous = {
    for (final best in exerciseBests(
      history.where(
        (s) =>
            s.id != session.id &&
            !(s.endedAt ?? s.startedAt).isAfter(session.startedAt),
      ),
    ))
      best.key: best.pounds,
  };
  final result = <String>{};
  for (final exercise in session.loggedExercises) {
    final key = exerciseRecordKey(exercise);
    for (final set in exercise['actualSets'] as List) {
      final load = completedPounds(exercise, set as Map);
      if (load != null && (previous[key] == null || load > previous[key]!)) {
        result.add(key);
      }
    }
  }
  return result;
}

List<Ride> personalBestRides(Iterable<Ride> rides) {
  final records = <String, Ride>{};
  for (final ride in rides) {
    if (ride.status != 'completed') continue;
    final speed = ride.averageSpeed(ride.ended ?? ride.started);
    final key = savedRideName(ride).trim().toLowerCase();
    final old = records[key];
    final oldSpeed = old?.averageSpeed(old.ended ?? old.started);
    final ended = ride.ended ?? ride.started;
    final oldEnded = old?.ended ?? old?.started;
    if (old == null ||
        speed != null && (oldSpeed == null || speed > oldSpeed) ||
        speed == oldSpeed &&
            oldEnded != null &&
            (ended.isBefore(oldEnded) ||
                ended.isAtSameMomentAs(oldEnded) &&
                    ride.id.compareTo(old.id) < 0)) {
      records[key] = ride;
    }
  }
  return records.values.toList()..sort(
    (a, b) => savedRideName(
      a,
    ).toLowerCase().compareTo(savedRideName(b).toLowerCase()),
  );
}
