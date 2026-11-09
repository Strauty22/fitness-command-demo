import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workout/data/workout_repository.dart';

class RotationState {
  final DateTime? anchor;
  final int? override;
  const RotationState(this.anchor, this.override);
  // Home is informational and automatic; retained manual preferences cannot pin it.
  int? week(DateTime now) {
    if (anchor == null) return null;
    DateTime sunday(DateTime date) =>
        DateTime.utc(date.year, date.month, date.day - date.weekday % 7);
    // UTC calendar dates avoid daylight-saving shifts in elapsed day counts.
    return (sunday(now).difference(sunday(anchor!)).inDays ~/ 7) % 2;
  }
}

class RotationRepository {
  final WorkoutRepository workouts;
  RotationRepository(this.workouts);
  static const preferenceName = 'Informational A/B rotation';
  Future<RotationState> load() => workouts.db.transaction(() async {
    final saved = (await workouts.list(
      'preference',
    )).where((p) => p.name == preferenceName).firstOrNull;
    if (saved != null) {
      return RotationState(
        DateTime.tryParse(saved.values['anchor'] as String? ?? ''),
        saved.values['weekOverride'] as int?,
      );
    }
    // The imported single-week plan does not replace the original A/B anchor.
    final source = (await workouts.list('program', includeArchived: true))
        .where(
          (p) =>
              (p.values['cycle'] as List? ?? []).length == 2 &&
              DateTime.tryParse(p.values['anchor'] as String? ?? '') != null,
        )
        .firstOrNull;
    final anchor = source == null
        ? null
        : DateTime.parse(source.values['anchor'] as String);
    final override = source?.values['weekOverride'] as int?;
    await workouts.create('preference', {
      'name': preferenceName,
      'anchor': anchor?.toIso8601String().substring(0, 10),
      'weekOverride': override,
    });
    return RotationState(anchor, override);
  });
  Future<void> save({DateTime? anchor, int? override}) =>
      workouts.db.transaction(() async {
        if (override != null && override != 0 && override != 1) {
          throw ArgumentError('Choose Week A or Week B');
        }
        final current = await load();
        final record = (await workouts.list(
          'preference',
        )).firstWhere((p) => p.name == preferenceName);
        await workouts.edit(record.id, {
          ...record.values,
          'anchor': (anchor ?? current.anchor)?.toIso8601String().substring(
            0,
            10,
          ),
          'weekOverride': override,
        });
      });
}

final rotationRepositoryProvider = Provider(
  (ref) => RotationRepository(ref.watch(workoutRepositoryProvider)),
);
final rotationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final rotationProvider = FutureProvider<RotationState>((ref) async {
  await ref.watch(managementReadyProvider.future);
  return ref.watch(rotationRepositoryProvider).load();
});
