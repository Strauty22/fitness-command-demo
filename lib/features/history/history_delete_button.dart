import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cycling/data/ride_repository.dart';
import '../strength/data/session_repository.dart';
import 'history_data.dart';

class HistoryDeleteButton extends ConsumerStatefulWidget {
  final HistoryEntry entry;
  const HistoryDeleteButton({super.key, required this.entry});
  @override
  ConsumerState<HistoryDeleteButton> createState() =>
      _HistoryDeleteButtonState();
}

class _HistoryDeleteButtonState extends ConsumerState<HistoryDeleteButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final session = widget.entry.session;
    final isRide = session == null;
    return IconButton(
      tooltip: isRide ? 'Delete ride' : 'Delete workout',
      icon: const Icon(Icons.delete_outline),
      onPressed: busy
          ? null
          : () async {
              setState(() => busy = true);
              try {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      isRide ? 'Delete ride?' : 'Delete workout history?',
                    ),
                    content: Text(
                      isRide
                          ? 'Delete this ride? This will permanently remove the ride and its recorded data.'
                          : 'Permanently delete ${session.name} and its recorded sets? This cannot be undone. Templates and future targets will stay unchanged.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(isRide ? 'Cancel' : 'Keep'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                if (isRide) {
                  await ref
                      .read(rideRepositoryProvider)
                      .deleteHistory(widget.entry.ride!.id);
                  if (mounted) {
                    ref.read(rideRevisionProvider.notifier).refresh();
                  }
                } else {
                  await ref
                      .read(sessionRepositoryProvider)
                      .deleteHistory(session.id);
                  if (mounted) {
                    ref.read(sessionRevisionProvider.notifier).refresh();
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not delete ${isRide ? 'ride' : 'workout'}: $e',
                      ),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
    );
  }
}
