import '../../workout/data/compact_workout_upgrade.dart';
import '../../workout/data/custom_workout_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workout/data/workout_repository.dart';

class WorkoutRecommendation {
  final WorkoutRecord workout, program;
  final DateTime date;
  const WorkoutRecommendation(this.workout, this.program, this.date);
  bool isToday(DateTime now) =>
      date.year == now.year && date.month == now.month && date.day == now.day;
}

/// Find the earliest strength schedule, including future rotation weeks.
/// Calendar date constructors avoid daylight-saving duration shifts.
WorkoutRecommendation? recommendWorkout({
  required List<WorkoutRecord> programs,
  required List<WorkoutRecord> workouts,
  required List<WorkoutRecord> rules,
  required DateTime now,
  int? programId,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final available = {
    for (final w in workouts)
      if (!w.archived) w.id: w,
  };
  WorkoutRecommendation? best;
  for (final program in programs) {
    if (program.archived || programId != null && program.id != programId) {
      continue;
    }
    final cycle = program.values['cycle'] as List;
    final anchor = DateTime.parse(program.values['anchor'] as String);
    final override = program.values['weekOverride'] as int?;
    for (final rule in rules) {
      if (rule.archived || rule.parentId != program.id) continue;
      final workout = available[rule.values['workoutId']];
      if (workout == null || workout.parentId != program.id) continue;
      final day = rule.values['weekday'] as int;
      var candidate = DateTime(
        today.year,
        today.month,
        today.day + (day - today.weekday) % 7,
      );
      final week = rule.values['week'] as int?;
      if (week != null) {
        if (week < 0 ||
            week >= cycle.length ||
            override != null && override != week) {
          continue;
        }
        final current = rotationIndex(
          candidate,
          anchor,
          cycle.length,
          override: override,
        );
        candidate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day + ((week - current) % cycle.length) * 7,
        );
      }
      if (best == null || candidate.isBefore(best.date)) {
        best = WorkoutRecommendation(workout, program, candidate);
      }
    }
  }
  return best;
}

class WorkoutDiscovery {
  final List<WorkoutRecord> programs, workouts;
  final int? programId;
  final WorkoutRecommendation? recommendation;
  const WorkoutDiscovery(
    this.programs,
    this.workouts,
    this.programId,
    this.recommendation,
  );
}

/// Uses existing local records for one UI preference; no schema or program edits.
class WorkoutDiscoveryRepository {
  final WorkoutRepository workouts;
  WorkoutDiscoveryRepository(this.workouts);
  static const preferenceName = 'Workout recommendation program';

  static const selectionName = 'Selected workout';
  Future<int?> selectedWorkout() async {
    for (final p in await workouts.list('preference')) {
      if (p.name == selectionName) return p.values['workoutId'] as int?;
    }
    return null;
  }

  Future<void> selectWorkout(int id) => workouts.db.transaction(() async {
    final workout = await workouts.get(id);
    if (workout.kind != 'workout' || workout.archived) {
      throw ArgumentError('Unavailable workout');
    }
    final matches = (await workouts.list(
      'preference',
    )).where((p) => p.name == selectionName);
    final values = <String, dynamic>{'name': selectionName, 'workoutId': id};
    if (matches.isEmpty) {
      await workouts.create('preference', values);
    } else {
      await workouts.edit(matches.first.id, values);
    }
  });

  Future<int?> selectedProgram() async {
    final preferences = await workouts.list('preference');
    for (final pref in preferences) {
      if (pref.name == preferenceName) return pref.values['programId'] as int?;
    }
    return null;
  }

  Future<void> selectProgram(int? id) => workouts.db.transaction(() async {
    if (id != null) {
      final program = await workouts.get(id);
      if (program.kind != 'program' || program.archived) {
        throw ArgumentError('Choose an active program');
      }
    }
    final matches = (await workouts.list(
      'preference',
    )).where((p) => p.name == preferenceName);
    final values = <String, dynamic>{'name': preferenceName, 'programId': id};
    if (matches.isEmpty) {
      await workouts.create('preference', values);
    } else {
      await workouts.edit(matches.first.id, values);
    }
  });

  Future<WorkoutDiscovery> load(DateTime now) async {
    final programs = await workouts.list('program');
    final ids = programs.map((p) => p.id).toSet();
    final all = (await workouts.list(
      'workout',
    )).where((w) => ids.contains(w.parentId)).toList();
    final saved = await selectedProgram();
    final selected = ids.contains(saved) ? saved : null;
    return WorkoutDiscovery(programs, all, selected, null);
  }
}

final workoutClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final workoutDiscoveryRepositoryProvider = Provider(
  (ref) => WorkoutDiscoveryRepository(ref.watch(workoutRepositoryProvider)),
);
final workoutChoicesProvider = FutureProvider.autoDispose<WorkoutDiscovery>((
  ref,
) async {
  ref.watch(managementRevisionProvider);
  await ref.watch(managementReadyProvider.future);
  return ref
      .watch(workoutDiscoveryRepositoryProvider)
      .load(ref.watch(workoutClockProvider)());
});

final selectedWorkoutProvider = FutureProvider<int?>((ref) async {
  ref.watch(managementRevisionProvider);
  await ref.watch(managementReadyProvider.future);
  return ref.watch(workoutDiscoveryRepositoryProvider).selectedWorkout();
});

final compactWorkoutsProvider = FutureProvider<List<WorkoutRecord>>((
  ref,
) async {
  ref.watch(managementRevisionProvider);
  await ref.watch(managementReadyProvider.future);
  return ensureCompactWorkouts(ref.watch(workoutRepositoryProvider));
});

final homeWorkoutsProvider = FutureProvider<List<WorkoutRecord>>((ref) async {
  ref.watch(managementRevisionProvider);
  final custom = ref.watch(customWorkoutRepositoryProvider);
  await ref.watch(managementReadyProvider.future);
  final originals = await ensureCompactWorkouts(custom.workouts);
  return [...originals, ...await custom.list()];
});
