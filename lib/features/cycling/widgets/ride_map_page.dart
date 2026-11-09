import 'package:flutter/material.dart';
import '../data/ride_controller.dart';
import 'ride_map.dart';
import 'ride_statistics.dart';
import '../data/ride.dart';

class RideMapPage extends StatelessWidget {
  final RideLiveState state;
  final Widget controls;
  const RideMapPage({super.key, required this.state, required this.controls});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) => Stack(
      children: [
        Positioned.fill(
          child: RideMap(route: state.route, location: state.location),
        ),
        DraggableScrollableSheet(
          initialChildSize: state.ride?.status == 'paused' ? .43 : .36,
          minChildSize: state.ride?.status == 'paused' ? .43 : .36,
          maxChildSize: .70,
          snap: true,
          snapSizes: [state.ride?.status == 'paused' ? .43 : .36, .70],
          builder: (context, scroll) => LayoutBuilder(
            builder: (context, panel) => Material(
              color: const Color(0xff171c18),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: RideMetric(
                          miles(state.ride?.metres),
                          'Distance (mi)',
                          large: true,
                        ),
                      ),
                      Expanded(
                        child: RideMetric(
                          rideDuration(
                            state.ride?.activeMilliseconds(state.now) ?? 0,
                          ),
                          'Duration',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  controls,
                  if (panel.maxHeight > viewport.maxHeight * .50) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: RideMetric(
                            mph(state.ride?.currentSpeed(state.now)),
                            'Current speed (mph)',
                          ),
                        ),
                        Expanded(
                          child: RideMetric(
                            mph(state.ride?.averageSpeed(state.now)),
                            'Average speed (mph)',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
