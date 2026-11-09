import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/ride_platform.dart';
import 'ride.dart';
import 'ride_repository.dart';

class RideLiveState {
  final Ride? ride;
  final List<RidePoint> route;
  final RidePoint? location;
  final Map<String, dynamic> readiness;
  final bool busy;
  final String? error;
  final DateTime now;
  RideLiveState({
    this.ride,
    this.route = const [],
    this.location,
    this.readiness = const {},
    this.busy = false,
    this.error,
    DateTime? now,
  }) : now = now ?? DateTime.now();
  RideLiveState withValues({
    Ride? ride,
    List<RidePoint>? route,
    RidePoint? location,
    Map<String, dynamic>? readiness,
    bool? busy,
    String? error,
    bool clearRide = false,
    bool clearError = false,
  }) => RideLiveState(
    ride: clearRide ? null : ride ?? this.ride,
    route: route ?? this.route,
    location: location ?? this.location,
    readiness: readiness ?? this.readiness,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
  );
  String get gpsLabel {
    if (readiness['supported'] == true) return 'Simulated GPS';
    if (readiness['precisePermission'] != true) return 'Enable precise GPS';
    if (readiness['gpsEnabled'] != true) return 'GPS is off';
    if (location == null || now.difference(location!.time).inSeconds > 15) {
      return 'Waiting for GPS';
    }
    return location!.accuracy <= 10
        ? 'GPS good'
        : location!.accuracy <= 25
        ? 'GPS fair'
        : 'GPS weak';
  }
}

class RideController extends Notifier<RideLiveState> {
  StreamSubscription<Map<String, dynamic>>? subscription;
  Timer? clock;
  bool initialized = false, syncing = false, syncAgain = false;
  Future<void>? initialization;
  Completer<void>? syncCompletion;
  RidePlatform get platform => ref.read(ridePlatformProvider);
  RideRepository get repo => ref.read(rideRepositoryProvider);
  @override
  RideLiveState build() {
    ref.onDispose(() {
      subscription?.cancel();
      clock?.cancel();
    });
    return RideLiveState();
  }

