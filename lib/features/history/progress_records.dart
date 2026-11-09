import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'history_data.dart';
import 'personal_bests.dart';
import 'workout_history_card.dart';
import 'workout_summary.dart';

class ProgressRecords extends ConsumerWidget {
  const ProgressRecords({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(combinedHistoryProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Could not load progress: $e'),
        data: (entries) {
          final rides = entries
              .where((e) => e.ride != null)
              .map((e) => e.ride!)
              .toList();
          final sessions = entries
              .where((e) => e.session != null)
              .map((e) => e.session!)
              .toList();
          final rideRecords = personalBestRides(rides);
          final exerciseRecords = exerciseBests(sessions);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lifetime Totals',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                '${rides.length}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const Text(
                                'Total Rides',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                '${sessions.length}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const Text(
                                'Total Strength Workouts',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Personal Best Rides',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (rideRecords.isEmpty) const Text('No saved rides yet.'),
              for (final ride in rideRecords)
                RideHistoryCard(
                  ride: ride,
                  onTap: () => context.push('/rides/${ride.id}'),
                ),
              const SizedBox(height: 16),
              Text(
                'Personal Best Exercises',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (exerciseRecords.isEmpty)
                const Text('No completed weight records yet.'),
              for (final best in exerciseRecords)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(best.name),
                  subtitle: Text(historyDate(best.date)),
                  trailing: Text(
                    '${summaryNumber(double.parse(best.pounds.toStringAsFixed(2)))} lb',
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Exercise Performance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          );
        },
      );
}
