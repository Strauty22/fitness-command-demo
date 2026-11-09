import '../workout/data/personal_workout_seed.dart';

String displayLoadUnit(Map<String, dynamic> target) {
  final unit = (target['loadUnit'] as String? ?? '').trim();
  return unit.isNotEmpty
      ? unit
      : target['importKey'] == personalPlanKey
      ? 'lb'
      : '';
}

String compactPrescription(Map<String, dynamic> target, int sets) {
  final type = target['type'] as String? ?? 'weighted';
  final metric = type.startsWith('timed')
      ? '${target['durationSeconds'] ?? "?"}s'
      : type == 'distance'
      ? '${target['distance'] ?? "?"} ${target['distanceUnit'] ?? ""}'
      : '${target['reps'] ?? "?"}';
  final load = target['load'];
  final unit = displayLoadUnit(target);
  final weight = load != null
      ? '$load${unit.isEmpty ? "" : " $unit"}'
      : type == 'bodyweight'
      ? 'BW'
      : '';
  return '$sets\u00d7$metric${weight.isEmpty ? "" : "  $weight"}';
}
