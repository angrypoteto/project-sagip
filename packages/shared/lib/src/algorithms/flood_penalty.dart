import 'dart:math' as math;
import 'dart:typed_data';

import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
import 'road_graph.dart';

/// Roads inside confirmed flood incidents are slower (plan 10.2, "Could":
/// a travel-time penalty for flooded roads), so suggestions and routes go
/// around them when another way is not much longer.
///
/// PROVISIONAL until MDRRMD says how flooding slows its units: a road whose
/// middle lies within [radiusMeters] of a flood takes [factor] times as
/// long. Dijkstra stays the same; only the edge weights change.
class FloodPenalty {
  const FloodPenalty(this.zones, {this.radiusMeters = 150, this.factor = 4});

  /// The centres of the confirmed flood incidents.
  final List<GeoPoint> zones;
  final double radiusMeters;
  final double factor;

  static const none = FloodPenalty([]);

  bool get isEmpty => zones.isEmpty;

  /// The flood incidents a route should avoid: confirmed (verified), not
  /// resolved, not a false report, and not [except] (the incident being
  /// routed to; its own street is where the unit has to go).
  factory FloodPenalty.fromIncidents(
    Iterable<Incident> incidents, {
    String? except,
  }) => FloodPenalty([
    for (final i in incidents)
      if (i.type == IncidentType.flood &&
          i.isVerified &&
          i.status != IncidentStatus.resolved &&
          !i.falseReport &&
          i.id != except)
        i.location,
  ]);

  /// Each edge's travel time in [graph] with the penalty applied, or null
  /// when no edge is affected (Dijkstra then uses the graph's own times).
  Float64List? weightsFor(RoadGraph graph) {
    if (zones.isEmpty) return null;
    // A box around each zone: most edges are skipped without the distance.
    final dLat = radiusMeters / 110574;
    final boxes = [
      for (final z in zones)
        (z, dLat, radiusMeters / (111320 * math.cos(z.lat * math.pi / 180))),
    ];
    Float64List? out;
    for (var u = 0; u < graph.nodeCount; u++) {
      for (var e = graph.offsets[u]; e < graph.offsets[u + 1]; e++) {
        final v = graph.targets[e];
        final mid = GeoPoint(
          (graph.lat[u] + graph.lat[v]) / 2,
          (graph.lng[u] + graph.lng[v]) / 2,
        );
        final hit = boxes.any(
          (b) =>
              (mid.lat - b.$1.lat).abs() <= b.$2 &&
              (mid.lng - b.$1.lng).abs() <= b.$3 &&
              mid.distanceTo(b.$1) <= radiusMeters,
        );
        if (!hit) continue;
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
      other is FloodPenalty &&
      other.radiusMeters == radiusMeters &&
      other.factor == factor &&
      _sameZones(other.zones);

  bool _sameZones(List<GeoPoint> other) {
    if (other.length != zones.length) return false;
    for (var i = 0; i < zones.length; i++) {
      if (other[i] != zones[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(radiusMeters, factor, Object.hashAll(zones));
}
