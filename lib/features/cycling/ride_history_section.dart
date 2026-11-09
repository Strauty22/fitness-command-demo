import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/ride_controller.dart';
import 'data/ride_repository.dart';
import 'data/ride.dart';
import '../history/workout_history_card.dart';
import '../history/history_delete_button.dart';
import '../history/history_data.dart';

class RideHistorySection extends ConsumerStatefulWidget {
  final bool progress;
  const RideHistorySection({super.key, this.progress = false});
  @override
  ConsumerState<RideHistorySection> createState() => _RideHistorySectionState();
}

class _RideHistorySectionState extends ConsumerState<RideHistorySection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => unawaited(ref.read(rideControllerProvider.notifier).sync()),
    );
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(rideHistoryProvider)
      .when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Text('Could not load rides: $e'),
        data: (rides) {
          if (rides.isEmpty) return const SizedBox.shrink();
          if (widget.progress) {
            final known = rides.where((r) => r.metres != null).toList();
            final total = known.fold<double>(0, (sum, r) => sum + r.metres!);
            return Card(
              child: ListTile(
                leading: const Icon(Icons.directions_bike),
                title: Text('${rides.length} saved rides'),
                subtitle: Text(
                  '${known.isEmpty ? 'Unavailable' : (total / metresPerMile).toStringAsFixed(2)} miles recorded / Compare rides in History',
                ),
                onTap: () => context.push('/rides/${rides.first.id}'),
              ),
            );
          }
          return Column(
            children: [
              for (final ride in rides)
                RideHistoryCard(
                  ride: ride,
                  deleteAction: HistoryDeleteButton(
                    entry: HistoryEntry.cycling(ride),
                  ),
                  onTap: () => context.push('/rides/${ride.id}'),
                ),
            ],
          );
        },
      );
}
