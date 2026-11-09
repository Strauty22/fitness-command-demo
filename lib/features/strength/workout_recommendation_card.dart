import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/workout_discovery.dart';
import 'workout_session_controls.dart';

String recommendationDateLabel(
  BuildContext context,
  WorkoutRecommendation recommendation,
  DateTime now,
) {
  final date = MaterialLocalizations.of(
    context,
  ).formatFullDate(recommendation.date);
  return '${recommendation.isToday(now) ? "Today's Workout" : 'Up Next'} · $date';
}

class WorkoutRecommendationCard extends StatelessWidget {
  final WorkoutRecommendation recommendation;
  final DateTime now;
  const WorkoutRecommendationCard({
    super.key,
    required this.recommendation,
    required this.now,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(recommendationDateLabel(context, recommendation, now)),
          Text(
            recommendation.workout.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(recommendation.program.name),
          const SizedBox(height: 16),
          StartWorkoutButton(workoutId: recommendation.workout.id),
          TextButton(
            onPressed: () =>
                context.push('/workout/${recommendation.workout.id}'),
            child: const Text('View Exercises'),
          ),
        ],
      ),
    ),
  );
}
