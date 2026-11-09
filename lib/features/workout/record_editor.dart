import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/workout_repository.dart';

Future<void> editRecord(
  BuildContext context,
  WidgetRef ref,
  String kind, {
  WorkoutRecord? record,
  int? parentId,
}) async {
  final repo = ref.read(workoutRepositoryProvider);
  final exercises = kind == 'entry'
      ? await repo.list('exercise', includeArchived: true)
      : <WorkoutRecord>[];
  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => RecordEditor(
      kind: kind,
      record: record,
      parentId: parentId,
      repo: repo,
      exercises: exercises,
    ),
  );
  if (saved == true) ref.read(managementRevisionProvider.notifier).refresh();
}

class RecordEditor extends StatefulWidget {
  final String kind;
  final WorkoutRecord? record;
  final int? parentId;
  final WorkoutRepository repo;
  final List<WorkoutRecord> exercises;
  const RecordEditor({
    super.key,
    required this.kind,
    this.record,
    this.parentId,
    required this.repo,
    required this.exercises,
  });
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final fields = <String, TextEditingController>{};
  late Map<String, dynamic> values;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    values = {...?widget.record?.values};
    if (widget.record == null) {
      if (widget.kind == 'program') {
        values.addAll({
          'sets': 2,
          'reps': 10,
          'cycle': ['Week A', 'Week B'],
          'anchor': DateUtils.dateOnly(
            DateTime.now(),
          ).toIso8601String().substring(0, 10),
          'restSeconds': 90,
        });
      }
      if (widget.kind == 'exercise') {
        values.addAll({'type': 'weighted', 'progression': 'Manual'});
      }
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool numeric = false,
    String? initial,
  }) {
    final controller = fields.putIfAbsent(
      key,
      () => TextEditingController(text: initial ?? '${values[key] ?? ''}'),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
      ),
    );
  }

  Widget choice(String key, String label, List<String> choices) =>
      DropdownButtonFormField<String>(
        initialValue: values[key] as String?,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('Inherit')),
          ...choices.map((v) => DropdownMenuItem(value: v, child: Text(v))),
        ],
        onChanged: (v) => setState(() {
          if (v == null) {
            values.remove(key);
          } else {
            values[key] = v;
          }
        }),
      );

  Widget programSetup() => ExpansionTile(
    title: const Text('Program defaults'),
    children: [
      field('sets', 'Sets', numeric: true),
      field('reps', 'Reps', numeric: true),
      field('restSeconds', 'Rest seconds', numeric: true),
    ],
  );

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = {...values};
      for (final item in fields.entries) {
        final text = item.value.text.trim();
        if (item.key == 'cycle') {
          next['cycle'] = text.split(',').map((s) => s.trim()).toList();
        } else if ([
          'sets',
          'reps',
          'repsMax',
          'restSeconds',
          'load',
          'durationSeconds',
          'durationMaxSeconds',
          'distance',
          'increment',
          'successCount',
          'failureCount',
          'allowedFailedSets',
          'deloadPercent',
          'weekOverride',
          'weekday',
          'week',
          'workoutId',
        ].contains(item.key)) {
          if (text.isEmpty) {
            next.remove(item.key);
          } else {
            next[item.key] = num.parse(text);
          }
        } else {
          next[item.key] = text;
        }
      }
      if (widget.kind == 'entry') {
        if (next['exerciseId'] == null) {
          throw ArgumentError('Choose an exercise from the library');
        }
        next['name'] = widget.exercises
            .firstWhere((e) => e.id == next['exerciseId'])
            .name;
        if (next['exerciseId'] != widget.record?.values['exerciseId']) {
          next.remove('displayName');
        }
      }
      if (next['weekOverride'] != null) {
        final n = next['weekOverride'] as num;
        if (n != n.round() || n < 0 || n >= (next['cycle'] as List).length) {
          throw ArgumentError(
            'Week override must be a rotation index (0, 1, …)',
          );
        }
        next['weekOverride'] = n.toInt();
      }
      if (widget.record == null) {
        await widget.repo.create(widget.kind, next, parentId: widget.parentId);
      } else {
        await widget.repo.edit(widget.record!.id, next);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final targets = ['program', 'exercise', 'entry'].contains(kind);
    return AlertDialog(
      title: Text('${widget.record == null ? 'Create' : 'Edit'} $kind'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind != 'entry') field('name', 'Name'),
              if (kind == 'schedule') ...[
                field('weekday', 'Day: Monday=1 … Sunday=7', numeric: true),
                field(
                  'week',
                  'Rotation week index (0, 1, …); blank = every week',
                  numeric: true,
                ),
                field('workoutId', 'Workout ID (optional)', numeric: true),
              ],
              if (kind == 'program') programSetup(),
              if (kind == 'entry')
                DropdownButtonFormField<int>(
                  initialValue: values['exerciseId'] as int?,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Exercise identity',
                  ),
                  items: widget.exercises
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            '${e.name}${e.archived ? ' (archived)' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => values['exerciseId'] = v),
                ),
              if (kind == 'exercise' || kind == 'entry')
                choice('type', 'Measurement type', exerciseTypes),
              if (targets && kind != 'program') ...[
                const Text(
                  'Blank targets inherit defaults. Targets remain editable in every progression mode.',
                ),
                field('sets', 'Sets', numeric: true),
                field('reps', 'Reps', numeric: true),
                if (kind == 'entry')
                  field(
                    'repsMax',
                    'Maximum reps (optional range)',
                    numeric: true,
                  ),
                field('restSeconds', 'Rest seconds', numeric: true),
              ],
              if (kind == 'exercise' || kind == 'entry') ...[
                field('load', 'External load', numeric: true),
                field('loadUnit', 'Load unit (leave unknown if unconfirmed)'),
                field('durationSeconds', 'Duration seconds', numeric: true),
                if (kind == 'entry')
                  field(
                    'durationMaxSeconds',
                    'Maximum duration seconds (optional range)',
                    numeric: true,
                  ),
                field('distance', 'Distance', numeric: true),
                field('distanceUnit', 'Distance unit'),
                choice('progression', 'Progression mode', progressionModes),
                field('increment', 'Progress increment', numeric: true),
                field(
                  'successCount',
                  'Successes before increase',
                  numeric: true,
                ),
                field(
                  'allowedFailedSets',
                  'Allowed failed sets (default 0)',
                  numeric: true,
                ),
                field(
                  'failureCount',
                  'Consecutive failures before deload (0 disables)',
                  numeric: true,
                ),
                field('deloadPercent', 'Deload percent', numeric: true),
              ],
              if (kind == 'entry') ...[
                field('category', 'Category'),
                for (final key in ['optional', 'warmup', 'repsUnknown'])
                  SwitchListTile(
                    title: Text(
                      key == 'repsUnknown'
                          ? 'Quality sets / reps unknown'
                          : key,
                    ),
                    value: values[key] == true,
                    onChanged: (v) => setState(() => values[key] = v),
                  ),
              ],
              if (kind != 'program') field('notes', 'Notes'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
