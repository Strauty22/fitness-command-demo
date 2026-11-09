import 'package:flutter/material.dart';
import '../strength/data/strength_session.dart';
import '../cycling/data/ride.dart';
import 'workout_summary.dart';

class WorkoutHistoryCard extends StatelessWidget {
  final String name;
  final DateTime date;
  final List<Widget> children;
  final String duration;
  final VoidCallback? onTap;
  final Widget? deleteAction;
  const WorkoutHistoryCard({
    super.key,
    required this.name,
    required this.date,
    required this.children,
    required this.duration,
    this.onTap,
    this.deleteAction,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    historyDate(date),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    duration,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (deleteAction != null)
                  deleteAction!
                else
                  const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class SummaryMetric extends StatelessWidget {
  final String label, value;
  const SummaryMetric(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class StrengthHistoryCard extends StatelessWidget {
  final StrengthSession session;
  final VoidCallback? onTap;
  final Widget? deleteAction;
  final bool indicators;
  const StrengthHistoryCard({
    super.key,
    required this.session,
    this.onTap,
    this.deleteAction,
    this.indicators = false,
  });
  @override
  Widget build(BuildContext context) => WorkoutHistoryCard(
    name: session.name,
    date: session.endedAt ?? session.startedAt,
    duration: summaryDuration(strengthDuration(session)),
    onTap: onTap,
    deleteAction: deleteAction,
    children: [
      if (session.status == 'cancelled') const Text('Cancelled'),
      if (session.completedSets < session.totalSets)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Partial workout - ${session.completedSets}/${session.totalSets} sets recorded',
          ),
        ),
      for (final exercise in summaryExercises(session)) ...[
        SummaryMetric(exercise['name'] as String, exerciseSummary(exercise)),
        if (indicators)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final set in completedActuals(exercise))
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16),
                    label: Text(actualSummary(exercise, set)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
      ],
      if (session.completedSets == 0) const Text('No completed sets'),
    ],
  );
}

String savedRideName(Ride ride) {
  final description = ride.description.trim();
  if (description.isNotEmpty) return description;
  for (final key in ['name', 'title']) {
    final value = ride.data[key];
    if (value is String &&
        value.trim().isNotEmpty &&
        value.trim().toLowerCase() != 'road cycling') {
      return value.trim();
    }
  }
  return 'Road Cycling';
}

class RideHistoryCard extends StatelessWidget {
  final Ride ride;
  final VoidCallback? onTap;
  final Widget? deleteAction;
  const RideHistoryCard({
    super.key,
    required this.ride,
    this.onTap,
    this.deleteAction,
  });
  @override
  Widget build(BuildContext context) {
    final end = ride.ended ?? ride.started;
    final average = ride.averageSpeed(end);
    return WorkoutHistoryCard(
      name: savedRideName(ride),
      date: end,
      duration: rideDuration(ride.activeMilliseconds(end)),
      onTap: onTap,
      deleteAction: deleteAction,
      children: [
        SummaryMetric(
          'Distance',
          ride.metres == null
              ? 'Unavailable'
              : '${(ride.metres! / metresPerMile).toStringAsFixed(2)} mi',
        ),
        if (average != null)
          SummaryMetric(
            'Average Speed',
            '${(average * mphPerMps).toStringAsFixed(1)} mph',
          ),
        if (ride.notes.trim().isNotEmpty &&
            ride.notes.trim().toLowerCase() !=
                savedRideName(ride).toLowerCase())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ride.notes.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
