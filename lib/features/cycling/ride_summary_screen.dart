import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/ride.dart';
import 'data/ride_controller.dart';
import 'data/ride_repository.dart';
import 'widgets/ride_map.dart';
import 'ride_notes_editor.dart';
import 'ride_text_formatter.dart';
import 'ride_description_editor.dart';
import 'widgets/ride_statistics.dart';
import '../history/workout_history_card.dart';

class RideSummaryScreen extends ConsumerStatefulWidget {
  final Ride ride;
  final List<RidePoint> route;
  final bool review;
  const RideSummaryScreen({
    super.key,
    required this.ride,
    required this.route,
    this.review = false,
  });
  @override
  ConsumerState<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends ConsumerState<RideSummaryScreen> {
  late final TextEditingController notes, name;
  @override
  void initState() {
    super.initState();
    notes = TextEditingController(text: widget.ride.notes);
    name = TextEditingController(
      text: widget.review
          ? widget.ride.data['description'] as String? ?? ''
          : savedRideName(widget.ride),
    );
  }

  @override
  void dispose() {
    notes.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> discard() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard recorded ride?'),
        content: const Text(
          'The route and recorded measurements will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep ride'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirm == true &&
        mounted &&
        await ref.read(rideControllerProvider.notifier).act('discard') &&
        mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride,
        now = ride.ended ?? DateTime.now(),
        busy = ref.watch(rideControllerProvider).busy;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.review ? 'Finish ride' : savedRideName(ride)),
      ),
      bottomNavigationBar: widget.review
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final saved = await ref
                                    .read(rideControllerProvider.notifier)
                                    .act(
                                      'save',
                                      notes: notes.text,
                                      name: name.text,
                                    );
                                if (saved && context.mounted) {
                                  ref
                                      .read(rideControllerProvider.notifier)
                                      .newRide();
                                  context.pop();
                                }
                              },
                        child: const Text('SAVE RIDE'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: busy ? null : discard,
                      child: const Text('Discard ride'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        children: [
          SizedBox(height: 240, child: RideMap(route: widget.route)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ride.started.toLocal().toString().substring(0, 16),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (ref.watch(rideControllerProvider).error != null &&
                    ref.watch(rideControllerProvider).ride?.id == ride.id) ...[
                  Text(
                    ref.watch(rideControllerProvider).error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(rideControllerProvider.notifier).sync(),
                    child: const Text('Retry local save sync'),
                  ),
                ],
                const SizedBox(height: 16),
                RideMetric(miles(ride.metres), 'Distance (mi)', large: true),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: RideMetric(
                        rideDuration(ride.activeMilliseconds(now)),
                        'Active duration',
                      ),
                    ),
                    Expanded(
                      child: RideMetric(
                        mph(ride.averageSpeed(now)),
                        'Average speed (mph)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: RideMetric(
                        rideDuration(ride.movingMilliseconds),
                        'Moving time',
                      ),
                    ),
                    Expanded(
                      child: RideMetric(
                        rideDuration(ride.totalMilliseconds(now)),
                        'Total elapsed',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: RideMetric(
                        mph(ride.maximum),
                        'Maximum speed (mph)',
                      ),
                    ),
                    Expanded(
                      child: RideMetric(
                        ride.elevation == null
                            ? '\u2014'
                            : (ride.elevation! * 3.2808399).toStringAsFixed(0),
                        'Elevation gain (ft)',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.review) ...[
                  TextField(
                    controller: name,
                    inputFormatters: const [RideTextFormatter()],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Name your ride',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notes,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [RideTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Ride notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  if (ref.watch(rideControllerProvider).error != null)
                    Text(ref.watch(rideControllerProvider).error!),
                ] else ...[
                  SavedRideDescription(ride: ride),
                  SavedRideNotes(ride: ride),
                  ref
                      .watch(rideHistoryProvider)
                      .when(
                        loading: () => const SizedBox.shrink(),
                        error: (e, _) => Text('$e'),
                        data: (rides) {
                          final previous = rides
                              .where(
                                (r) =>
                                    r.id != ride.id &&
                                    r.started.isBefore(ride.started),
                              )
                              .firstOrNull;
                          if (previous == null) {
                            return const Text(
                              'First saved ride. Future rides can be compared here.',
                            );
                          }
                          final delta =
                              ride.metres != null && previous.metres != null
                              ? (ride.metres! - previous.metres!) /
                                    metresPerMile
                              : null;
                          final previousAverage = previous.averageSpeed(
                                previous.ended ?? now,
                              ),
                              average = ride.averageSpeed(now);
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Compared with previous ride',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    previous.started
                                        .toLocal()
                                        .toString()
                                        .substring(0, 10),
                                  ),
                                  Text(
                                    delta == null
                                        ? 'Distance unavailable'
                                        : 'Distance: ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} mi',
                                  ),
                                  if (average != null &&
                                      previousAverage != null)
                                    Text(
                                      'Average speed: ${((average - previousAverage) * mphPerMps) >= 0 ? '+' : ''}${((average - previousAverage) * mphPerMps).toStringAsFixed(1)} mph',
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final rideDetailProvider = FutureProvider.family<Ride?, String>((ref, id) {
  ref.watch(rideRevisionProvider);
  return ref.watch(rideRepositoryProvider).get(id);
});

class SavedRideScreen extends ConsumerWidget {
  final String id;
  const SavedRideScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ride = ref.watch(rideDetailProvider(id)),
        points = ref.watch(ridePointsProvider(id));
    if (ride.value == null || points.value == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ride')),
        body: Center(
          child: ride.hasError || points.hasError
              ? Text('${ride.error ?? points.error}')
              : ride.hasValue
              ? const Text('Ride not found')
              : const CircularProgressIndicator(),
        ),
      );
    }
    return RideSummaryScreen(ride: ride.value!, route: points.value!);
  }
}
