import 'package:flutter/foundation.dart';

import '../algorithms/polyline.dart';
import 'geo_point.dart';

/// Which way to go at the start of a route step.
enum TurnDirection {
  depart,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
}

/// One stretch of a route along the same street.
@immutable
class RouteStep {
  const RouteStep({
    required this.turn,
    required this.street,
    required this.meters,
    required this.seconds,
    required this.start,
  });

  final TurnDirection turn;

  /// The street's name from OpenStreetMap; null for unnamed roads.
  final String? street;
  final double meters;
  final double seconds;

  /// Where the step starts.
  final GeoPoint start;

  factory RouteStep.fromJson(Map<String, Object?> json) => RouteStep(
    turn: TurnDirection.values.byName(json['turn']! as String),
    street: json['street'] as String?,
    meters: (json['meters']! as num).toDouble(),
    seconds: (json['seconds']! as num).toDouble(),
    start: GeoPoint.fromJson((json['start']! as Map).cast<String, Object?>()),
  );

  Map<String, Object?> toJson() => {
    'turn': turn.name,
    'street': street,
    'meters': meters.roundToDouble(),
    'seconds': seconds.roundToDouble(),
    'start': start.toJson(),
  };
}

/// A road route from a unit to an incident (FR3), found by Dijkstra over
/// the OSM road graph. Stored on the dispatch record (`dispatch.route` and
/// `route_plan`) and cached on the responder's phone.
@immutable
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.seconds,
    required this.meters,
    required this.steps,
    required this.computeTime,
    required this.graphBuilt,
  });

  /// The route's shape, from the start point to the destination.
  final List<GeoPoint> points;

  /// Estimated travel time, including the short legs between each end and
  /// the nearest intersection.
  final double seconds;
  final double meters;
  final List<RouteStep> steps;

  /// How long Dijkstra took (the thesis's T_end minus T_start), for
  /// Chapter 4.
  final Duration computeTime;

  /// When the road graph was built from OpenStreetMap.
  final DateTime graphBuilt;

  double get minutes => seconds / 60;

  /// The first turn after the street the route starts on; null when the
  /// destination is on the same street.
  RouteStep? get nextTurn => steps.length > 1 ? steps[1] : null;

  /// Distance from the start to [nextTurn] (or to the end of the only step).
  double get metersToNextTurn {
    if (steps.isEmpty) return meters;
    return points.first.distanceTo(steps.first.start) + steps.first.meters;
  }

  /// The direction of travel at the start, in degrees from north: toward
  /// the first route point at least [ahead] meters away.
  double initialBearing({double ahead = 15}) {
    final from = points.first;
    for (final p in points.skip(1)) {
      if (from.distanceTo(p) >= ahead) return from.bearingTo(p);
    }
    return from.bearingTo(points.last);
  }

  factory RoadRoute.fromJson(Map<String, Object?> json) => RoadRoute(
    points: decodePolyline(json['polyline']! as String),
    seconds: (json['seconds']! as num).toDouble(),
    meters: (json['meters']! as num).toDouble(),
    steps: [
      for (final s in (json['steps'] as List? ?? const []))
        RouteStep.fromJson((s as Map).cast<String, Object?>()),
    ],
    computeTime: Duration(
      microseconds: ((json['compute_ms'] as num? ?? 0) * 1000).round(),
    ),
    graphBuilt:
        DateTime.tryParse(json['graph_built'] as String? ?? '') ??
        DateTime(2026),
  );

  Map<String, Object?> toJson() => {
    'polyline': encodePolyline(points),
    'seconds': seconds.roundToDouble(),
    'meters': meters.roundToDouble(),
    'steps': [for (final s in steps) s.toJson()],
    'compute_ms': computeTime.inMicroseconds / 1000,
    'graph_built': dateOnly(graphBuilt),
  };
}

String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What a timed Dijkstra run computed.
enum RoutingRunKind {
  /// One run on the reversed graph that ranks every Available unit.
  suggestions,

  /// One route from a unit to an incident.
  route,
}

/// Where a run happened.
enum RoutingPlatform {
  web,
  android,
  other;

  static RoutingPlatform get current {
    if (kIsWeb) return RoutingPlatform.web;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return RoutingPlatform.android;
    }
    return RoutingPlatform.other;
  }
}

/// One timed Dijkstra run (T_end minus T_start), logged for Chapter 4
/// (plan 10.2; `routing_run` table).
@immutable
class RoutingRun {
  const RoutingRun({
    required this.kind,
    required this.platform,
    required this.computeTime,
    this.incidentId,
    this.candidates,
    this.nodeCount,
    this.edgeCount,
    this.graphBuilt,
    this.at,
  });

  final RoutingRunKind kind;
  final RoutingPlatform platform;
  final Duration computeTime;
  final String? incidentId;

  /// Units ranked (suggestions only).
  final int? candidates;
  final int? nodeCount;
  final int? edgeCount;
  final DateTime? graphBuilt;

  /// When the run finished (the server stamps its own time on Supabase).
  final DateTime? at;

  double get computeMs => computeTime.inMicroseconds / 1000;
}
