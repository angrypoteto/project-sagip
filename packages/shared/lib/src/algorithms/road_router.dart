import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/geo_point.dart';
import '../models/incident.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import 'dijkstra.dart';
import 'polyline.dart';
import 'road_graph.dart';
import 'unit_suggester.dart';

/// Loads the bundled Manila road graph (about 0.9 MB) and builds a router.
Future<RoadRouter> loadManilaRouter([AssetBundle? bundle]) async {
  final data = await (bundle ?? rootBundle).load(RoadGraph.assetKey);
  return RoadRouter(RoadGraph.decode(data));
}

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

/// A road route from a unit to an incident (FR3), found by Dijkstra.
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
    graphBuilt: DateTime.parse(json['graph_built']! as String),
  );

  Map<String, Object?> toJson() => {
    'polyline': encodePolyline(points),
    'seconds': seconds.roundToDouble(),
    'meters': meters.roundToDouble(),
    'steps': [for (final s in steps) s.toJson()],
    'compute_ms': computeTime.inMicroseconds / 1000,
    'graph_built':
        '${graphBuilt.year.toString().padLeft(4, '0')}-'
        '${graphBuilt.month.toString().padLeft(2, '0')}-'
        '${graphBuilt.day.toString().padLeft(2, '0')}',
  };
}

/// Routes over the road graph between any two points in Manila.
///
/// A point is joined to its nearest intersection by a short straight leg at
/// [accessSpeedKmh]. Points more than [maxSnapMeters] from any road get no
/// route (the caller falls back to straight-line estimates).
class RoadRouter {
  RoadRouter(this.graph, {this.accessSpeedKmh = 15, this.maxSnapMeters = 1000});

  final RoadGraph graph;
  final double accessSpeedKmh;
  final double maxSnapMeters;

  double _accessSeconds(double meters) => meters / (accessSpeedKmh / 3.6);

  /// The fastest route from [from] to [to], or null when either end is off
  /// the road graph.
  RoadRoute? route(GeoPoint from, GeoPoint to) {
    final watch = Stopwatch()..start();
    final a = graph.nearestNode(from, maxMeters: maxSnapMeters);
    final b = graph.nearestNode(to, maxMeters: maxSnapMeters);
    if (a == null || b == null) return null;
    final paths = dijkstra(graph, a.node, targets: {b.node});
    final edges = paths.edgesTo(b.node);
    watch.stop();
    if (edges == null) return null;

    final points = <GeoPoint>[from, graph.pointOf(a.node)];
    var meters = a.meters + b.meters;
    for (final e in edges) {
      _appendShape(e, points);
      meters += graph.meters[e];
    }
    points.add(to);
    return RoadRoute(
      points: _dedupe(points),
      seconds:
          paths.seconds[b.node] +
          _accessSeconds(a.meters) +
          _accessSeconds(b.meters),
      meters: meters,
      steps: _steps(edges, a.node),
      computeTime: watch.elapsed,
      graphBuilt: graph.built,
    );
  }

  /// Travel time in seconds from each of [origins] to [destination], from a
  /// single Dijkstra run on the reversed graph (plan 10.2). Origins off the
  /// road graph are left out.
  ({Map<K, ({double seconds, double meters})> times, Duration computeTime})
  timesTo<K>(GeoPoint destination, Map<K, GeoPoint> origins) {
    final watch = Stopwatch()..start();
    final dest = graph.nearestNode(destination, maxMeters: maxSnapMeters);
    final times = <K, ({double seconds, double meters})>{};
    if (dest == null) return (times: times, computeTime: watch.elapsed);

    final starts = <K, ({int node, double meters})>{};
    for (final entry in origins.entries) {
      final snap = graph.nearestNode(entry.value, maxMeters: maxSnapMeters);
      if (snap != null) starts[entry.key] = snap;
    }
    final reversed = graph.reversed;
    final paths = dijkstra(
      reversed,
      dest.node,
      targets: {for (final s in starts.values) s.node},
    );
    for (final entry in starts.entries) {
      final node = entry.value.node;
      final edges = paths.edgesTo(node);
      if (edges == null) continue;
      var meters = entry.value.meters + dest.meters;
      for (final e in edges) {
        meters += reversed.meters[e];
      }
      times[entry.key] = (
        seconds:
            paths.seconds[node] +
            _accessSeconds(entry.value.meters) +
            _accessSeconds(dest.meters),
        meters: meters,
      );
    }
    watch.stop();
    return (times: times, computeTime: watch.elapsed);
  }

