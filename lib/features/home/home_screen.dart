import 'rotation_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../strength/data/workout_discovery.dart';
import '../strength/workout_session_controls.dart';
import '../strength/workout_refresh.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => WorkoutRefresh(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Fitness Command'),
        actions: [
          IconButton(
            tooltip: 'Bike ride',
            onPressed: () => context.push('/cycling'),
            icon: const Icon(Icons.directions_bike),
          ),
        ],
      ),
      bottomNavigationBar: const RotationIndicator(),
      body: ref
          .watch(homeWorkoutsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load workouts: $e')),
            data: (workouts) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  const ResumeWorkoutCard(),
                  for (final workout in workouts)
                    Card(
                      child: ListTile(
                        key: ValueKey('workout-preview-${workout.id}'),
                        title: Text(workout.name),
                        onTap: () async {
                          try {
                            await ref
                                .read(workoutDiscoveryRepositoryProvider)
                                .selectWorkout(workout.id);
                            ref.invalidate(selectedWorkoutProvider);
                            if (context.mounted) {
                              context.push('/workout/${workout.id}');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not select workout: $e'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
    ),
  );
}
