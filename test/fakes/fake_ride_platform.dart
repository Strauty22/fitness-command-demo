import 'dart:async';
import 'dart:convert';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';

Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class FakeRidePlatform implements RidePlatform {
  final stream = StreamController<Map<String, dynamic>>.broadcast();
  final rides = <String, Map<String, dynamic>>{};
  final points = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic> prefs = {
    'interval': 'off',
    'measurements': ['distance', 'duration', 'average'],
  };
  Map<String, dynamic> ready = {
    'supported': true,
    'precisePermission': true,
    'gpsEnabled': true,
    'notifications': true,
  };
  DateTime now = DateTime.utc(2026, 11, 4, 12);
  int serial = 0, starts = 0, requests = 0;
  bool previewEnabled = false;
  @override
  bool get supported => true;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<Map<String, dynamic>> readiness({bool request = false}) async {
    if (request) requests++;
    return clone(ready);
  }

  @override
  Future<void> preview(bool enabled) async {
    previewEnabled = enabled;
  }

  @override
  Future<Map<String, dynamic>?> current() async {
    final ride = rides.values
        .where((r) => ['recording', 'paused', 'review'].contains(r['status']))
        .firstOrNull;
    return ride == null ? null : clone(ride);
  }

  @override
  Future<List<Map<String, dynamic>>> manifest() async =>
      rides.values.map(clone).toList();
  @override
  Future<Map<String, dynamic>> export(String id, int after) async => {
    'ride': clone(rides[id]!),
    'points': points[id]!
        .where((p) => (p['sequence'] as int) > after)
        .map(clone)
        .take(500)
        .toList(),
  };
  void changed(Map<String, dynamic> ride) {
    ride['updatedAt'] = ++serial;
  }

  @override
  Future<Map<String, dynamic>> command(String action, {String? notes}) async {
    var ride = await current();
    if (action == 'start') {
      if (ride != null) throw StateError('Already active');
      starts++;
      final id = 'ride-$starts';
      ride = {
        'id': id,
        'status': 'recording',
        'startedAt': now.millisecondsSinceEpoch,
        'activeSince': now.millisecondsSinceEpoch,
        'activeMillis': 0,
        'distanceMetres': 0,
        'acceptedPoints': 0,
        'movingMillis': 0,
        'segment': 0,
        'endedAt': null,
        'notes': '',
      };
      points[id] = [];
    } else {
      if (ride == null) throw StateError('No ride');
      if (action == 'pause' || action == 'review') {
        if (ride['status'] == 'recording') {
          ride['activeMillis'] =
              (ride['activeMillis'] as int) +
              now.millisecondsSinceEpoch -
              (ride['activeSince'] as int);
        }
        ride['activeSince'] = null;
        ride['segment'] = (ride['segment'] as int) + 1;
        ride['status'] = action == 'pause' ? 'paused' : 'review';
        if (action == 'review') ride['endedAt'] = now.millisecondsSinceEpoch;
      }
      if (action == 'resume') {
        ride['status'] = 'recording';
        ride['activeSince'] = now.millisecondsSinceEpoch;
      }
      if (action == 'save') {
        ride['status'] = 'completed';
        ride['notes'] = notes ?? '';
      }
      if (action == 'discard') {
        ride['status'] = 'discarded';
        points[ride['id']]!.clear();
      }
    }
    changed(ride);
    rides[ride['id'] as String] = clone(ride);
    return clone(ride);
  }

  void fix({double metres = 12, double latitude = 41, double longitude = -87}) {
    final ride = rides.values
        .where((r) => r['status'] == 'recording')
        .firstOrNull;
    if (ride == null) return;
    final sequence = ++serial;
    final point = <String, dynamic>{
      'sequence': sequence,
      'time': now.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': 3,
      'accepted': true,
      'segment': ride['segment'],
      'speed': 4,
      'heading': 90,
      'altitude': 200,
      'altitudeAccuracy': 2,
      'reason': 'moving',
    };
    points[ride['id']]!.add(point);
    ride['acceptedPoints'] = (ride['acceptedPoints'] as int) + 1;
    ride['distanceMetres'] = (ride['distanceMetres'] as num) + metres;
    ride['movingMillis'] = (ride['movingMillis'] as int) + 3000;
    ride['maximumSpeed'] = 4;
    ride['currentSpeed'] = 4;
    ride['lastFixAt'] = now.millisecondsSinceEpoch;
    ride['lastSequence'] = sequence;
    changed(ride);
    stream.add({'type': 'fix', 'point': clone(point)});
    stream.add({'type': 'changed'});
  }

  @override
  Future<Map<String, dynamic>> settings() async => clone(prefs);
  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    prefs = clone(settings);
  }

  @override
  Future<void> openSettings(String which) async {}
  @override
  Future<void> attribution() async {}
}
