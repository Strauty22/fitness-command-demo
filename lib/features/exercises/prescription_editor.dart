import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workout/data/workout_repository.dart';
import 'data/exercise_library_repository.dart';

class PrescriptionEditor extends ConsumerStatefulWidget {
  final WorkoutRecord exercise;
  final List<ExerciseUse> uses;
  final ValueChanged<Map<String, dynamic>>? onSaveDraft;
  final bool newExercise;
  const PrescriptionEditor({
    super.key,
    required this.exercise,
    required this.uses,
    this.onSaveDraft,
    this.newExercise = false,
  });
  @override
  ConsumerState<PrescriptionEditor> createState() => _PrescriptionEditorState();
}

class _PrescriptionEditorState extends ConsumerState<PrescriptionEditor> {
  final fields = <String, TextEditingController>{};
  final original = <String, String>{};
  int selected = 0;
  bool saving = false;
  String? error;
  late String originalName;
  late String name;
  late String draftType;
  bool get drafting => widget.onSaveDraft != null;
  Map<String, dynamic> get target => widget.uses.isEmpty
      ? widget.exercise.values
      : widget.uses[selected].target;
  @override
  void initState() {
    super.initState();
    reset();
  }

  void reset() {
    originalName = target['exerciseName'] as String? ?? widget.exercise.name;
    if (drafting) {
      originalName = target['displayName'] as String? ?? originalName;
    }
    name = originalName;
    draftType = target['type'] as String? ?? 'weighted';
    for (final key in [
      'load',
      'loadUnit',
      'sets',
      'reps',
      'durationSeconds',
      'distance',
      'distanceUnit',
      'notes',
      if (drafting) 'restSeconds',
    ]) {
      original[key] = '${target[key] ?? ''}';
      (fields[key] ??= TextEditingController()).text = original[key]!;
    }
  }

  Future<void> rename() async {
    var draft = name;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Rename exercise'),
          content: TextFormField(
            initialValue: draft,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Exercise name'),
            onChanged: (value) => updateDialog(() => draft = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: draft.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, draft.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) setState(() => name = result);
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget field(String key, String label, {bool numeric = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: fields[key],
      enabled: !saving,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
    ),
  );
  Future<void> save(bool all) async {
    if (saving) return;
    final patch = <String, dynamic>{};
    if (name != originalName) patch['name'] = name;
    if (drafting && draftType != target['type']) patch['type'] = draftType;
    for (final key in fields.keys) {
      final text = fields[key]!.text.trim();
      if (text == original[key]!.trim()) continue;
      if (['loadUnit', 'distanceUnit', 'notes'].contains(key)) {
        patch[key] = text.isEmpty ? null : text;
        continue;
      }
      final value = num.tryParse(text);
      if (text.isNotEmpty && (value == null || !value.isFinite || value < 0) ||
          ['sets', 'reps'].contains(key) &&
              value != null &&
              (value < 1 || value != value.round())) {
        setState(
          () => error =
              'Enter non-negative measurements and whole positive sets/reps.',
        );
        return;
      }
      final baseline = num.tryParse(original[key]!);
      if (value != baseline) patch[key] = value;
    }
    if (drafting) {
      final next = {...target, ...patch};
      if (patch.containsKey('name')) next['displayName'] = name;
      if (patch.containsKey('reps')) {
        next.remove('repsMax');
        next['repsUnknown'] = false;
      }
      if (patch.containsKey('durationSeconds')) {
        next.remove('durationMaxSeconds');
      }
      if (draftType != target['type'] || widget.newExercise) {
        if (draftType.startsWith('timed') || draftType == 'distance') {
          next.remove('reps');
          next.remove('repsMax');
          next.remove('repsUnknown');
        }
        if (!draftType.startsWith('timed')) {
          next.remove('durationSeconds');
          next.remove('durationMaxSeconds');
        }
        if (draftType != 'distance') {
          next.remove('distance');
          next.remove('distanceUnit');
        }
      }
      try {
        ref.read(workoutRepositoryProvider).validate('exercise', next);
        widget.onSaveDraft!(next);
        Navigator.pop(context);
      } catch (e) {
        setState(() => error = '$e');
      }
      return;
    }
    if (patch.isEmpty) {
      setState(() => error = 'Change the name or at least one exercise field.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(exerciseLibraryRepositoryProvider)
          .update(
            widget.exercise.id,
            patch,
            workoutId: all ? null : widget.uses[selected].workout.id,
          );
      ref.read(managementRevisionProvider.notifier).refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = drafting ? draftType : target['type'] as String? ?? 'weighted';
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
              if (widget.newExercise)
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(labelText: 'Exercise name'),
                  onChanged: (value) => name = value.trim(),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rename exercise',
                      onPressed: saving ? null : rename,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (drafting) ...[
                DropdownButtonFormField<String>(
                  initialValue: draftType,
                  decoration: const InputDecoration(
                    labelText: 'Measurement type',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'weighted',
                      child: Text('Weight and reps'),
                    ),
                    DropdownMenuItem(
                      value: 'bodyweight',
                      child: Text('Bodyweight'),
                    ),
                    DropdownMenuItem(
                      value: 'timedHold',
                      child: Text('Timed hold'),
                    ),
                    DropdownMenuItem(
                      value: 'timedActivity',
                      child: Text('Timed activity'),
                    ),
                    DropdownMenuItem(
                      value: 'distance',
                      child: Text('Distance'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => draftType = value);
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (widget.uses.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Choose workout',
                  ),
                  items: [
                    for (var i = 0; i < widget.uses.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          widget.uses[i].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (index) {
                          if (index != null) {
                            setState(() {
                              selected = index;
                              reset();
                            });
                          }
                        },
                ),
              const SizedBox(height: 12),
              field('load', 'Weight / external load'),
              field('loadUnit', 'Weight unit', numeric: false),
              Row(
                children: [
                  Expanded(child: field('sets', 'Sets')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: type.startsWith('timed')
                        ? field('durationSeconds', 'Duration (seconds)')
                        : type == 'distance'
                        ? field('distance', 'Distance')
                        : field('reps', 'Reps'),
                  ),
                ],
              ),
              if (type == 'distance')
                field('distanceUnit', 'Distance unit', numeric: false),
              if (drafting)
                field('restSeconds', 'Rest duration (seconds, optional)'),
              ExpansionTile(
                title: const Text('Resistance and notes'),
                tilePadding: EdgeInsets.zero,
                children: [
                  field('notes', 'Resistance / notes', numeric: false),
                ],
              ),
              Text(
                drafting
                    ? 'These settings apply only to this workout. Save Workout to keep your changes.'
                    : 'Choose a scope below to save the name and changed fields. Active sessions and history stay unchanged.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (!drafting && widget.uses.isNotEmpty)
                FilledButton(
                  onPressed: saving ? null : () => save(false),
                  child: const Text('Change This Workout Only'),
                ),
              if (drafting) ...[
                FilledButton(
                  onPressed: () => save(false),
                  child: const Text('Save Exercise'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ] else
                OutlinedButton(
                  onPressed: saving ? null : () => save(true),
                  child: const Text('Change All Workouts'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
