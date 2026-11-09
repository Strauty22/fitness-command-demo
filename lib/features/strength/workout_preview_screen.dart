import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workout/data/workout_repository.dart';
import 'data/strength_session.dart';
import 'data/session_repository.dart';
import 'workout_session_controls.dart';
import 'compact_prescription.dart';
import '../workout/data/custom_workout_repository.dart';
import 'package:go_router/go_router.dart';

class WorkoutPreview {
  final WorkoutRecord workout;
  final List<List<Map<String, dynamic>>> exercises;
  const WorkoutPreview(this.workout, this.exercises);
}

final workoutPreviewProvider = FutureProvider.autoDispose
    .family<WorkoutPreview, int>((ref, id) async {
      ref.watch(managementRevisionProvider);
      ref.watch(sessionRevisionProvider);
      await ref.watch(managementReadyProvider.future);
      final repo = ref.watch(workoutRepositoryProvider);
      final workout = await repo.get(id);
      if (workout.kind != 'workout' ||
          workout.archived ||
          (await repo.get(workout.parentId!)).archived) {
        throw StateError('This workout is unavailable');
      }
      final sessions = ref.watch(sessionRepositoryProvider);
      Future<Map<String, dynamic>> resolve(
        WorkoutRecord entry, {
        int? alternative,
      }) async {
        final target = await repo.resolvedEntry(
          entry,
          alternative: alternative,
        );
        return workingTarget(
          target,
          await sessions.previous(target['exerciseId'] as int),
        );
      }

      final exercises = <List<Map<String, dynamic>>>[];
      for (final entry in await repo.list('entry', parentId: id)) {
        final options = entry.values['alternatives'] as List?;
        final selected = entry.values['selectedAlternative'] as int? ?? 0;
        exercises.add([
          if (options == null)
            await resolve(entry)
          else
            for (var i = 0; i < options.length; i++)
              {
                ...await resolve(entry, alternative: i),
                'previewDefault': i == selected,
              },
        ]);
      }
      return WorkoutPreview(workout, exercises);
    });

class WorkoutPreviewScreen extends ConsumerWidget {
  final int workoutId;
  const WorkoutPreviewScreen({super.key, required this.workoutId});
  Future<void> delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text(
          'Remove this custom workout from your list? Shared exercises, active sessions and completed history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Workout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(customWorkoutRepositoryProvider).delete(workoutId);
      ref.read(managementRevisionProvider.notifier).refresh();
      if (context.mounted) context.go('/');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete workout: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workoutPreviewProvider(workoutId));
    final custom = state.asData?.value.workout.values[customWorkoutKey] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Preview'),
        actions: [
          if (custom)
            PopupMenuButton<String>(
              tooltip: 'Manage workout',
              onSelected: (action) {
                if (action == 'edit') {
                  context.push('/custom-workouts/$workoutId/edit');
                }
                if (action == 'delete') delete(context, ref);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit Workout')),
                PopupMenuItem(value: 'delete', child: Text('Delete Workout')),
              ],
            ),
        ],
      ),
      body: ref
          .watch(workoutPreviewProvider(workoutId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load workout: $e')),
            data: (preview) => Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        preview.workout.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if ((preview.workout.values['notes'] as String? ?? '')
                          .isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            preview.workout.values['notes'] as String,
                          ),
                        ),
                      if (preview.exercises.isEmpty)
                        const Text(
                          'Add exercises in Programs before starting.',
                        ),
                      for (final options in preview.exercises)
                        Builder(
                          builder: (context) {
                            final selected =
                                options
                                    .where((o) => o['previewDefault'] == true)
                                    .firstOrNull ??
                                options.first;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${selected['exerciseName']}'),
                              subtitle: Text(
                                compactPrescription(
                                  selected,
                                  (selected['sets'] as num? ?? 1).toInt(),
                                ),
                              ),
                              trailing: const Icon(Icons.more_horiz),
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                useSafeArea: true,
                                showDragHandle: true,
                                builder: (context) => ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: [
                                    for (
                                      var i = 0;
                                      i < options.length;
                                      i++
                                    ) ...[
                                      Text(
                                        '${options.length > 1 ? 'Option ${String.fromCharCode(65 + i)}: ' : ''}${options[i]['exerciseName']}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(measurementText(options[i])),
                                      if ((options[i]['notes'] as String? ?? '')
                                          .isNotEmpty)
                                        ExpansionTile(
                                          title: const Text('Advanced'),
                                          children: [
                                            Text(options[i]['notes'] as String),
                                          ],
                                        ),
                                      const SizedBox(height: 12),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StartWorkoutButton(
                      workoutId: workoutId,
                      enabled: preview.exercises.isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
