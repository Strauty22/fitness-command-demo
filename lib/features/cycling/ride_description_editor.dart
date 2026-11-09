import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/ride.dart';
import 'ride_text_formatter.dart';
import 'data/ride_repository.dart';
import '../history/workout_history_card.dart';

class SavedRideDescription extends StatelessWidget {
  final Ride ride;
  const SavedRideDescription({super.key, required this.ride});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          savedRideName(ride),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        tooltip: 'Edit description',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _DescriptionDialog(ride: ride),
        ),
      ),
    ],
  );
}

class _DescriptionDialog extends ConsumerStatefulWidget {
  final Ride ride;
  const _DescriptionDialog({required this.ride});
  @override
  ConsumerState<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends ConsumerState<_DescriptionDialog> {
  late final TextEditingController description;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final savedDescription = widget.ride.data['description'];
    final title = savedRideName(widget.ride);
    description = TextEditingController(
      text: savedDescription is String
          ? savedDescription
          : widget.ride.description.trim().isNotEmpty
          ? widget.ride.description
          : title == 'Road Cycling'
          ? ''
          : title,
    );
  }

  @override
  void dispose() {
    description.dispose();
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
          .saveDescription(widget.ride.id, description.text);
      if (!mounted) return;
      ref.read(rideRevisionProvider.notifier).refresh();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save description: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Edit ride description'),
      content: TextField(
        controller: description,
        inputFormatters: const [RideTextFormatter()],
        textCapitalization: TextCapitalization.sentences,
        autofocus: true,
        enabled: !saving,
        decoration: InputDecoration(
          labelText: 'Description',
          hintText: 'Name your ride',
          errorText: error,
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
