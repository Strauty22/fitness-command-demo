import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workout/data/workout_repository.dart';
import '../strength/compact_prescription.dart';
import 'data/exercise_library_repository.dart';
import 'prescription_editor.dart';

class ExerciseLibraryDetail extends ConsumerWidget {
  final WorkoutRecord exercise;
  const ExerciseLibraryDetail({super.key, required this.exercise});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentExercise =
        ref
            .watch(exerciseLibraryProvider)
            .asData
            ?.value
            .where((item) => item.id == exercise.id)
            .firstOrNull ??
        exercise;
    return Scaffold(
      appBar: AppBar(title: Text(currentExercise.name)),
      body: ref
          .watch(exerciseUsesProvider(exercise.id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load prescriptions: $e')),
            data: (uses) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  currentExercise.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Edit future workout prescriptions. Active sessions and completed history stay unchanged.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Exercise'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) => PrescriptionEditor(
                      exercise: currentExercise,
                      uses: uses,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Workouts containing this exercise',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (uses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'No workout uses this exercise yet. Edit its defaults for future use.',
                    ),
                  ),
                for (final use in uses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(use.label),
                    subtitle: Text(
                      '${use.target['exerciseName']}\n${compactPrescription(use.target, (use.target['sets'] as num? ?? 1).toInt())}${(use.target['notes'] as String? ?? '').isEmpty ? '' : '\n${use.target['notes']}'}',
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}
