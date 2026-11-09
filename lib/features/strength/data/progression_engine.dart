/// Pure progression rules. Inputs and historical actuals are never mutated.
class ProgressionEngine {
  static void validate(Map<String, dynamic> target) {
    for (final key in ['successCount', 'failureCount', 'allowedFailedSets']) {
      final n = target[key];
      if (n != null &&
          (n is! num ||
              !n.isFinite ||
              n != n.round() ||
              n < (key == 'successCount' ? 1 : 0))) {
        throw ArgumentError('Invalid $key');
      }
    }
    final percent = target['deloadPercent'];
    if (percent != null &&
        (percent is! num ||
            !percent.isFinite ||
            percent < 0 ||
            percent > 100)) {
      throw ArgumentError('Deload percent must be 0–100');
    }
  }

  /// Different template prescriptions keep separate counters, shared by identity.
  static String signature(Map<String, dynamic> t) => [
    for (final k in [
      'type',
      'load',
      'loadUnit',
      'sets',
      'reps',
      'durationSeconds',
      'distance',
      'distanceUnit',
      'increment',
      'successCount',
      'allowedFailedSets',
      'failureCount',
      'deloadPercent',
    ])
      '$k=${t[k]}',
  ].join('|');

  static Map<String, dynamic> evaluate(
    Map<String, dynamic> target,
    List<Map<String, dynamic>> actuals,
    Map<String, dynamic> state, {
    bool skipped = false,
  }) {
    validate(target);
    final next = Map<String, dynamic>.from(state);
    if (skipped ||
        target['progression'] != 'Progress' ||
        target['load'] is! num ||
        (target['loadUnit'] as String? ?? '').trim().isEmpty ||
        target['type'] == 'bodyweight') {
      return next;
    }
    final count = (target['sets'] as num? ?? 1).toInt();
    final metrics = [
      'reps',
      'durationSeconds',
      'distance',
    ].where((k) => target[k] is num).toList();
    if (metrics.isEmpty || target['repsUnknown'] == true) return next;
    var failed = 0;
    for (var i = 0; i < count; i++) {
      if (i >= actuals.length) {
        failed++;
        continue;
      }
      final set = actuals[i];
      if (set['completed'] != true ||
          [...metrics, 'load'].any(
            (k) =>
                set[k] is! num ||
                !(set[k] as num).isFinite ||
                (set[k] as num) < (target[k] as num),
          )) {
        failed++;
      }
    }
    final success = failed <= (target['allowedFailedSets'] as num? ?? 0);
    var wins = success ? (state['wins'] as int? ?? 0) + 1 : 0;
    var losses = success ? 0 : (state['losses'] as int? ?? 0) + 1;
    num load = target['load'] as num;
    if (wins >= (target['successCount'] as num? ?? 1)) {
      load += target['increment'] as num? ?? 0;
      wins = 0;
    }
    final threshold = target['failureCount'] as num? ?? 0;
    if (threshold > 0 && losses >= threshold) {
      load *= 1 - (target['deloadPercent'] as num? ?? 0) / 100;
      losses = 0;
    }
    // Stable decimal output without imposing equipment rounding rules.
    next.addAll({
      'load': double.parse(load.toStringAsFixed(8)),
      'wins': wins,
      'losses': losses,
    });
    return next;
  }
}
