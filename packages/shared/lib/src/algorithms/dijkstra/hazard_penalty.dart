import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/enums.dart';
import '../../models/geo_point.dart';
import '../../models/incident.dart';
import '../../models/road_condition.dart';
import 'road_graph.dart';

/// A confirmed flood or fire that roads are slower around.
///
/// PROVISIONAL until MDRRMD says how each slows its units: a road whose
/// middle lies within [radiusMeters] of the hazard takes [factor] times as
/// long. A flooded street can still be driven slowly; the streets at a fire
/// are as good as closed (hoses, cordon), so the factor is much higher and
/// the route only goes through when there is no other way.
class HazardZone {
  const HazardZone(this.center, this.type);

  final GeoPoint center;

  /// [IncidentType.flood] or [IncidentType.fire].
  final IncidentType type;

  double get radiusMeters => type == IncidentType.fire ? 100 : 150;
  double get factor => type == IncidentType.fire ? 20 : 4;

  /// A row of `road_hazards()`; null for a type that does not slow roads or
  /// a row that cannot be read.
  static HazardZone? fromJson(Map<String, dynamic> json) {
    final type = IncidentType.values.asNameMap()[json['type']];
    final lat = json['latitude'], lng = json['longitude'];
    if (type == null || !slows(type) || lat is! num || lng is! num) return null;
    return HazardZone(GeoPoint(lat.toDouble(), lng.toDouble()), type);
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'latitude': center.lat,
    'longitude': center.lng,
  };

  static bool slows(IncidentType? type) =>
      type == IncidentType.flood || type == IncidentType.fire;

  @override
  bool operator ==(Object other) =>
      other is HazardZone && other.center == center && other.type == type;

  @override
  int get hashCode => Object.hash(center, type);
}

/// Roads inside confirmed floods and fires are slower (plan 10.2, "Could":
/// a travel-time penalty for flooded roads; fires added 2026-10-13), so
/// suggestions and routes go around them when another way is not much
/// longer. Since 2026-11-25 the roads TomTom reports as jammed, closed, or
/// flooded are slower too ([roads]). Dijkstra stays the same; only the edge
/// weights change.
class HazardPenalty {
  const HazardPenalty(this.zones, {this.roads = const []});

  final List<HazardZone> zones;

  /// TomTom's jams, closed roads, and flooded roads (migration
  /// road_conditions): a road along one takes [RoadCondition.factor] times
  /// as long.
  final List<RoadCondition> roads;

  static const none = HazardPenalty([]);

  bool get isEmpty => zones.isEmpty && roads.isEmpty;

  int count(IncidentType type) => zones.where((z) => z.type == type).length;

  /// The incidents a route should avoid: a flood or a fire that is
  /// confirmed (verified), not resolved, not a false report, and not
  /// [except] (the incident being routed to; its own street is where the
  /// unit has to go). [roads] are TomTom's slow roads.
  factory HazardPenalty.fromIncidents(
    Iterable<Incident> incidents, {
    String? except,
    List<RoadCondition> roads = const [],
  }) => HazardPenalty([
    for (final i in incidents)
      if (HazardZone.slows(i.type) &&
          i.isVerified &&
          i.status != IncidentStatus.resolved &&
          !i.falseReport &&
          i.id != except)
        HazardZone(i.location, i.type!),
  ], roads: roads);

  /// How far an edge's middle may be from a reported road's line, in
  /// meters, to count as that road.
  static const roadToleranceMeters = 12.0;

