import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import '../models/road_condition.dart';
import '../theme/sagip_palette.dart';
import 'sagip_map.dart';

// TomTom's jams, closed roads, and flooded roads on a map (2026-11-25).
// Joshua asked for them to be red or something that stands out: thick
// lines with a dark outline so they read on the dark map and the light one.

/// The colour of a reported road: red for a heavy jam or a closed road,
/// orange for slow traffic, blue for a flooded road.
Color roadConditionColor(SagipPalette p, RoadCondition r) => switch (r.kind) {
  RoadConditionKind.flooding => p.info.fill,
  RoadConditionKind.closed => p.critical.fill,
  RoadConditionKind.jam => r.isHeavy ? p.critical.fill : p.warning.fill,
};

/// The reported roads as thick lines. Closed roads are dashed; flooded and
/// closed roads draw over jams. [scale] widens the lines (the wall map).
/// [hitNotifier] tells the map which road was tapped.
class RoadConditionsLayer extends StatelessWidget {
  const RoadConditionsLayer({
    super.key,
    required this.roads,
    this.scale = 1,
    this.hitNotifier,
  });

  final List<RoadCondition> roads;
  final double scale;
  final LayerHitNotifier<RoadCondition>? hitNotifier;

  /// Line width in logical pixels before [scale].
  static const width = 6.0;

  static int _order(RoadCondition r) => switch (r.kind) {
    RoadConditionKind.jam => r.isHeavy ? 1 : 0,
    RoadConditionKind.closed => 2,
    RoadConditionKind.flooding => 3,
  };

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final sorted = [...roads]..sort((a, b) => _order(a).compareTo(_order(b)));
    return PolylineLayer<RoadCondition>(
      hitNotifier: hitNotifier,
      polylines: [
        for (final r in sorted)
          Polyline<RoadCondition>(
            points: [for (final g in r.path) toLatLng(g)],
            color: roadConditionColor(p, r),
            strokeWidth: width * scale,
            borderColor: Colors.black.withValues(alpha: 0.55),
            borderStrokeWidth: 1.5 * scale,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
            pattern: r.kind == RoadConditionKind.closed
                ? StrokePattern.dashed(segments: [10 * scale, 6 * scale])
                : const StrokePattern.solid(),
            hitValue: r,
          ),
      ],
    );
  }
}

/// A small sample of a road line for a legend.
class RoadLegendSwatch extends StatelessWidget {
  const RoadLegendSwatch({super.key, required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 12,
    child: CustomPaint(painter: _SwatchPainter(color, dashed)),
  );
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = color
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas
        ..drawLine(Offset(2, y), Offset(size.width - 2, y), outline)
        ..drawLine(Offset(2, y), Offset(size.width - 2, y), line);
      return;
    }
    for (final (a, b) in [(2.0, 7.0), (11.0, 16.0)]) {
      canvas
        ..drawLine(Offset(a, y), Offset(b, y), outline)
        ..drawLine(Offset(a, y), Offset(b, y), line);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.dashed != dashed;
}
