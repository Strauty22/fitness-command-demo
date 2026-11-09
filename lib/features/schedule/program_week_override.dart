import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workout/data/workout_repository.dart';

/// Overrides the active week without moving the calendar anchor.
class ProgramWeekOverride extends ConsumerStatefulWidget {
  final WorkoutRecord program;
  const ProgramWeekOverride({super.key, required this.program});

  @override
  ConsumerState<ProgramWeekOverride> createState() =>
      _ProgramWeekOverrideState();
}

class _ProgramWeekOverrideState extends ConsumerState<ProgramWeekOverride> {
  bool saving = false;

  Future<void> select(int? week) async {
    if (week == null || saving) return;
    setState(() => saving = true);
    try {
      final repo = ref.read(workoutRepositoryProvider);
      final latest = await repo.get(widget.program.id);
      final values = {...latest.values};
      if (week == -1) {
        values.remove('weekOverride');
      } else {
        values['weekOverride'] = week;
      }
      await repo.edit(latest.id, values);
      ref.read(managementRevisionProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final cycle = (p.values['cycle'] as List).cast<String>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DropdownButtonFormField<int>(
        key: ValueKey('${p.id}:${p.values['weekOverride']}'),
        initialValue: p.values['weekOverride'] as int? ?? -1,
        decoration: const InputDecoration(
          labelText: 'Active week',
          helperText:
              'Overrides stay active until Automatic is selected. The start date stays unchanged.',
          helperMaxLines: 3,
        ),
        items: [
          const DropdownMenuItem(
            value: -1,
            child: Text('Automatic (calendar)'),
          ),
          for (var i = 0; i < cycle.length; i++)
            DropdownMenuItem(value: i, child: Text(cycle[i])),
        ],
        onChanged: saving ? null : select,
      ),
    );
  }
}
