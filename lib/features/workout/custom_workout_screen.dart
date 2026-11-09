import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../strength/compact_prescription.dart';
import 'data/workout_repository.dart';
import 'data/custom_workout_repository.dart';
import 'workout_exercise_picker.dart';

class CustomWorkoutScreen extends ConsumerStatefulWidget {
  final int? workoutId;
  const CustomWorkoutScreen({super.key, this.workoutId});
  @override
  ConsumerState<CustomWorkoutScreen> createState() =>
      _CustomWorkoutScreenState();
}

class _CustomWorkoutScreenState extends ConsumerState<CustomWorkoutScreen> {
  final name = TextEditingController();
  final notes = TextEditingController();
  final exercises = <WorkoutExerciseDraft>[];
  bool loading = false, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.workoutId != null) load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = ref.read(customWorkoutRepositoryProvider);
      final entries = await repo.entries(widget.workoutId!);
      final workout = await repo.workouts.get(widget.workoutId!);
      if (!mounted) return;
      name.text = workout.name;
      notes.text = workout.values['notes'] as String? ?? '';
      setState(() {
        exercises.clear();
        exercises.addAll(entries);
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load workout: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> add() async {
    try {
      await addExercise();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not add exercise: $e');
    }
  }

  Future<void> addExercise() async {
    final result = await Navigator.push<WorkoutExerciseDraft>(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutExercisePicker()),
    );
    if (!mounted || result == null) return;
    if (result.exerciseId == null &&
        exercises.any(
          (e) =>
              e.exerciseId == null &&
              normalizedExerciseName(e.values['name'] as String) ==
                  normalizedExerciseName(result.values['name'] as String),
        )) {
      setState(
        () => error =
            'That new exercise is already in this draft. Edit it in the list.',
      );
      return;
    }
    if (mounted) {
      setState(() {
        exercises.add(result);
        error = null;
      });
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(customWorkoutRepositoryProvider)
          .save(
            workoutId: widget.workoutId,
            name: name.text,
            notes: notes.text,
            exercises: exercises,
          );
      ref.read(managementRevisionProvider.notifier).refresh();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save workout: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void move(int from, int to) =>
      setState(() => exercises.insert(to, exercises.removeAt(from)));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.workoutId == null ? 'Create Workout' : 'Edit Workout',
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: saving,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Workout Name (required)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Workout notes (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < exercises.length; i++)
                    Card(
                      key: ValueKey('draft-exercise-$i'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercises[i].name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              compactPrescription(
                                exercises[i].values,
                                (exercises[i].values['sets'] as num? ?? 2)
                                    .toInt(),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      var updated = await editWorkoutExercise(
                                        context,
                                        exercises[i],
                                      );
                                      if (!mounted || !context.mounted) return;
                                      if (updated != null &&
                                          updated.exerciseId == null) {
                                        updated = await resolveNewExercise(
                                          context,
                                          ref,
                                          updated,
                                        );
                                      }
                                      if (mounted && updated != null) {
                                        setState(() => exercises[i] = updated!);
                                      }
                                    },
                                    child: const Text(
                                      'Edit Exercise',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move up',
                                  onPressed: i == 0
                                      ? null
                                      : () => move(i, i - 1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip: 'Move down',
                                  onPressed: i == exercises.length - 1
                                      ? null
                                      : () => move(i, i + 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                IconButton(
                                  tooltip: 'Remove exercise',
                                  onPressed: () =>
                                      setState(() => exercises.removeAt(i)),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Exercise'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: save,
                    child: Text(saving ? 'Saving...' : 'Save Workout'),
                  ),
                ],
              ),
            ),
    ),
  );
}
