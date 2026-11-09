import 'dart:math' as math;
import 'dart:ui';

class MapProjection {
  static double worldSize(double zoom) => 256 * math.pow(2, zoom).toDouble();
  static Offset project(double latitude, double longitude, double zoom) {
    final size = worldSize(zoom),
        sin = math.sin(latitude.clamp(-85.0511, 85.0511) * math.pi / 180);
    return Offset(
      (longitude + 180) / 360 * size,
      (.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * size,
    );
  }

  /// Returns latitude, longitude. Longitudes wrap around the antimeridian.
  static (double, double) unproject(Offset pixel, double zoom) {
    final size = worldSize(zoom), y = pixel.dy.clamp(0.0, size);
    final longitude = ((pixel.dx / size * 360) % 360 + 360) % 360 - 180;
    final n = math.pi - 2 * math.pi * y / size;
    final latitude =
        (180 / math.pi * math.atan((math.exp(n) - math.exp(-n)) / 2)).clamp(
          -85.0511,
          85.0511,
        );
    return (latitude, longitude);
  }
}
