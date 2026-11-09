import 'dart:math' as math;

const metresPerMile = 1609.344;
const mphPerMps = 2.2369362921;
double? measurement(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;

class RidePoint {
  final int sequence, segment;
  final DateTime time;
  final double latitude, longitude, accuracy;
  final double? altitude, altitudeAccuracy, speed, heading;
  final bool accepted;
  final String reason;
  const RidePoint({
    required this.sequence,
    required this.segment,
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.speed,
    this.heading,
    this.accepted = true,
    this.reason = '',
  });
  factory RidePoint.fromJson(Map<String, dynamic> j) => RidePoint(
    sequence: (j['sequence'] as num? ?? 0).toInt(),
    segment: (j['segment'] as num? ?? 0).toInt(),
    time: DateTime.fromMillisecondsSinceEpoch(
      (j['time'] as num).toInt(),
      isUtc: true,
    ),
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    accuracy: measurement(j['accuracy']) ?? double.infinity,
    altitude: measurement(j['altitude']),
    altitudeAccuracy: measurement(j['altitudeAccuracy']),
    speed: measurement(j['speed']),
    heading: measurement(j['heading']),
    accepted: j['accepted'] == true,
    reason: j['reason'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'segment': segment,
    'time': time.millisecondsSinceEpoch,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy.isFinite ? accuracy : null,
    'altitude': altitude,
    'altitudeAccuracy': altitudeAccuracy,
    'speed': speed,
    'heading': heading,
    'accepted': accepted,
    'reason': reason,
  };
}

class Ride {
  final Map<String, dynamic> data;
  Ride(Map<String, dynamic> value) : data = Map.unmodifiable(value);
  String get id => data['id'] as String;
  String get status => data['status'] as String;
  bool get live => ['recording', 'paused', 'review'].contains(status);
  bool get recording => status == 'recording';
  DateTime get started => DateTime.fromMillisecondsSinceEpoch(
    (data['startedAt'] as num).toInt(),
    isUtc: true,
  );
  DateTime? get ended => data['endedAt'] == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (data['endedAt'] as num).toInt(),
          isUtc: true,
        );
  int activeMilliseconds(DateTime now) =>
      (data['activeMillis'] as num? ?? 0).toInt() +
      (recording && data['activeSince'] is num
          ? math.max(
              0,
              now.millisecondsSinceEpoch - (data['activeSince'] as num).toInt(),
            )
          : 0);
  int totalMilliseconds(DateTime now) => math.max(
    0,
    (ended ?? now).millisecondsSinceEpoch - started.millisecondsSinceEpoch,
  );
  int get movingMilliseconds => (data['movingMillis'] as num? ?? 0).toInt();
  bool get hasGps => (data['acceptedPoints'] as num? ?? 0) > 0;
  double? get metres => hasGps ? measurement(data['distanceMetres']) : null;
  double? get elevation => measurement(data['elevationGain']);
  double? get maximum => measurement(data['maximumSpeed']);
  double? currentSpeed(DateTime now) =>
      recording &&
          data['lastFixAt'] is num &&
          now.millisecondsSinceEpoch - (data['lastFixAt'] as num).toInt() <
              15000
      ? measurement(data['currentSpeed'])
      : null;
  double? averageSpeed(DateTime now) => hasGps && activeMilliseconds(now) > 0
      ? metres! / (activeMilliseconds(now) / 1000)
      : null;
  // Early native saves stored the identifying description in notes. Resolve
  // that legacy field only when no explicit description or distinct name exists.
  // This is a read-time fallback; capture data and annotations stay unchanged.
  String get description {
    final explicit = data['description'];
    if (explicit is String) return explicit;
    for (final key in ['name', 'title']) {
      final value = data[key];
      if (value is String &&
          value.trim().isNotEmpty &&
          value.trim().toLowerCase() != 'road cycling') {
        return '';
      }
    }
    return notes;
  }

  bool get personalBest => data['personalBest'] == true;
  String get notes => data['notes'] as String? ?? '';
}

String rideDuration(int milliseconds) {
  final seconds = math.max(0, milliseconds ~/ 1000);
  final hours = seconds ~/ 3600;
  return '${hours > 0 ? '$hours:' : ''}${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

double gpsDistance(double aLat, double aLon, double bLat, double bLon) {
  const rad = math.pi / 180;
  final dLat = (bLat - aLat) * rad, dLon = (bLon - aLon) * rad;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(aLat * rad) *
          math.cos(bLat * rad) *
          math.pow(math.sin(dLon / 2), 2);
  return 6371000 *
      2 *
      math.atan2(math.sqrt(h.clamp(0, 1)), math.sqrt((1 - h).clamp(0, 1)));
}