  Future<void> initialize() => initialization ??= _initialize();
  Future<void> _initialize() async {
    state = state.withValues(busy: true, clearError: true);
    try {
      state = state.withValues(readiness: await platform.readiness());
      subscription = platform.events.listen(
        (event) {
          if (event['type'] == 'fix' &&
              ![
                'GPS jump',
                'out of order',
                'invalid coordinate',
              ].contains((event['point'] as Map?)?['reason'])) {
            try {
              state = state.withValues(
                location: RidePoint.fromJson(
                  Map<String, dynamic>.from(event['point'] as Map),
                ),
              );
            } catch (_) {}
          }
          if (event['type'] == 'error') {
            state = state.withValues(error: event['message'] as String?);
          }
          if (event['type'] == 'changed') unawaited(sync());
        },
        onError: (Object error) {
          state = state.withValues(error: 'GPS connection failed: $error');
        },
      );
      await sync();
      if (state.readiness['precisePermission'] == true) {
        await platform.preview(state.ride == null);
      }
      clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.ride?.recording == true) state = state.withValues();
      });
      initialized = true;
    } catch (e) {
      state = state.withValues(error: 'Could not open cycling: $e');
      initialization = null;
    } finally {
      state = state.withValues(busy: false);
    }
  }

  Future<void> sync() {
    if (syncCompletion != null) {
      syncAgain = true;
      return syncCompletion!.future;
    }
    final completion = Completer<void>();
    syncCompletion = completion;
    unawaited(_sync(completion));
    return completion.future;
  }

  Future<void> _sync(Completer<void> completion) async {
    syncing = true;
    try {
      do {
        syncAgain = false;
        final manifests = await platform.manifest();
        // Close older mirrored rides before importing a new active one.
        manifests.sort(
          (a, b) => (Ride(a).live ? 1 : 0).compareTo(Ride(b).live ? 1 : 0),
        );
        for (final metadata in manifests) {
          final ride = Ride(metadata);
          if (await repo.isDeleted(ride.id)) continue;
          final old = await repo.get(ride.id);
          if (old?.status == ride.status &&
              old?.data['updatedAt'] == ride.data['updatedAt'] &&
              (await repo.lastSequence(ride.id)) >=
                  (ride.data['lastSequence'] as num? ?? 0)) {
            continue;
          }
          var after = await repo.lastSequence(ride.id);
          do {
            final exported = await platform.export(ride.id, after);
            final captured = Ride(
              Map<String, dynamic>.from(exported['ride'] as Map),
            );
            final points = (exported['points'] as List)
                .map(
                  (p) =>
                      RidePoint.fromJson(Map<String, dynamic>.from(p as Map)),
                )
                .toList();
            await repo.importCapture(captured, points);
            if (points.isEmpty || points.length < 500) break;
            after = points.last.sequence;
          } while (true);
        }
        final current = await platform.current();
        if (current != null) {
          final ride = await repo.get(current['id'] as String) ?? Ride(current);
          state = state.withValues(
            ride: ride,
            route: await repo.points(ride.id),
          );
        } else if (state.ride?.status != 'completed') {
          state = state.withValues(clearRide: true, route: const []);
        }
        state = state.withValues(
          readiness: await platform.readiness(),
          clearError: true,
        );
        ref.read(rideRevisionProvider.notifier).refresh();
      } while (syncAgain);
    } catch (e) {
      state = state.withValues(
        error:
            'Could not sync saved GPS capture: $e. Native recording is retained for retry.',
      );
    } finally {
      syncing = false;
      syncCompletion = null;
      completion.complete();
    }
  }

  Future<void> enter() async {
    await initialize();
    await sync();
    await platform.preview(state.ride == null);
  }

  Future<void> enableGps() async {
    if (state.busy) return;
    state = state.withValues(busy: true, clearError: true);
    try {
      state = state.withValues(
        readiness: await platform.readiness(request: true),
      );
      await platform.preview(state.ride == null);
    } catch (e) {
      state = state.withValues(error: 'Could not enable GPS: $e');
    } finally {
      state = state.withValues(busy: false);
    }
  }

  Future<bool> act(String action, {String? notes, String? name}) async {
    if (state.busy) return false;
    state = state.withValues(busy: true, clearError: true);
    try {
      if (action == 'start' || action == 'resume') {
        final readiness = await platform.readiness(request: true);
        state = state.withValues(readiness: readiness);
        if (readiness['supported'] != true) {
          throw StateError(
            'GPS recording is implemented on Android. iOS capture is not available yet.',
          );
        }
        if (readiness['precisePermission'] != true) {
          throw StateError(
            'Allow precise location in app settings to record a ride.',
          );
        }
        if (readiness['gpsEnabled'] != true) {
          throw StateError('Turn on device GPS before starting.');
        }
        if (readiness['notifications'] != true) {
          throw StateError(
            'Allow ride notifications to record with the screen off.',
          );
        }
      }
      if (action == 'start' || action == 'resume') {
        await platform.preview(false);
      }
      final response = Ride(await platform.command(action, notes: notes));
      state = state.withValues(ride: response);
      await sync();
      if (action == 'save' && state.error == null) {
        if (name != null) await repo.saveDescription(response.id, name);
        ref.read(rideRevisionProvider.notifier).refresh();
        state = state.withValues(
          ride: await repo.get(response.id) ?? response,
          route: await repo.points(response.id),
        );
      }
      if (action == 'discard') {
        state = state.withValues(clearRide: true, route: const []);
      }
      return state.error == null;
    } catch (e) {
      state = state.withValues(error: 'Could not $action ride: $e');
      return false;
    } finally {
      state = state.withValues(busy: false);
    }
  }

  void newRide() {
    state = state.withValues(
      clearRide: true,
      route: const [],
      clearError: true,
    );
  }

  Future<void> leavePreview() => platform.preview(false);
}

final rideControllerProvider = NotifierProvider<RideController, RideLiveState>(
  RideController.new,
);