  /// Each edge's travel time in [graph] with the penalty applied, or null
  /// when no edge is affected (Dijkstra then uses the graph's own times).
  /// A road inside two zones takes the larger factor.
  Float64List? weightsFor(RoadGraph graph) {
    if (isEmpty) return null;
    // A box around each zone: most edges are skipped without the distance.
    final boxes = [
      for (final z in zones)
        (
          z,
          z.radiusMeters / 110574,
          z.radiusMeters / (111320 * math.cos(z.center.lat * math.pi / 180)),
        ),
    ];
    final lines = roads.isEmpty ? null : _RoadIndex(roads);
    Float64List? out;
    for (var u = 0; u < graph.nodeCount; u++) {
      for (var e = graph.offsets[u]; e < graph.offsets[u + 1]; e++) {
        final v = graph.targets[e];
        final mid = GeoPoint(
          (graph.lat[u] + graph.lat[v]) / 2,
          (graph.lng[u] + graph.lng[v]) / 2,
        );
        var factor = 1.0;
        for (final b in boxes) {
          final z = b.$1;
          if (z.factor > factor &&
              (mid.lat - z.center.lat).abs() <= b.$2 &&
              (mid.lng - z.center.lng).abs() <= b.$3 &&
              mid.distanceTo(z.center) <= z.radiusMeters) {
            factor = z.factor;
          }
        }
        if (lines != null) {
          final f = lines.factorAt(
            graph.lat[u],
            graph.lng[u],
            graph.lat[v],
            graph.lng[v],
          );
          if (f > factor) factor = f;
        }
        if (factor == 1.0) continue;
        out ??= Float64List.fromList([
          for (var i = 0; i < graph.edgeCount; i++) graph.seconds[i],
        ]);
        out[e] = graph.seconds[e] * factor;
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is HazardPenalty &&
      _same(other.zones, zones) &&
      _same(other.roads, roads);

  static bool _same(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(zones), Object.hashAll(roads));
}

/// The reported roads' segments in a grid of about 55 m cells, in local
/// meters around Manila, so each edge looks only at the segments near it.
class _RoadIndex {
  _RoadIndex(List<RoadCondition> roads) {
    for (final r in roads) {
      for (var i = 0; i + 1 < r.path.length; i++) {
        final a = r.path[i], b = r.path[i + 1];
        final s = _segments.length ~/ 5;
        _segments.addAll([
          _x(a.lng),
          _y(a.lat),
          _x(b.lng),
          _y(b.lat),
          r.factor,
        ]);
        final pad = HazardPenalty.roadToleranceMeters;
        final x0 = math.min(_segments[s * 5], _segments[s * 5 + 2]) - pad;
        final x1 = math.max(_segments[s * 5], _segments[s * 5 + 2]) + pad;
        final y0 = math.min(_segments[s * 5 + 1], _segments[s * 5 + 3]) - pad;
        final y1 = math.max(_segments[s * 5 + 1], _segments[s * 5 + 3]) + pad;
        for (var cx = (x0 / _cell).floor(); cx <= (x1 / _cell).floor(); cx++) {
          for (
            var cy = (y0 / _cell).floor();
            cy <= (y1 / _cell).floor();
            cy++
          ) {
            (_cells[_key(cx, cy)] ??= []).add(s);
          }
        }
      }
    }
  }

  static const _cell = 55.0;
  static const _lat0 = 14.6;
  static final _mPerLng = 111320 * math.cos(_lat0 * math.pi / 180);
  static double _x(double lng) => lng * _mPerLng;
  static double _y(double lat) => lat * 110574;
  static int _key(int cx, int cy) => cx * 1000003 + cy;

  final _segments = <double>[];
  final _cells = <int, List<int>>{};

  /// The largest factor of a reported road running along the edge from
  /// (lat1, lng1) to (lat2, lng2): its middle within the tolerance of the
  /// road's line and pointing the same way (within 30 degrees, either
  /// direction), so a cross street is not slowed. 1 when none.
  double factorAt(double lat1, double lng1, double lat2, double lng2) {
    final ax = _x(lng1), ay = _y(lat1), bx = _x(lng2), by = _y(lat2);
    final mx = (ax + bx) / 2, my = (ay + by) / 2;
    final list = _cells[_key((mx / _cell).floor(), (my / _cell).floor())];
    if (list == null) return 1;
    final ex = bx - ax, ey = by - ay;
    final elen = math.sqrt(ex * ex + ey * ey);
    var best = 1.0;
    for (final s in list) {
      final f = _segments[s * 5 + 4];
      if (f <= best) continue;
      final px = _segments[s * 5], py = _segments[s * 5 + 1];
      final qx = _segments[s * 5 + 2], qy = _segments[s * 5 + 3];
      final dx = qx - px, dy = qy - py;
      final len2 = dx * dx + dy * dy;
      double d;
      if (len2 == 0) {
        d = math.sqrt((mx - px) * (mx - px) + (my - py) * (my - py));
      } else {
        final t = (((mx - px) * dx + (my - py) * dy) / len2).clamp(0.0, 1.0);
        final cx = px + t * dx, cy = py + t * dy;
        d = math.sqrt((mx - cx) * (mx - cx) + (my - cy) * (my - cy));
        if (elen > 0 &&
            (ex * dy - ey * dx).abs() / (elen * math.sqrt(len2)) > 0.5) {
          continue;
        }
      }
      if (d <= HazardPenalty.roadToleranceMeters) best = f;
    }
    return best;
  }
}
