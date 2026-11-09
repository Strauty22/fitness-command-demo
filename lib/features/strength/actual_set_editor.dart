import 'package:flutter/material.dart';
import 'data/strength_session.dart';

/// Every valid numeric change is sent immediately, including clearing a field.
/// The write queue is awaited before dismissing, so the final keystroke is saved.
class ActualSetEditor extends StatefulWidget {
  final Map<String, dynamic> target;
  final Map<String, dynamic> actual;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const ActualSetEditor({
    super.key,
    required this.target,
    required this.actual,
    required this.onSave,
  });
  @override
  State<ActualSetEditor> createState() => _ActualSetEditorState();
}

class _ActualSetEditorState extends State<ActualSetEditor> {
  final controllers = <String, TextEditingController>{};
  final errors = <String, String>{};
  Future<void> pending = Future.value();
  int writes = 0;
  String? failure;
  late final Map<String, String> labels;
  @override
  void initState() {
    super.initState();
    final type = widget.target['type'] as String? ?? 'weighted';
    labels = {
      if (!type.startsWith('timed') && type != 'distance')
        'reps': 'Actual reps',
      if (type.startsWith('timed') ||
          type == 'weighted' ||
          type == 'bodyweight' ||
          widget.target['load'] != null)
        'load':
            'Actual load (${unitLabel(widget.target['loadUnit'], 'unit unconfirmed')})',
      if (type.startsWith('timed')) 'durationSeconds': 'Actual seconds',
      if (type == 'distance')
        'distance':
            'Actual distance (${unitLabel(widget.target['distanceUnit'], 'units unconfirmed')})',
    };
    for (final key in labels.keys) {
      final value = widget.actual.containsKey(key)
          ? widget.actual[key]
          : widget.target[key];
      controllers[key] = TextEditingController(text: '${value ?? ''}');
    }
  }

  void changed(String key, String text) {
    final value = text.trim().isEmpty ? null : num.tryParse(text);
    if (text.trim().isNotEmpty &&
        (value == null ||
            !value.isFinite ||
            value < 0 ||
            key == 'reps' && value != value.round())) {
      setState(
        () => errors[key] =
            'Enter a non-negative ${key == 'reps' ? 'whole number' : 'number'}',
      );
      return;
    }
    setState(() {
      errors.remove(key);
      writes++;
      failure = null;
    });
    pending = pending.then((_) async {
      try {
        await widget.onSave({key: value});
      } catch (e) {
        if (mounted) setState(() => failure = 'Could not save: $e');
      } finally {
        if (mounted) setState(() => writes--);
      }
    });
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: writes == 0 && errors.isEmpty && failure == null,
    child: AlertDialog(
      title: const Text('Edit actual set'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Targets stay unchanged. Valid edits save immediately.'),
            for (final key in labels.keys)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  autofocus: key == labels.keys.first,
                  controller: controllers[key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: labels[key],
                    errorText: errors[key],
                  ),
                  onChanged: (text) => changed(key, text),
                ),
              ),
            const SizedBox(height: 12),
            Text(failure ?? (writes > 0 ? 'Saving...' : 'Saved on device')),
            if (failure != null)
              TextButton(
                onPressed: () {
                  for (final key in controllers.keys) {
                    changed(key, controllers[key]!.text);
                  }
                },
                child: const Text('Retry save'),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: errors.isNotEmpty || failure != null || writes > 0
              ? null
              : () async {
                  await pending;
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
