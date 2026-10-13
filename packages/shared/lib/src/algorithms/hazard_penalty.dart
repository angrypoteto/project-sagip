import 'dart:math' as math;
import 'dart:typed_data';

import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
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
/// longer. Dijkstra stays the same; only the edge weights change.
class HazardPenalty {
  const HazardPenalty(this.zones);

  final List<HazardZone> zones;

  static const none = HazardPenalty([]);

  bool get isEmpty => zones.isEmpty;

  int count(IncidentType type) => zones.where((z) => z.type == type).length;

  /// The incidents a route should avoid: a flood or a fire that is
  /// confirmed (verified), not resolved, not a false report, and not
  /// [except] (the incident being routed to; its own street is where the
  /// unit has to go).
  factory HazardPenalty.fromIncidents(
    Iterable<Incident> incidents, {
    String? except,
  }) => HazardPenalty([
    for (final i in incidents)
      if (HazardZone.slows(i.type) &&
          i.isVerified &&
          i.status != IncidentStatus.resolved &&
          !i.falseReport &&
          i.id != except)
        HazardZone(i.location, i.type!),
  ]);

  /// Each edge's travel time in [graph] with the penalty applied, or null
  /// when no edge is affected (Dijkstra then uses the graph's own times).
  /// A road inside two zones takes the larger factor.
  Float64List? weightsFor(RoadGraph graph) {
    if (zones.isEmpty) return null;
    // A box around each zone: most edges are skipped without the distance.
    final boxes = [
      for (final z in zones)
        (
          z,
          z.radiusMeters / 110574,
          z.radiusMeters / (111320 * math.cos(z.center.lat * math.pi / 180)),
        ),
    ];
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
      other is HazardPenalty && _sameZones(other.zones);

  bool _sameZones(List<HazardZone> other) {
    if (other.length != zones.length) return false;
    for (var i = 0; i < zones.length; i++) {
      if (other[i] != zones[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(zones);
}
