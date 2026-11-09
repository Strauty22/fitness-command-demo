import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/workout_discovery.dart';

class WorkoutLaunchScreen extends ConsumerWidget {
  const WorkoutLaunchScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Choose workout')),
    body: ref
        .watch(workoutChoicesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (choices) => ListView(
            children: [
              for (final w in choices.workouts)
                Card(
                  child: ListTile(
                    key: ValueKey('workout-preview-${w.id}'),
                    title: Text(w.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await ref
                          .read(workoutDiscoveryRepositoryProvider)
                          .selectWorkout(w.id);
                      ref.invalidate(selectedWorkoutProvider);
                      if (context.mounted) context.push('/workout/${w.id}');
                    },
                  ),
                ),
            ],
          ),
        ),
  );
}
