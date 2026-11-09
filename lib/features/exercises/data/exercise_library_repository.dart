import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/data/workout_alternatives.dart';
import '../../workout/data/compact_workout_upgrade.dart';
import '../../workout/data/custom_workout_repository.dart';
import '../../workout/data/personal_workout_seed.dart';
import '../../strength/data/workout_discovery.dart';

class ExerciseUse {
  final WorkoutRecord workout, entry;
  final int? alternative;
  final Map<String, dynamic> target;
  final String programName;
  const ExerciseUse(
    this.workout,
    this.entry,
    this.alternative,
    this.target, [
    this.programName = '',
  ]);
  String get label =>
      '${workout.name}${programName.isEmpty ? '' : ' ($programName)'}${workout.archived ? ' (archived)' : ''}${alternative == null ? '' : ' - Option ${String.fromCharCode(65 + alternative!)}'}';
}

class ExerciseLibraryRepository {
  final WorkoutRepository workouts;
  ExerciseLibraryRepository(this.workouts);
  Future<List<ExerciseUse>> usages(int exerciseId) async {
    final templates = await workouts.list('workout', includeArchived: true);
    // The additive A/B upgrade retains its source records. Identify them by
    // relationship, never by a similar workout name (even if a variant is archived).
    final sources = {
      for (final w in templates)
        if (w.values[compactVariantKey] != null) w.values['sourceWorkoutId'],
    };
    final activePrograms = await workouts.list('program');
    final personalProgram = activePrograms
        .where((p) => p.values['importKey'] == personalPlanKey)
        .firstOrNull;
    final all = {
      for (final w in templates)
        if (!w.archived &&
            !sources.contains(w.id) &&
            // Match Home's six personal variants and active custom workouts.
            (w.values[customWorkoutKey] == true ||
                personalProgram != null &&
                    w.parentId == personalProgram.id &&
                    compactVariantNames.contains(w.values[compactVariantKey])))
          w.id: w,
    };
    final programs = {for (final p in activePrograms) p.id: p.name};
    final result = <ExerciseUse>[];
    for (final entry in await workouts.list('entry')) {
      final workout = all[entry.parentId];
      if (workout == null || !programs.containsKey(workout.parentId)) continue;
      final options = entry.values['alternatives'] as List?;
      if (options == null) {
        if (entry.values['exerciseId'] == exerciseId) {
          result.add(
            ExerciseUse(
              workout,
              entry,
              null,
              await workouts.resolvedEntry(entry),
              programs[workout.parentId] ?? '',
            ),
          );
        }
      } else {
        for (var i = 0; i < options.length; i++) {
          if (options[i]['exerciseId'] == exerciseId) {
            result.add(
              ExerciseUse(
                workout,
                entry,
                i,
                await workouts.resolvedEntry(entry, alternative: i),
                programs[workout.parentId] ?? '',
              ),
            );
          }
        }
      }
    }
    result.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return result;
  }

  /// Patch canonical identities, including unselected alternatives, without touching snapshots.
  Future<void> update(
    int exerciseId,
    Map<String, dynamic> changes, {
    int? workoutId,
  }) => workouts.db.transaction(() async {
    const allowed = [
      'name',
      'load',
      'loadUnit',
      'sets',
      'reps',
      'durationSeconds',
      'distance',
      'distanceUnit',
      'notes',
      'progression',
    ];
    if (changes.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Invalid prescription field');
    }
    if (changes.containsKey('name')) {
      final name = changes['name'];
      if (name is! String || name.trim().isEmpty) {
        throw ArgumentError('Name is required');
      }
      changes = {...changes, 'name': name.trim()};
    }
    final exercise = await workouts.get(exerciseId);
    if (exercise.kind != 'exercise') throw ArgumentError('Choose an exercise');
    if (changes.isEmpty) return;
    Map<String, dynamic> patch(
      Map<String, dynamic> old, {
      bool template = true,
    }) {
      final next = {...old, ...changes};
      if (template && changes.containsKey('name')) {
        next['displayName'] = changes['name'];
      }
      if (changes.containsKey('reps')) {
        next.remove('repsMax');
        if (changes['reps'] != null) next['repsUnknown'] = false;
      }
      if (changes.containsKey('durationSeconds')) {
        next.remove('durationMaxSeconds');
      }
      return next;
    }

    // Validate the patch even when an exercise has no current template uses.
    workouts.validate('exercise', patch(exercise.values, template: false));
    var matched = false;
    for (final entry in await workouts.list('entry', includeArchived: true)) {
      if (workoutId != null && entry.parentId != workoutId) continue;
      final options = entry.values['alternatives'] as List?;
      if (options == null) {
        if (entry.values['exerciseId'] != exerciseId) continue;
        await workouts.edit(entry.id, patch(entry.values));
        matched = true;
      } else {
        if (!options.any((o) => o['exerciseId'] == exerciseId)) continue;
        final updated = [
          for (final o in options)
            o['exerciseId'] == exerciseId
                ? patch(Map<String, dynamic>.from(o as Map))
                : Map<String, dynamic>.from(o as Map),
        ];
        final values = selectWorkoutAlternative({
          ...entry.values,
          'alternatives': updated,
        }, entry.values['selectedAlternative'] as int? ?? 0);
        await workouts.edit(entry.id, values);
        matched = true;
      }
    }
    if (workoutId != null && !matched) {
      throw StateError('This exercise is no longer in that workout');
    }
    if (workoutId == null) {
      await workouts.edit(exercise.id, patch(exercise.values, template: false));
    }
  });
}

final exerciseLibraryRepositoryProvider = Provider(
  (ref) => ExerciseLibraryRepository(ref.watch(workoutRepositoryProvider)),
);
final exerciseLibraryProvider = FutureProvider<List<WorkoutRecord>>((
  ref,
) async {
  ref.watch(managementRevisionProvider);
  await ref.watch(compactWorkoutsProvider.future);
  final exercises = await ref
      .watch(workoutRepositoryProvider)
      .list('exercise', includeArchived: true);
  exercises.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return exercises;
});
final exerciseUsesProvider = FutureProvider.family<List<ExerciseUse>, int>((
  ref,
  id,
) async {
  ref.watch(managementRevisionProvider);
  await ref.watch(compactWorkoutsProvider.future);
  return ref.watch(exerciseLibraryRepositoryProvider).usages(id);
});
