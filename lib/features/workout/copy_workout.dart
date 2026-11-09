import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/workout_repository.dart';

Future<void> copyWorkout(
  BuildContext context,
  WidgetRef ref,
  WorkoutRecord workout,
) async {
  final repo = ref.read(workoutRepositoryProvider);
  final programs = await repo.list('program');
  if (!context.mounted) return;
  final destination = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Copy workout to program'),
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Creates an editable copy. Schedule rules stay unchanged.',
          ),
        ),
        for (final program in programs)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, program.id),
            child: Text(program.name),
          ),
      ],
    ),
  );
  if (destination == null) return;
  try {
    await repo.copyWorkoutToProgram(workout.id, destination);
    ref.read(managementRevisionProvider.notifier).refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Workout copied. Select it from Home whenever you are ready.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not copy: $e')));
    }
  }
}
