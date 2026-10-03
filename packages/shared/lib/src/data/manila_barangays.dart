import 'dart:math' as math;

import '../algorithms/polyline.dart';
import '../models/account.dart';
import '../models/geo_point.dart';

part 'manila_barangays_data.dart';

/// One barangay's outline, decoded once, with its bounding box so most
/// barangays are skipped without a full test.
class _Shape {
  _Shape(List<String> rings)
    : rings = [for (final r in rings) decodePolyline(r)] {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final ring in this.rings) {
      for (final p in ring) {
        if (p.lat < minLat) minLat = p.lat;
        if (p.lat > maxLat) maxLat = p.lat;
        if (p.lng < minLng) minLng = p.lng;
        if (p.lng > maxLng) maxLng = p.lng;
      }
    }
    _box = (minLat, maxLat, minLng, maxLng);
  }

  final List<List<GeoPoint>> rings;
  late final (double, double, double, double) _box;

  bool contains(GeoPoint p) {
    final (minLat, maxLat, minLng, maxLng) = _box;
    if (p.lat < minLat || p.lat > maxLat || p.lng < minLng || p.lng > maxLng) {
      return false;
    }
    return rings.any((ring) => _inRing(p, ring));
  }

  /// Meters from [p] to the nearest edge, or null when the bounding box is
  /// already farther than [limit].
  double? metersTo(GeoPoint p, double limit) {
    final (minLat, maxLat, minLng, maxLng) = _box;
    final kx = 111320 * math.cos(p.lat * math.pi / 180);
    const ky = 110574.0;
    final dx = p.lng < minLng
        ? (minLng - p.lng) * kx
        : p.lng > maxLng
        ? (p.lng - maxLng) * kx
        : 0.0;
    final dy = p.lat < minLat
        ? (minLat - p.lat) * ky
        : p.lat > maxLat
        ? (p.lat - maxLat) * ky
        : 0.0;
    if (dx > limit || dy > limit) return null;
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        // Flat projection around p; fine over a few hundred meters.
        final ax = (ring[j].lng - p.lng) * kx, ay = (ring[j].lat - p.lat) * ky;
        final bx = (ring[i].lng - p.lng) * kx, by = (ring[i].lat - p.lat) * ky;
        final ex = bx - ax, ey = by - ay;
        final len2 = ex * ex + ey * ey;
        final t = len2 == 0
            ? 0.0
            : (-(ax * ex + ay * ey) / len2).clamp(0.0, 1.0);
        final cx = ax + t * ex, cy = ay + t * ey;
        final d = math.sqrt(cx * cx + cy * cy);
        if (d < best) best = d;
      }
    }
    return best;
  }

  static bool _inRing(GeoPoint p, List<GeoPoint> ring) {
    var hit = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.lat > p.lat) != (b.lat > p.lat) &&
          p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng) {
        hit = !hit;
      }
    }
    return hit;
  }
}

final List<_Shape> _shapes = [for (final o in _outlines) _Shape(o)];
final List<_Shape> _otherShapes = [
  for (final o in _otherOutlines) _Shape([o]),
];

/// The barangay whose boundary holds [point] (PSA's indicative boundaries,
/// bundled so it works offline). Just outside every boundary (an edge, the
/// river, the bay shore), the barangay whose boundary is nearest, if within
/// [withinMeters], the same 50 m the server allows. Null outside Manila and
/// in the two areas that are in no barangay (Tutuban Mall, Manila North
/// Cemetery). The server decides either way.
Barangay? nearestBarangay(GeoPoint point, {double withinMeters = 50}) {
  for (var i = 0; i < _shapes.length; i++) {
    if (_shapes[i].contains(point)) return manilaBarangays[i];
  }
  if (_otherShapes.any((s) => s.contains(point))) return null;
  Barangay? best;
  var bestMeters = withinMeters;
  for (var i = 0; i < _shapes.length; i++) {
    final d = _shapes[i].metersTo(point, bestMeters);
    if (d != null && d <= bestMeters) {
      best = manilaBarangays[i];
      bestMeters = d;
    }
  }
  return best;
}

/// The barangay with this exact name, if it exists.
Barangay? barangayNamed(String name) {
  for (final b in manilaBarangays) {
    if (b.name == name) return b;
  }
  return null;
}