  void _appendShape(int edge, List<GeoPoint> out) {
    for (
      var i = graph.shapeOffsets[edge];
      i < graph.shapeOffsets[edge + 1];
      i++
    ) {
      out.add(GeoPoint(graph.shape[2 * i], graph.shape[2 * i + 1]));
    }
    out.add(graph.pointOf(graph.targets[edge]));
  }

  static List<GeoPoint> _dedupe(List<GeoPoint> points) => [
    for (var i = 0; i < points.length; i++)
      if (i == 0 || points[i] != points[i - 1]) points[i],
  ];

  /// Groups the route's edges into steps along the same street, with the
  /// turn at the start of each.
  List<RouteStep> _steps(List<int> edges, int sourceNode) {
    final steps = <RouteStep>[];
    var tail = sourceNode;
    String? street;
    var meters = 0.0;
    var seconds = 0.0;
    var turn = TurnDirection.depart;
    GeoPoint? start;
    double? lastBearing;

    void flush() {
      final at = start;
      if (at == null) return;
      steps.add(
        RouteStep(
          turn: turn,
          street: street,
          meters: meters,
          seconds: seconds,
          start: at,
        ),
      );
    }

    for (final e in edges) {
      final shape = <GeoPoint>[];
      _appendShape(e, shape);
      final from = graph.pointOf(tail);
      final name = graph.nameOf(e);
      if (start == null || name != street) {
        flush();
        final previous = lastBearing;
        turn = previous == null
            ? TurnDirection.depart
            : turnBetween(previous, from.bearingTo(shape.first));
        street = name;
        meters = 0;
        seconds = 0;
        start = from;
      }
      meters += graph.meters[e];
      seconds += graph.seconds[e];
      final beforeLast = shape.length > 1 ? shape[shape.length - 2] : from;
      lastBearing = beforeLast.bearingTo(shape.last);
      tail = graph.targets[e];
    }
    flush();
    return steps;
  }
}

/// The turn from travelling at [fromBearing] to [toBearing] (degrees).
TurnDirection turnBetween(double fromBearing, double toBearing) {
  final d = ((toBearing - fromBearing + 540) % 360) - 180; // -180 .. 180
  final a = d.abs();
  if (a < 20) return TurnDirection.straight;
  if (a > 160) return TurnDirection.uTurn;
  if (d < 0) {
    if (a < 45) return TurnDirection.slightLeft;
    if (a < 120) return TurnDirection.left;
    return TurnDirection.sharpLeft;
  }
  if (a < 45) return TurnDirection.slightRight;
  if (a < 120) return TurnDirection.right;
  return TurnDirection.sharpRight;
}

/// Ranks Available units by road travel time to the incident: one Dijkstra
/// run from the incident on the reversed road graph (FR3, plan 10.2).
///
/// Units the road graph cannot place, and every unit when the graph fails
/// to load, fall back to [fallback] (straight-line estimates, labelled as
/// such in the UI).
class RoadNetworkSuggester implements UnitSuggester {
  RoadNetworkSuggester(
    this._loadRouter, {
    this.fallback = const StraightLineSuggester(),
    this.onRun,
  });

  final Future<RoadRouter> Function() _loadRouter;
  final StraightLineSuggester fallback;

  /// Called after every routing run with its execution time, for the
  /// Chapter 4 timing log.
  final void Function(Incident incident, Duration computeTime)? onRun;

  Future<RoadRouter>? _router;

  @override
  Future<List<UnitSuggestion>> suggest(
    Incident incident,
    List<ResponseUnit> units, {
    int limit = 3,
  }) async {
    final candidates = [
      for (final u in units)
        if (u.isDispatchable && u.location != null) u,
    ];
    RoadRouter router;
    try {
      router = await (_router ??= _loadRouter());
    } catch (_) {
      _router = null; // try again next time
      return fallback.suggest(incident, units, limit: limit);
    }

    final result = router.timesTo(incident.location, {
      for (final u in candidates) u.id: u.location!,
    });
    onRun?.call(incident, result.computeTime);
    final ranked = <UnitSuggestion>[
      for (final u in candidates)
        if (result.times[u.id] case final t?)
          UnitSuggestion(
            unit: u,
            etaMinutes: t.seconds / 60,
            distanceKm: t.meters / 1000,
            method: RoutingMethod.roadNetwork,
          ),
    ];
    final unrouted = [
      for (final u in candidates)
        if (!result.times.containsKey(u.id)) u,
    ];
    if (unrouted.isNotEmpty) {
      ranked.addAll(
        await fallback.suggest(incident, unrouted, limit: unrouted.length),
      );
    }
    ranked.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return ranked.take(limit).toList();
  }
}
