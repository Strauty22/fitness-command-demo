import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/session_repository.dart';
import 'data/strength_session.dart';
import 'compact_prescription.dart';
import 'session_exercise_sheet.dart';
import '../history/personal_bests.dart';

class SessionExerciseCard extends ConsumerWidget {
  final StrengthSession session;
  final int index;
  final bool saving;
  final Future<void> Function(Future<StrengthSession> Function()) operate;
  const SessionExerciseCard({
    super.key,
    required this.session,
    required this.index,
    required this.saving,
    required this.operate,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = session.exercises[index];
    final target = Map<String, dynamic>.from(exercise['target'] as Map);
    final history = ref.watch(sessionHistoryProvider);
    final isBest =
        history.hasValue &&
        newExerciseRecords(
          session,
          history.value!,
        ).contains(exerciseRecordKey(exercise));
    final sets = exercise['actualSets'] as List;
    final canLog =
        session.status == 'active' && !saving && exercise['skipped'] != true;
    void details([int? setIndex]) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SessionExerciseSheet(
        session: session,
        index: index,
        setIndex: setIndex,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('exercise-details-$index'),
            onTap: saving ? null : () => details(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${exercise['name']}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isBest)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        'PB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text(
                      compactPrescription(target, sets.length),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (var i = 0; i < sets.length; i++)
                Semantics(
                  label:
                      '${exercise['name']}, set ${i + 1}, ${sets[i]['completed'] == true ? "completed" : "incomplete"}',
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: GestureDetector(
                      onLongPress: saving ? null : () => details(i),
                      child: FilledButton(
                        key: ValueKey('complete-$index-$i'),
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: sets[i]['completed'] == true
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xff343a36),
                          foregroundColor: sets[i]['completed'] == true
                              ? Colors.black
                              : Colors.white,
                          disabledBackgroundColor: sets[i]['completed'] == true
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xff343a36),
                          disabledForegroundColor: Colors.white,
                        ),
                        onPressed: !canLog
                            ? null
                            : () => operate(
                                () => ref
                                    .read(sessionRepositoryProvider)
                                    .tapSet(session.id, index, i),
                              ),
                        child: Text(
                          '${target['type'].toString().startsWith('timed')
                              ? "${target['durationSeconds'] ?? '?'}s"
                              : target['type'] == 'distance'
                              ? target['distance'] ?? '?'
                              : sets[i]['completed'] == true
                              ? sets[i]['reps'] ?? target['reps'] ?? '?'
                              : target['reps'] ?? '?'}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (exercise['skipped'] == true)
            const Text('Skipped', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
