import 'map_projection.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/ride.dart';
import '../data/map_tile_repository.dart';
import '../platform/ride_platform.dart';

/// Web Mercator raster viewport. Only visible tiles are fetched, with persistent HTTP caching.
class RideMap extends ConsumerStatefulWidget {
  final List<RidePoint> route;
  final RidePoint? location;
  final bool dark, tiles;
  const RideMap({
    super.key,
    this.route = const [],
    this.location,
    this.dark = true,
    this.tiles = true,
  });
  @override
  ConsumerState<RideMap> createState() => _RideMapState();
}

class _RideMapState extends ConsumerState<RideMap> {
  double latitude = 0, longitude = 0, zoom = 2;
  bool following = true, positioned = false;
  double baseZoom = 2;
  Offset anchor = Offset.zero;
  Size viewport = Size.zero;
  static double worldSize(double zoom) => MapProjection.worldSize(zoom);
  static Offset project(double latitude, double longitude, double zoom) =>
      MapProjection.project(latitude, longitude, zoom);
  void centerOn(Offset pixel, double z) {
    final position = MapProjection.unproject(pixel, z);
    latitude = position.$1;
    longitude = position.$2;
  }

  bool fitPending = false;
  void fitRoute(Size size) {
    if (!fitPending || widget.route.length < 2) return;
    fitPending = false;
    final world = worldSize(16),
        reference = project(
          widget.route.first.latitude,
          widget.route.first.longitude,
          16,
        ).dx;
    final extent = widget.route.map((p) {
      final pixel = project(p.latitude, p.longitude, 16);
      var x = pixel.dx;
      if (x - reference > world / 2) x -= world;
      if (x - reference < -world / 2) x += world;
      return Offset(x, pixel.dy);
    }).toList();
    final xs = extent.map((p) => p.dx), ys = extent.map((p) => p.dy);
    final minX = xs.reduce(math.min),
        maxX = xs.reduce(math.max),
        minY = ys.reduce(math.min),
        maxY = ys.reduce(math.max);
    final ratio = math.max(
      (maxX - minX) / math.max(1, size.width - 64),
      (maxY - minY) / math.max(1, size.height - 64),
    );
    zoom = (16 - math.log(ratio.clamp(1, 65536)) / math.ln2).clamp(2, 17);
    centerOn(Offset((minX + maxX) / 2, (minY + maxY) / 2), 16);
  }

  @override
  void initState() {
    super.initState();
    initialPosition();
  }

  void initialPosition() {
    final point = widget.location ?? widget.route.lastOrNull;
    if (point != null) {
      latitude = point.latitude;
      longitude = point.longitude;
      zoom = 16;
      positioned = true;
      fitPending = widget.location == null && widget.route.length > 1;
    }
  }

