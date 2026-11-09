import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../cycling/data/ride_controller.dart';
import 'history_data.dart';
import 'history_delete_button.dart';
import 'workout_history_card.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(ref.read(rideControllerProvider.notifier).sync());
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('History')),
    body: ref
        .watch(combinedHistoryProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load history: $e')),
          data: (entries) => entries.isEmpty
              ? const Center(child: Text('No finished workouts yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final action = HistoryDeleteButton(entry: entry);
                    return entry.session != null
                        ? StrengthHistoryCard(
                            key: ValueKey(entry.key),
                            session: entry.session!,
                            deleteAction: action,
                            onTap: () =>
                                context.push('/session/${entry.session!.id}'),
                          )
                        : RideHistoryCard(
                            key: ValueKey(entry.key),
                            ride: entry.ride!,
                            deleteAction: action,
                            onTap: () =>
                                context.push('/rides/${entry.ride!.id}'),
                          );
                  },
                ),
        ),
  );
}
