import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/session_repository.dart';
import 'data/workout_discovery.dart';
import 'data/strength_session.dart';

final workoutActionProvider = NotifierProvider<WorkoutAction, bool>(
  WorkoutAction.new,
);

class WorkoutAction extends Notifier<bool> {
  @override
  bool build() => false;
  bool begin() {
    if (state) return false;
    state = true;
    return true;
  }

  void end() => state = false;
}

void _error(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not update workout: $error')));
  }
}

Future<void> _openSession(
  BuildContext context,
  WidgetRef ref,
  StrengthSession session,
) async {
  final repo = ref.read(sessionRepositoryProvider);
  final revision = ref.read(sessionRevisionProvider.notifier);
  if (session.status == 'paused') {
    await repo.resume(session.id);
    revision.refresh();
  }
  if (context.mounted) context.push('/session/${session.id}');
}

/// Only an explicit button calls this write path. Lists and previews are read-only.
Future<void> startWorkout(
  BuildContext context,
  WidgetRef ref,
  int workoutId,
) async {
  final action = ref.read(workoutActionProvider.notifier);
  if (!action.begin()) return;
  final revision = ref.read(sessionRevisionProvider.notifier);
  try {
    await ref.read(workoutDiscoveryRepositoryProvider).selectWorkout(workoutId);
    ref.invalidate(selectedWorkoutProvider);
    final repo = ref.read(sessionRepositoryProvider);
    final existing = await repo.unfinished();
    if (!context.mounted) return;
    if (existing != null) {
      if (existing.data['workoutId'] == workoutId) {
        await _openSession(context, ref, existing);
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Another workout is in progress'),
          content: Text(
            '${existing.name} has ${existing.completedSets} recorded sets. Resume it, or discard it before starting this workout. Discarded sessions remain in history as cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep current workout'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'resume'),
              child: const Text('Resume Workout'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard and Start'),
            ),
          ],
        ),
      );
      if (!context.mounted || choice == null) return;
      if (choice == 'resume') {
        await _openSession(context, ref, existing);
        return;
      }
      final session = await repo.replaceUnfinished(workoutId, existing.id);
      revision.refresh();
      if (context.mounted) context.push('/session/${session.id}');
      return;
    }
    final session = await repo.start(workoutId);
    revision.refresh();
    if (context.mounted) context.push('/session/${session.id}');
  } catch (e) {
    if (context.mounted) {
      _error(context, e);
    }
  } finally {
    action.end();
  }
}

class StartWorkoutButton extends ConsumerWidget {
  final int workoutId;
  final bool enabled;
  const StartWorkoutButton({
    super.key,
    required this.workoutId,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => FilledButton.icon(
    onPressed: !enabled || ref.watch(workoutActionProvider)
        ? null
        : () => startWorkout(context, ref, workoutId),
    icon: const Icon(Icons.play_arrow),
    label: const Text('Start Workout'),
  );
}

class ResumeWorkoutCard extends ConsumerWidget {
  const ResumeWorkoutCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(workoutActionProvider);
    return ref
        .watch(unfinishedSessionProvider)
        .when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text('Could not load saved workout: $e'),
          data: (session) {
            if (session == null) return const SizedBox.shrink();
            final repo = ref.read(sessionRepositoryProvider);
            final revision = ref.read(sessionRevisionProvider.notifier);
            final started = session.startedAt.toLocal();
            final local = MaterialLocalizations.of(context);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workout in progress',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(session.name),
                    Text(
                      'Started ${local.formatMediumDate(started)} at ${local.formatTimeOfDay(TimeOfDay.fromDateTime(started))}',
                    ),
                    Text(
                      session.completedSets == 0
                          ? 'No sets recorded'
                          : '${session.completedSets} sets recorded',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final action = ref.read(
                                    workoutActionProvider.notifier,
                                  );
                                  if (!action.begin()) return;
                                  try {
                                    await _openSession(context, ref, session);
                                  } catch (e) {
                                    if (context.mounted) {
                                      _error(context, e);
                                    }
                                  } finally {
                                    action.end();
                                  }
                                },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume Workout'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final action = ref.read(
                                    workoutActionProvider.notifier,
                                  );
                                  if (!action.begin()) return;
                                  try {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Discard workout?'),
                                        content: Text(
                                          'Discard ${session.name}? It will be marked cancelled, keeping recorded sets in history.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Keep workout'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text(
                                              'Discard Workout',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await repo.finish(
                                        session.id,
                                        cancel: true,
                                      );
                                      revision.refresh();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      _error(context, e);
                                    }
                                  } finally {
                                    action.end();
                                  }
                                },
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}
