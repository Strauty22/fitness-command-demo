import 'package:flutter/material.dart';

class SessionTargetEditor extends StatefulWidget {
  final Map<String, dynamic> target;
  final int sets;
  const SessionTargetEditor({
    super.key,
    required this.target,
    required this.sets,
  });
  @override
  State<SessionTargetEditor> createState() => _SessionTargetEditorState();
}

class _SessionTargetEditorState extends State<SessionTargetEditor> {
  final fields = <String, TextEditingController>{};
  String? error;
  late final Map<String, String> labels;
  @override
  void initState() {
    super.initState();
    final type = widget.target['type'] as String? ?? 'weighted';
    labels = {
      'sets': 'Sets',
      if (!type.startsWith('timed') && type != 'distance')
        'reps': 'Target reps (blank = unspecified)',
      'load': 'Target external load (blank = none; existing unit)',
      if (type.startsWith('timed'))
        'durationSeconds': 'Target seconds (blank = unspecified)',
      if (type == 'distance') 'distance': 'Target distance',
    };
    for (final key in labels.keys) {
      fields[key] = TextEditingController(
        text: '${key == 'sets' ? widget.sets : widget.target[key] ?? ''}',
      );
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Session targets'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Changes apply to this session only. Recorded actuals stay unchanged. Sets with recorded results cannot be removed.',
          ),
          for (final key in fields.keys)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: fields[key],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: labels[key]),
              ),
            ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final changes = <String, dynamic>{};
          for (final key in fields.keys) {
            final text = fields[key]!.text.trim();
            final value = num.tryParse(text);
            if ((text.isNotEmpty &&
                    (value == null || !value.isFinite || value < 0)) ||
                key == 'sets' &&
                    (value == null || value < 1 || value != value.round()) ||
                key == 'reps' &&
                    value != null &&
                    (value < 1 || value != value.round())) {
              setState(
                () => error =
                    'Enter valid non-negative values and whole positive sets/reps.',
              );
              return;
            }
            changes[key] = value;
          }
          Navigator.pop(context, changes);
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
