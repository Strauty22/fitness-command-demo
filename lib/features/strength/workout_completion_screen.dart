import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../history/history_data.dart';
import '../history/workout_history_card.dart';
import '../history/workout_summary.dart';
import '../history/personal_bests.dart';
import 'data/session_repository.dart';

class WorkoutCompletionScreen extends ConsumerWidget {
  final int sessionId;
  const WorkoutCompletionScreen({super.key, required this.sessionId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider(sessionId));
    final history = ref.watch(sessionHistoryProvider);
    final count = ref.watch(completedWorkoutCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout complete'),
        automaticallyImplyLeading: false,
      ),
      body: sessionState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load saved workout: $e')),
        data: (session) => session.status != 'completed'
            ? const Center(child: Text('This workout has not been completed.'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 16),
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  count.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Column(
                      children: [
                        Text('Could not load workout count: $e'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(completedWorkoutCountProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                    data: (number) => Text(
                      'Workout $number done!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fantastic!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stat(
                        context,
                        summaryDuration(strengthDuration(session)),
                        'Duration',
                      ),
                      _stat(
                        context,
                        '${groupedNumber(liftingVolumePounds(session).round())} lb',
                        'Volume',
                      ),
                      history.when(
                        loading: () => _stat(context, '?', 'Records'),
                        error: (e, _) =>
                            _stat(context, 'Unavailable', 'Records'),
                        data: (sessions) => _stat(
                          context,
                          '${newExerciseRecords(session, sessions).length}',
                          'Records',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  StrengthHistoryCard(session: session, indicators: true),
                ],
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('DONE'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(label),
      ],
    ),
  );
}
