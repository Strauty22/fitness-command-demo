import 'compact_prescription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/session_repository.dart';
import 'data/strength_session.dart';
import '../workout/data/workout_repository.dart';

class SessionExerciseSheet extends ConsumerStatefulWidget {
  final StrengthSession session;
  final int index;
  final int? setIndex;
  const SessionExerciseSheet({
    super.key,
    required this.session,
    required this.index,
    this.setIndex,
  });
  @override
  ConsumerState<SessionExerciseSheet> createState() =>
      _SessionExerciseSheetState();
}

class _SessionExerciseSheetState extends ConsumerState<SessionExerciseSheet> {
  final fields = <String, TextEditingController>{};
  late StrengthSession session;
  int selection = -1;
  bool saving = false;
  String? error;
  String mode = 'Manual';
  Map<String, dynamic> get exercise => session.exercises[widget.index];
  Map<String, dynamic> get target =>
      Map<String, dynamic>.from(exercise['target'] as Map);
  @override
  void initState() {
    super.initState();
    session = widget.session;
    selection = widget.setIndex ?? -1;
    reset();
  }

  void reset() {
    final values = selection < 0
        ? target
        : Map<String, dynamic>.from(
            (exercise['actualSets'] as List)[selection] as Map,
          );
    for (final key in [
      'name',
      'sets',
      'reps',
      'load',
      'durationSeconds',
      'distance',
      'notes',
    ]) {
      final value = key == 'name'
          ? exercise['name']
          : key == 'sets'
          ? (exercise['actualSets'] as List).length
          : key == 'notes'
          ? target['notes'] ?? ''
          : values[key] ?? (selection < 0 ? '' : target[key] ?? '');
      (fields[key] ??= TextEditingController()).text = '$value';
    }
    mode = target['progression'] as String? ?? 'Manual';
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> change(Future<StrengthSession> Function() action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      session = await action();
      ref.read(sessionRevisionProvider.notifier).refresh();
      if (mounted) setState(reset);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(String key, String label, {bool numeric = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: fields[key],
      enabled:
          !saving &&
          ((key == 'name' || key == 'notes')
              ? session.unfinished && selection < 0
              : session.unfinished || selection >= 0),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Future<void> save() async {
    final type = target['type'] as String? ?? 'weighted';
    final keys = [
      if (selection < 0) 'sets',
      if (!type.startsWith('timed') && type != 'distance') 'reps',
      'load',
      if (type.startsWith('timed')) 'durationSeconds',
      if (type == 'distance') 'distance',
    ];
    final changes = <String, dynamic>{};
    for (final key in keys) {
      final text = fields[key]!.text.trim();
      final value = num.tryParse(text);
      if (text.isNotEmpty && (value == null || !value.isFinite || value < 0) ||
          key == 'sets' &&
              (value == null || value < 1 || value != value.round()) ||
          key == 'reps' &&
              value != null &&
              (value != value.round() || selection < 0 && value < 1)) {
        setState(() => error = 'Enter valid measurements and whole sets/reps.');
        return;
      }
      changes[key] = value;
    }
    final repo = ref.read(sessionRepositoryProvider);
    await change(
      () => repo.db.transaction(() async {
        if (selection >= 0) {
          return session.unfinished
              ? repo.editSet(session.id, widget.index, selection, changes)
              : repo.editHistorySet(
                  session.id,
                  widget.index,
                  selection,
                  changes,
                );
        }
        await repo.editTargets(session.id, widget.index, changes);
        return repo.editExerciseInfo(
          session.id,
          widget.index,
          name: fields['name']!.text,
          mode: mode,
          notes: fields['notes']!.text,
        );
      }),
    );
    if (mounted && error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final type = target['type'] as String? ?? 'weighted';
    final alternatives = exercise['alternativeChoices'] as List?;
    final sets = exercise['actualSets'] as List;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${exercise['name']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('actual-selection-$selection'),
                initialValue: selection,
                decoration: const InputDecoration(labelText: 'Edit'),
                items: [
                  const DropdownMenuItem(
                    value: -1,
                    child: Text('Exercise targets'),
                  ),
                  for (var i = 0; i < sets.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Actual set ${i + 1}'),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            selection = value;
                            reset();
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              if (selection < 0) field('name', 'Exercise name', numeric: false),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: field(
                      'load',
                      selection < 0
                          ? 'Weight (${displayLoadUnit(target)})'
                          : 'Actual weight (${displayLoadUnit(target)})',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (selection < 0) ...[
                    SizedBox(width: 64, child: field('sets', 'Sets')),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: type.startsWith('timed')
                        ? field(
                            'durationSeconds',
                            selection < 0 ? 'Target seconds' : 'Actual seconds',
                          )
                        : type == 'distance'
                        ? field(
                            'distance',
                            selection < 0
                                ? 'Target distance'
                                : 'Actual distance',
                          )
                        : field(
                            'reps',
                            selection < 0 ? 'Target reps' : 'Actual reps',
                          ),
                  ),
                ],
              ),
              if (selection < 0 && session.unfinished && alternatives != null)
                DropdownButtonFormField<int>(
                  key: ValueKey(
                    'alternative-${widget.index}-${exercise['selectedAlternative']}',
                  ),
                  initialValue: exercise['selectedAlternative'] as int,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Exercise alternative',
                  ),
                  items: [
                    for (var i = 0; i < alternatives.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          'Option ${String.fromCharCode(65 + i)}: ${alternatives[i]['name']}',
                        ),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            change(
                              () => ref
                                  .read(sessionRepositoryProvider)
                                  .switchAlternative(
                                    session.id,
                                    widget.index,
                                    value,
                                  ),
                            );
                          }
                        },
                ),
              if (selection < 0 && session.unfinished)
                DropdownButtonFormField<String>(
                  key: ValueKey('mode-$mode'),
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Progression mode (this session)',
                  ),
                  items: [
                    for (final m in progressionModes)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() => mode = value ?? mode),
                ),
              ExpansionTile(
                title: const Text('Advanced'),
                tilePadding: EdgeInsets.zero,
                children: [
                  field('notes', 'Exercise notes', numeric: false),
                  if (exercise['previous'] != null)
                    Text(
                      'Previous: ${(exercise['previous']['sets'] as List).map((s) => setMeasurementText(Map<String, dynamic>.from(exercise['previous']['target'] as Map), Map<String, dynamic>.from(s as Map))).join('; ')}',
                    ),
                  for (final recorded in session.loggedExercises.where(
                    (e) =>
                        e['entryId'] == exercise['entryId'] &&
                        e['selectedAlternative'] !=
                            exercise['selectedAlternative'],
                  ))
                    Text('Also recorded: ${recorded['name']}'),
                  if (session.unfinished)
                    Wrap(
                      children: [
                        if (exercise['previous'] != null)
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => change(
                                    () => ref
                                        .read(sessionRepositoryProvider)
                                        .usePrevious(session.id, widget.index),
                                  ),
                            child: const Text('Use previous actuals'),
                          ),
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => change(
                                  () => ref
                                      .read(sessionRepositoryProvider)
                                      .skip(
                                        session.id,
                                        widget.index,
                                        exercise['skipped'] != true,
                                      ),
                                ),
                          child: Text(
                            exercise['skipped'] == true
                                ? 'Restore exercise'
                                : 'Skip remaining sets',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (session.unfinished || selection >= 0)
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
