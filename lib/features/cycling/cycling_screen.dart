import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/ride_controller.dart';
import 'platform/ride_platform.dart';
import 'widgets/ride_map_page.dart';
import 'widgets/ride_statistics.dart';
import 'cycling_settings.dart';
import 'ride_summary_screen.dart';

class CyclingScreen extends ConsumerStatefulWidget {
  const CyclingScreen({super.key});
  @override
  ConsumerState<CyclingScreen> createState() => _CyclingScreenState();
}

class _CyclingScreenState extends ConsumerState<CyclingScreen>
    with WidgetsBindingObserver {
  int page = 0;
  late final RidePlatform platform;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platform = ref.read(ridePlatformProvider);
    Future.microtask(() => ref.read(rideControllerProvider.notifier).enter());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(rideControllerProvider.notifier).sync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(platform.preview(false).catchError((Object _) {}));
    super.dispose();
  }

  Widget controls(RideLiveState state) {
    final controller = ref.read(rideControllerProvider.notifier),
        ride = state.ride;
    final action = ride == null
        ? 'start'
        : ride.recording
        ? 'pause'
        : 'resume';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: state.busy || state.readiness['supported'] != true
              ? null
              : () => controller.act(action),
          icon: Icon(ride?.recording == true ? Icons.pause : Icons.play_arrow),
          label: Text(
            ride == null
                ? 'START WORKOUT'
                : ride.recording
                ? 'PAUSE'
                : 'RESUME',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (ride?.status == 'paused')
          TextButton(
            onPressed: state.busy ? null : () => controller.act('review'),
            child: const Text('FINISH'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rideControllerProvider), ride = state.ride;
    if (ride != null && ['review', 'completed'].contains(ride.status)) {
      return RideSummaryScreen(
        ride: ride,
        route: state.route,
        review: ride.status == 'review',
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Road Cycling'),
        actions: [
          IconButton(
            tooltip: 'Cycling settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CyclingSettings()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.gps_fixed,
                    size: 16,
                    color:
                        state.location != null && state.location!.accuracy <= 25
                        ? Colors.green
                        : Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.gpsLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (state.readiness['precisePermission'] != true)
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => ref
                                .read(rideControllerProvider.notifier)
                                .enableGps(),
                      child: const Text('Enable GPS'),
                    ),
                  if (state.readiness['gpsEnabled'] == false)
                    TextButton(
                      onPressed: () =>
                          ref.read(ridePlatformProvider).openSettings('gps'),
                      child: const Text('GPS settings'),
                    ),
                ],
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  state.error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (ride?.data['recovered'] == true)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Interrupted ride recovered, paused. Resume when ready.',
                ),
              ),
            Expanded(
              child: PageView(
                onPageChanged: (value) => setState(() => page = value),
                children: [
                  RideMapPage(state: state, controls: controls(state)),
                  ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 24),
                      RideStatistics(ride: ride, now: state.now),
                      const SizedBox(height: 36),
                      controls(state),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: page == i
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade700,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    page == 0 ? 'MAP' : 'STATISTICS',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
