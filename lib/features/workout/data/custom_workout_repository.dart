import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'workout_repository.dart';
import 'workout_alternatives.dart';

const customWorkoutKey = 'customWorkout';

String normalizedExerciseName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class DuplicateExercise implements Exception {
  final WorkoutRecord exercise;
  DuplicateExercise(this.exercise);
  @override
  String toString() =>
      'An exercise named ${exercise.name} already exists. Choose it from the library.';
}

class WorkoutExerciseDraft {
  final int? entryId;
  final int? exerciseId;
  final Map<String, dynamic> values;
  const WorkoutExerciseDraft(this.values, {this.entryId, this.exerciseId});
  String get name =>
      values['displayName'] as String? ?? values['name'] as String;
  WorkoutExerciseDraft edited(Map<String, dynamic> next) =>
      WorkoutExerciseDraft(next, entryId: entryId, exerciseId: exerciseId);
}

/// Copy prescription defaults, never a source workout's identity or alternatives.
Map<String, dynamic> exerciseDraftValues(
  WorkoutRecord exercise, [
  Map<String, dynamic>? target,
]) => {
  'type': 'weighted',
  'sets': 2,
  'reps': 10,
  'progression': 'Manual',
  for (final key in alternativeFields)
    if (!['name', 'displayName', 'exerciseId'].contains(key) &&
        (target ?? exercise.values).containsKey(key))
      key: (target ?? exercise.values)[key],
  'name': exercise.name,
};

class CustomWorkoutRepository {
  final WorkoutRepository workouts;
  CustomWorkoutRepository(this.workouts);

  Future<List<WorkoutRecord>> list() async {
    final programs = (await workouts.list('program')).map((p) => p.id).toSet();
    return (await workouts.list('workout'))
        .where(
          (w) =>
              w.values[customWorkoutKey] == true &&
              programs.contains(w.parentId),
        )
        .toList();
  }

  Future<List<WorkoutExerciseDraft>> entries(int workoutId) async {
    await _custom(workoutId);
    return [
      for (final entry in await workouts.list('entry', parentId: workoutId))
        WorkoutExerciseDraft(
          {
            ...exerciseDraftValues(
              await workouts.get(entry.values['exerciseId'] as int),
              await workouts.resolvedEntry(entry),
            ),
            ...entry.values,
          },
          entryId: entry.id,
          exerciseId: entry.values['exerciseId'] as int,
        ),
    ];
  }

  Future<WorkoutRecord> _custom(int id) async {
    final record = await workouts.get(id);
    if (record.kind != 'workout' ||
        record.archived ||
        record.values[customWorkoutKey] != true) {
      throw StateError('Choose an available custom workout');
    }
    return record;
  }

  /// Save the entire draft atomically. Shared exercises and session snapshots
  /// are never edited; removed entries are archived to retain their identifiers.
  Future<int> save({
    int? workoutId,
    required String name,
    required String notes,
    required List<WorkoutExerciseDraft> exercises,
  }) => workouts.db.transaction(() async {
    if (name.trim().isEmpty) throw ArgumentError('Workout name is required');
    if (exercises.isEmpty) throw ArgumentError('Add at least one exercise');
    final previous = workoutId == null ? null : await _custom(workoutId);
    final oldEntries = previous == null
        ? <WorkoutRecord>[]
        : await workouts.list(
            'entry',
            parentId: workoutId,
            includeArchived: true,
          );
    final retained = <int>{};
    final identities = await workouts.list('exercise', includeArchived: true);
    // Validate every draft before writing any records.
    final pendingNames = <String>{};
    for (final draft in exercises) {
      workouts.validate('exercise', draft.values);
      if (draft.entryId != null &&
          (!oldEntries.any(
                (e) =>
                    e.id == draft.entryId &&
                    e.values['exerciseId'] == draft.exerciseId,
              ) ||
              !retained.add(draft.entryId!))) {
        throw ArgumentError('Invalid workout entry');
      }
      if (draft.exerciseId != null) {
        if (!identities.any((e) => e.id == draft.exerciseId)) {
          throw ArgumentError('Choose an existing exercise');
        }
      } else {
        final key = normalizedExerciseName(draft.values['name'] as String);
        final duplicate = identities
            .where((e) => normalizedExerciseName(e.name) == key)
            .firstOrNull;
        if (duplicate != null) throw DuplicateExercise(duplicate);
        if (!pendingNames.add(key)) {
          throw ArgumentError('This new exercise is already in your draft');
        }
      }
    }
    int programId;
    if (previous != null) {
      programId = previous.parentId!;
    } else {
      final programs = await workouts.list('program');
      final program = programs
          .where((p) => p.values['customWorkoutProgram'] == true)
          .firstOrNull;
      programId =
          program?.id ??
          await workouts.create('program', {
            'name': 'Custom workouts',
            'customWorkoutProgram': true,
            'cycle': ['Week A', 'Week B'],
            'anchor': '2026-10-19',
            'sets': 2,
            'reps': 10,
            'restSeconds': 90,
          });
    }
    final values = {
      ...?previous?.values,
      'name': name.trim(),
      'notes': notes.trim(),
      customWorkoutKey: true,
    };
    final id =
        workoutId ??
        await workouts.create('workout', values, parentId: programId);
    if (previous != null) await workouts.edit(id, values);
    final order = <int>[];
    for (final draft in exercises) {
      final exerciseId =
          draft.exerciseId ??
          await workouts.create('exercise', {
            for (final key in alternativeFields)
              if (key != 'exerciseId' &&
                  key != 'displayName' &&
                  draft.values.containsKey(key))
                key: draft.values[key],
          });
      final entryValues = {...draft.values, 'exerciseId': exerciseId};
      if (draft.entryId == null) {
        order.add(await workouts.create('entry', entryValues, parentId: id));
      } else {
        await workouts.edit(draft.entryId!, entryValues);
        await workouts.archive(draft.entryId!, false);
        order.add(draft.entryId!);
      }
    }
    for (final entry in oldEntries) {
      if (!order.contains(entry.id)) await workouts.archive(entry.id, true);
    }
    await workouts.reorder('entry', id, order);
    return id;
  });

  Future<void> delete(int id) => workouts.db.transaction(() async {
    await _custom(id);
    await workouts.archive(id, true);
    // Clear only a selection pointing at the deleted template.
    for (final pref in await workouts.list('preference')) {
      if (pref.name == 'Selected workout' && pref.values['workoutId'] == id) {
        await workouts.edit(pref.id, {...pref.values, 'workoutId': null});
      }
    }
  });
}

final customWorkoutRepositoryProvider = Provider(
  (ref) => CustomWorkoutRepository(ref.watch(workoutRepositoryProvider)),
);
