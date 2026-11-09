import 'package:flutter/material.dart';
import '../data/ride.dart';

class RideMetric extends StatelessWidget {
  final String value, label;
  final bool large;
  const RideMetric(this.value, this.label, {super.key, this.large = false});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            fontSize: large ? 64 : 36,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.15,
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    ],
  );
}

String miles(double? metres) =>
    metres == null ? '\u2014' : (metres / metresPerMile).toStringAsFixed(2);
String mph(double? mps) =>
    mps == null ? '\u2014' : (mps * mphPerMps).toStringAsFixed(1);

class RideStatistics extends StatelessWidget {
  final Ride? ride;
  final DateTime now;
  final bool expanded;
  const RideStatistics({
    super.key,
    required this.ride,
    required this.now,
    this.expanded = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      RideMetric(miles(ride?.metres), 'Distance (mi)', large: true),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: RideMetric(
              rideDuration(ride?.activeMilliseconds(now) ?? 0),
              'Duration',
            ),
          ),
          if (expanded)
            Expanded(
              child: RideMetric(
                mph(ride?.currentSpeed(now)),
                'Current speed (mph)',
              ),
            ),
        ],
      ),
      if (expanded) ...[
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: RideMetric(
                mph(ride?.averageSpeed(now)),
                'Average speed (mph)',
              ),
            ),
            Expanded(
              child: RideMetric(
                ride?.elevation == null
                    ? '\u2014'
                    : (ride!.elevation! * 3.2808399).toStringAsFixed(0),
                'Elevation gain (ft)',
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
