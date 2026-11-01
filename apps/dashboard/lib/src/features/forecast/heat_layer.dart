import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Below this relative density a barangay is left unpainted: noise.
const _quietBelow = 0.05;

/// The smallest reach of a glow: about three times the KDE's bandwidth
/// (200 m), where a Gaussian kernel fades out, so a small barangay still
/// shows at city zoom and neighbours blend.
const _minReachMeters = 600.0;

/// A heat map over the map (design skill: "smooth gradient from
/// transparent → ember → signal over the muted basemap"): one soft glow per
/// barangay in [weights] (0 to 1), centred on it and reaching a little past
/// its edge, stronger and redder the higher its weight. Neighbouring glows
/// blend into hot areas. The map does not rotate on the Heatmap page, so
/// this paints in screen space.
class HeatLayer extends StatelessWidget {
  const HeatLayer({super.key, required this.weights});

  final Map<String, double> weights;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final p = SagipPalette.of(context);
    final spots = <_Spot>[];
    for (final MapEntry(key: name, value: weight) in weights.entries) {
      if (weight < _quietBelow) continue;
      final b = barangayNamed(name);
      final center = b?.center;
      if (center == null) continue;
      final reach = math.max(
        _minReachMeters,
        (barangayRadiusMeters(name) ?? 0) * 1.6,
      );
      final at = camera.latLngToScreenOffset(LatLng(center.lat, center.lng));
      // A point [reach] meters north, for the glow's radius in pixels.
      final edge = camera.latLngToScreenOffset(
        LatLng(center.lat + reach / 110574, center.lng),
      );
      spots.add(_Spot(at, (at - edge).distance, weight));
    }
    // Weakest first, so the hottest cores end on top.
    spots.sort((a, b) => a.relative.compareTo(b.relative));
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HeatPainter(
          spots: spots,
          warm: p.warning.fill,
          hot: p.critical.fill,
        ),
      ),
    );
  }
}

/// The color of [relative] density: ember at the low end, signal at the
/// top. Shared with the legend so the two always match.
Color heatColor(double relative, Color warm, Color hot) =>
    Color.lerp(warm, hot, relative.clamp(0, 1).toDouble())!;

/// How opaque the middle of a glow is at [relative] density.
double heatAlpha(double relative) => 0.35 + 0.3 * relative.clamp(0, 1);

class _Spot {
  const _Spot(this.at, this.radius, this.relative);

  final Offset at;
  final double radius;
  final double relative;
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({required this.spots, required this.warm, required this.hot});

  final List<_Spot> spots;
  final Color warm;
  final Color hot;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    for (final s in spots) {
      if (s.radius < 1) continue;
      final rect = Rect.fromCircle(center: s.at, radius: s.radius);
      if (!rect.overlaps(screen)) continue;
      final color = heatColor(s.relative, warm, hot);
      final alpha = heatAlpha(s.relative);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.55),
            warm.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect);
      canvas.drawCircle(s.at, s.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.spots != spots || old.warm != warm || old.hot != hot;
}