  @override
  void didUpdateWidget(RideMap old) {
    super.didUpdateWidget(old);
    if (!positioned && (widget.location != null || widget.route.isNotEmpty)) {
      initialPosition();
    }
    if (following && widget.location != null) {
      latitude = widget.location!.latitude;
      longitude = widget.location!.longitude;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      viewport = constraints.biggest;
      fitRoute(viewport);
      final center = project(latitude, longitude, zoom);
      final topLeft = center - Offset(viewport.width / 2, viewport.height / 2);
      final tileZoom = zoom.floor(),
          tileScale = math.pow(2, zoom - tileZoom).toDouble(),
          side = 256 * tileScale;
      final count = 1 << tileZoom;
      final tiles = <Widget>[];
      for (
        var y = (topLeft.dy / side).floor();
        y < ((topLeft.dy + viewport.height) / side).ceil();
        y++
      ) {
        if (y < 0 || y >= count) continue;
        for (
          var x = (topLeft.dx / side).floor();
          x < ((topLeft.dx + viewport.width) / side).ceil();
          x++
        ) {
          final xx = ((x % count) + count) % count;
          tiles.add(
            Positioned(
              left: x * side - topLeft.dx,
              top: y * side - topLeft.dy,
              width: side + 0.6,
              height: side + 0.6,
              child: widget.tiles
                  ? FutureBuilder(
                      future: ref
                          .read(mapTileRepositoryProvider)
                          .tile(tileZoom, xx, y),
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return Container(
                            decoration: BoxDecoration(
                              color: const Color(0xff17201b),
                              border: Border.all(
                                color: const Color(0xff243128),
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.map_outlined,
                                color: Color(0xff324237),
                              ),
                            ),
                          );
                        }
                        final image = Image.memory(
                          snapshot.data!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) =>
                              const ColoredBox(color: Color(0xff17201b)),
                        );
                        return widget.dark
                            ? ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  -0.22,
                                  -0.22,
                                  -0.22,
                                  0,
                                  200,
                                  -0.20,
                                  -0.24,
                                  -0.20,
                                  0,
                                  209,
                                  -0.22,
                                  -0.22,
                                  -0.22,
                                  0,
                                  200,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ]),
                                child: image,
                              )
                            : image;
                      },
                    )
                  : const ColoredBox(color: Color(0xff17201b)),
            ),
          );
        }
      }
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                baseZoom = zoom;
                anchor =
                    center +
                    details.localFocalPoint -
                    Offset(viewport.width / 2, viewport.height / 2);
              },
              onScaleUpdate: (details) => setState(() {
                following = false;
                zoom = (baseZoom + math.log(details.scale) / math.ln2).clamp(
                  2,
                  18,
                );
                centerOn(
                  anchor * math.pow(2, zoom - baseZoom).toDouble() -
                      details.localFocalPoint +
                      Offset(viewport.width / 2, viewport.height / 2),
                  zoom,
                );
              }),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ...tiles,
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _RoutePainter(
                        widget.route,
                        widget.location,
                        center,
                        zoom,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Recenter / north up',
                    onPressed: () => setState(() {
                      following = true;
                      initialPosition();
                    }),
                    child: Icon(
                      following ? Icons.my_location : Icons.location_searching,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton.filledTonal(
                    tooltip: 'Zoom in',
                    onPressed: () =>
                        setState(() => zoom = (zoom + 1).clamp(2, 18)),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Zoom out',
                    onPressed: () =>
                        setState(() => zoom = (zoom - 1).clamp(2, 18)),
                    icon: const Icon(Icons.remove),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 6,
              top: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => ref.read(ridePlatformProvider).attribution(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text(
                      'Fictional route - simulated GPS',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 42,
              child: ValueListenableBuilder<bool>(
                valueListenable: ref
                    .read(mapTileRepositoryProvider)
                    .unavailable,
                builder: (context, unavailable, child) => unavailable
                    ? TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.black87,
                        ),
                        onPressed: () {
                          ref.read(mapTileRepositoryProvider).retry();
                          setState(() {});
                        },
                        icon: const Icon(Icons.cloud_off, size: 16),
                        label: const Text('Map offline - Retry'),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (!positioned)
              const Center(
                child: IgnorePointer(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Waiting for GPS location\nMap tiles need an internet connection.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RoutePainter extends CustomPainter {
  final List<RidePoint> points;
  final RidePoint? location;
  final Offset center;
  final double zoom;
  final Color color;
  _RoutePainter(this.points, this.location, this.center, this.zoom, this.color);
  Offset point(RidePoint p, Size size) {
    var delta = _RideMapState.project(p.latitude, p.longitude, zoom) - center;
    final world = _RideMapState.worldSize(zoom);
    if (delta.dx > world / 2) delta = delta - Offset(world, 0);
    if (delta.dx < -world / 2) delta = delta + Offset(world, 0);
    return delta + Offset(size.width / 2, size.height / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    int? segment;
    for (final p in points) {
      final offset = point(p, size);
      if (segment != p.segment) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
      segment = p.segment;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round,
    );
    if (location != null) {
      final offset = point(location!, size);
      canvas.drawCircle(offset, 14, Paint()..color = Colors.white);
      final fresh = DateTime.now().difference(location!.time).inSeconds <= 15;
      canvas.drawCircle(
        offset,
        11,
        Paint()..color = fresh ? color : Colors.grey,
      );
      if (location!.heading != null && fresh) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        canvas.rotate(location!.heading! * math.pi / 180);
        final arrow = Path()
          ..moveTo(0, -21)
          ..lineTo(-7, -8)
          ..lineTo(7, -8)
          ..close();
        canvas.drawPath(arrow, Paint()..color = color);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => true;
}
