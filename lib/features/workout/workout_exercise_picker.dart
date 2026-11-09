import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../exercises/data/exercise_library_repository.dart';
import '../exercises/prescription_editor.dart';
import 'data/workout_repository.dart';
import 'data/custom_workout_repository.dart';

Future<WorkoutExerciseDraft?> resolveNewExercise(
  BuildContext context,
  WidgetRef ref,
  WorkoutExerciseDraft draft,
) async {
  final all = await ref
      .read(workoutRepositoryProvider)
      .list('exercise', includeArchived: true);
  final duplicate = all
      .where(
        (e) =>
            normalizedExerciseName(e.name) ==
            normalizedExerciseName(draft.values['name'] as String),
      )
      .firstOrNull;
  if (!context.mounted) return null;
  if (duplicate == null) return draft;
  final reuse = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Exercise already exists'),
      content: Text(
        'Use ${duplicate.name} from the library? Your settings will apply only to this workout.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Use Existing Exercise'),
        ),
      ],
    ),
  );
  return reuse == true
      ? WorkoutExerciseDraft(draft.values, exerciseId: duplicate.id)
      : null;
}

Future<WorkoutExerciseDraft?> editWorkoutExercise(
  BuildContext context,
  WorkoutExerciseDraft draft, {
  bool isNew = false,
}) async {
  Map<String, dynamic>? result;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PrescriptionEditor(
      exercise: WorkoutRecord(
        draft.exerciseId ?? -1,
        'exercise',
        null,
        0,
        false,
        draft.values,
      ),
      uses: const [],
      newExercise: isNew,
      onSaveDraft: (values) => result = values,
    ),
  );
  return result == null ? null : draft.edited(result!);
}

class WorkoutExercisePicker extends ConsumerStatefulWidget {
  const WorkoutExercisePicker({super.key});
  @override
  ConsumerState<WorkoutExercisePicker> createState() =>
      _WorkoutExercisePickerState();
}

class _WorkoutExercisePickerState extends ConsumerState<WorkoutExercisePicker> {
  String query = '';
  bool loading = false;
  String? error;
  Future<void> create() async {
    if (loading) return;
    setState(() => error = null);
    try {
      var result = await editWorkoutExercise(
        context,
        const WorkoutExerciseDraft({
          'name': '',
          'type': 'weighted',
          'sets': 2,
          'reps': 10,
          'loadUnit': 'lb',
          'progression': 'Manual',
        }),
        isNew: true,
      );
      if (!mounted || result == null) return;
      result = await resolveNewExercise(context, ref, result);
      if (mounted && result != null) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not create exercise: $e');
    }
  }

  Future<void> choose(WorkoutRecord exercise) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uses = await ref
          .read(exerciseLibraryRepositoryProvider)
          .usages(exercise.id);
      if (!mounted) return;
      final use =
          uses.where((use) => !use.workout.archived).firstOrNull ??
          uses.firstOrNull;
      final values = exerciseDraftValues(exercise, use?.target);
      setState(() => loading = false);
      final result = await editWorkoutExercise(
        context,
        WorkoutExerciseDraft(values, exerciseId: exercise.id),
      );
      if (mounted && result != null) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load exercise: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Exercise')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search exercises',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (text) =>
                setState(() => query = text.trim().toLowerCase()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Create New Exercise'),
          onTap: loading ? null : create,
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        Expanded(
          child: ref
              .watch(exerciseLibraryProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load exercises: $e')),
                data: (all) {
                  final matches = all
                      .where((e) => e.name.toLowerCase().contains(query))
                      .toList();
                  if (matches.isEmpty) {
                    return const Center(child: Text('No matching exercises.'));
                  }
                  return ListView(
                    children: [
                      for (final exercise in matches)
                        ListTile(
                          key: ValueKey('choose-exercise-${exercise.id}'),
                          title: Text(exercise.name),
                          subtitle: exercise.archived
                              ? const Text('Archived')
                              : null,
                          onTap: loading ? null : () => choose(exercise),
                        ),
                    ],
                  );
                },
              ),
        ),
      ],
    ),
  );
}
