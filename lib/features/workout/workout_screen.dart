import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/workout_repository.dart';
import 'record_editor.dart';
import 'copy_workout.dart';
import 'data/workout_alternatives.dart';

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Workout management')),
    body: ref
        .watch(managementReadyProvider)
        .when(
          data: (_) => const ManagementList(kind: 'program'),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
  );
}

class ManagementList extends ConsumerStatefulWidget {
  final String kind;
  final int? parentId;
  const ManagementList({super.key, required this.kind, this.parentId});
  @override
  ConsumerState<ManagementList> createState() => _ManagementListState();
}

class _ManagementListState extends ConsumerState<ManagementList> {
  bool showArchived = false;
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      ref.read(managementRevisionProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(managementRevisionProvider);
    final repo = ref.watch(workoutRepositoryProvider);
    return Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => editRecord(
                context,
                ref,
                widget.kind,
                parentId: widget.parentId,
              ),
              icon: const Icon(Icons.add),
              label: Text('Create ${widget.kind}'),
            ),
            if (widget.kind == 'program')
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Exercises')),
                      body: const ManagementList(kind: 'exercise'),
                    ),
                  ),
                ),
                child: const Text('Exercise library'),
              ),
            FilterChip(
              label: const Text('Show archived'),
              selected: showArchived,
              onSelected: (v) => setState(() => showArchived = v),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<WorkoutRecord>>(
            future: repo.list(
              widget.kind,
              parentId: widget.parentId,
              includeArchived: showArchived,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final records = snapshot.data!;
              return ReorderableListView.builder(
                itemCount: records.length,
                onReorderItem: (oldIndex, newIndex) => perform(() async {
                  if (showArchived) {
                    throw StateError('Hide archived items before reordering');
                  }
                  final ids = records.map((r) => r.id).toList();
                  ids.insert(newIndex, ids.removeAt(oldIndex));
                  await repo.reorder(widget.kind, widget.parentId, ids);
                }),
                itemBuilder: (context, index) {
                  final r = records[index];
                  return ListTile(
                    key: ValueKey(r.id),
                    title: Text(
                      '#${r.id} ${r.name}${r.archived ? ' (archived)' : ''}',
                    ),
                    subtitle: Text(
                      widget.kind == 'entry'
                          ? '${r.values['warmup'] == true ? 'Warmup · ' : ''}${r.values['optional'] == true ? 'Optional · ' : ''}${r.values['notes'] ?? ''}'
                          : 'Edit settings or open to manage',
                    ),
                    onTap: () {
                      final child = {
                        'program': 'workout',
                        'workout': 'entry',
                      }[widget.kind];
                      if (child == null) {
                        editRecord(context, ref, widget.kind, record: r);
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(r.name),
                              actions: [
                                IconButton(
                                  tooltip: 'Edit settings',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => editRecord(
                                    context,
                                    ref,
                                    widget.kind,
                                    record: r,
                                  ),
                                ),
                              ],
                            ),
                            body: Column(
                              children: [
                                Expanded(
                                  child: ManagementList(
                                    kind: child,
                                    parentId: r.id,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: Wrap(
                        children: [
                          if (widget.kind == 'workout')
                            IconButton(
                              tooltip: 'Copy to program',
                              icon: const Icon(Icons.copy),
                              onPressed: () => copyWorkout(context, ref, r),
                            ),
                          if (widget.kind == 'entry' &&
                              r.values['alternatives'] != null)
                            PopupMenuButton<int>(
                              tooltip: 'Select default alternative',
                              icon: const Icon(Icons.swap_horiz),
                              itemBuilder: (_) => [
                                for (
                                  var i = 0;
                                  i < (r.values['alternatives'] as List).length;
                                  i++
                                )
                                  PopupMenuItem(
                                    value: i,
                                    child: Text(
                                      'Option ${String.fromCharCode(65 + i)}: ${r.values['alternatives'][i]['name']}',
                                    ),
                                  ),
                              ],
                              onSelected: (i) => perform(
                                () => repo.edit(
                                  r.id,
                                  selectWorkoutAlternative(r.values, i),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit),
                            onPressed: () => editRecord(
                              context,
                              ref,
                              widget.kind,
                              record: r,
                            ),
                          ),
                          IconButton(
                            tooltip: r.archived ? 'Restore' : 'Archive',
                            icon: Icon(
                              r.archived
                                  ? Icons.unarchive
                                  : Icons.archive_outlined,
                            ),
                            onPressed: () =>
                                perform(() => repo.archive(r.id, !r.archived)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
