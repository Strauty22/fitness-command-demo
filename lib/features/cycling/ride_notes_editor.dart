import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/ride.dart';
import 'ride_text_formatter.dart';
import 'data/ride_repository.dart';

class SavedRideNotes extends StatelessWidget {
  final Ride ride;
  const SavedRideNotes({super.key, required this.ride});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(ride.notes.isEmpty ? 'No notes' : ride.notes),
        ),
      ),
      IconButton(
        tooltip: 'Edit notes',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _RideNotesDialog(ride: ride),
        ),
      ),
    ],
  );
}

class _RideNotesDialog extends ConsumerStatefulWidget {
  final Ride ride;
  const _RideNotesDialog({required this.ride});
  @override
  ConsumerState<_RideNotesDialog> createState() => _RideNotesDialogState();
}

class _RideNotesDialogState extends ConsumerState<_RideNotesDialog> {
  late final TextEditingController notes;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    notes = TextEditingController(text: widget.ride.notes);
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(rideRepositoryProvider)
          .saveNotes(widget.ride.id, notes.text);
      if (!mounted) return;
      ref.read(rideRevisionProvider.notifier).refresh();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save notes: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Edit ride notes'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notes,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: const [RideTextFormatter()],
              autofocus: true,
              enabled: !saving,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Ride notes',
                border: OutlineInputBorder(),
              ),
            ),
            if (error != null) Text(error!),
          ],
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
    ),
  );
}
