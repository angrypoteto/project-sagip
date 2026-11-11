// Dijkstra evaluation for Chapter 4 (Objective 1, FR3, FR10): runs Dijkstra
// the way each part of the system uses it, on the real Manila road graph,
// and writes the results to docs/testing/dijkstra/.
//
// Skipped in normal test runs (it writes files). Run it with:
//   cd packages/shared
//   SAGIP_EVAL=1 flutter test test/dijkstra_evaluation_test.dart
//
// Inputs are public only: the 897 barangay centers (PSA), the ten unit
// stations (OpenStreetMap, supabase/data/manila_units.sql), and the
// networkx reference answers. No incident, resident, or MDRRMD record.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

const _out = '../../docs/testing/dijkstra';

/// The ten stations loaded on the hosted project (manila_units.sql).
const _stations = <String, GeoPoint>{
  'MDR-DELPAN': GeoPoint(14.59884, 120.96576),
  'BFP-PANDACAN': GeoPoint(14.59200, 121.01193),
  'BFP-SNLAZARO': GeoPoint(14.61293, 120.98234),
  'BFP-INTRAMUR': GeoPoint(14.59220, 120.97218),
  'BFP-SNICOLAS': GeoPoint(14.59727, 120.97057),
  'BFP-PACO': GeoPoint(14.58059, 120.98823),
  'BFP-TONDO': GeoPoint(14.60762, 120.96656),
  'BFP-STAANA': GeoPoint(14.58013, 121.00813),
  'BFP-GAGALANG': GeoPoint(14.62459, 120.97304),
  'EMS-SNLAZARO': GeoPoint(14.61307, 120.98217),
};

/// JIT warm-up runs left out of the timing figures.
const _warmUp = 20;

RoadGraph _load() {
  final bytes = File('assets/road_graph/manila_drive_v1.bin').readAsBytesSync();
  return RoadGraph.decode(ByteData.sublistView(bytes));
}

double _ms(Duration d) => d.inMicroseconds / 1000;

Map<String, double> _stats(List<double> xs) {
  final s = [...xs]..sort();
  double q(double p) => s[math.min(s.length - 1, (p * (s.length - 1)).round())];
  return {
    'n': s.length.toDouble(),
    'mean': s.reduce((a, b) => a + b) / s.length,
    'median': q(0.5),
    'p95': q(0.95),
    'min': s.first,
    'max': s.last,
  };
}

String _r(num x, [int d = 2]) => x.toStringAsFixed(d);

/// The node an edge leaves from (the graph is stored as offsets per node).
int _sourceOf(RoadGraph g, int edge) {
  var lo = 0, hi = g.nodeCount - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (g.offsets[mid] <= edge) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

void _csv(String name, List<String> header, List<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.join(','));
  for (final r in rows) {
    b.writeln(
      r
          .map((v) {
            final s = '${v ?? ''}';
            return s.contains(',') ? '"$s"' : s;
          })
          .join(','),
    );
  }
  File('$_out/$name').writeAsStringSync(b.toString());
}

void main() {
  final run = Platform.environment['SAGIP_EVAL'] != null;

  test(
    'Dijkstra evaluation',
    () {
      Directory(_out).createSync(recursive: true);
      final graph = _load();
      final router = RoadRouter(graph);
      const straight = StraightLineSuggester();
      final summary = <String, Object?>{
        'ran_at': DateTime.now().toIso8601String(),
        'machine':
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'dart': Platform.version.split(' ').first,
        'graph': {
          'nodes': graph.nodeCount,
          'edges': graph.edgeCount,
          'built': graph.built.toIso8601String().substring(0, 10),
        },
      };

      // ---------------------------------------------------------------- 1
      // Correctness against networkx (a standard graph library).
      final ref = jsonDecode(
        File('test/fixtures/road_graph_reference.json').readAsStringSync(),
      ) as Map<String, Object?>;
      var pairOk = 0, pairMaxDiff = 0.0;
      final pairs = ref['pairs']! as List;
      for (final raw in pairs) {
        final p = raw as Map<String, Object?>;
        final to = p['to']! as int;
        final got = dijkstra(
          graph,
          p['from']! as int,
          targets: {to},
        ).seconds[to];
        final diff = (got - (p['seconds']! as num).toDouble()).abs();
        pairMaxDiff = math.max(pairMaxDiff, diff);
        if (diff < 1e-6) pairOk++;
      }
      final many = ref['toIncident']! as Map<String, Object?>;
      final rev = dijkstra(graph.reversed, many['incident']! as int);
      var unitOk = 0;
      final unitRefs = many['units']! as List;
      for (final raw in unitRefs) {
        final u = raw as Map<String, Object?>;
        if ((rev.seconds[u['from']! as int] - (u['seconds']! as num)).abs() <
            1e-6) {
          unitOk++;
        }
      }
      summary['correctness'] = {
        'networkx_pairs': pairs.length,
        'networkx_pairs_matched': pairOk,
        'networkx_max_difference_seconds': pairMaxDiff,
        'networkx_units': unitRefs.length,
        'networkx_units_matched': unitOk,
      };
      expect(pairOk, pairs.length);
      expect(unitOk, unitRefs.length);

      // ---------------------------------------------------------------- 2
      // Unit suggestions on the dashboard (FR3): one reversed run from each
      // incident point to all ten stations; the unit by road against the unit
      // nearest in a straight line (what a map and a ruler would pick).
      final incidents = [
        for (final b in manilaBarangays)
          if (b.center != null) b,
      ];
      final sugRows = <List<Object?>>[];
      final sugMs = <double>[];
      var samePick = 0, routed = 0, sameTop3 = 0;
      final savedSec = <double>[], savedPct = <double>[];
      final etaDiffMin = <double>[];
      for (final (i, b) in incidents.indexed) {
        final r = router.timesTo(b.center!, _stations);
        if (i >= _warmUp) sugMs.add(_ms(r.computeTime));
        if (r.times.length != _stations.length) continue;
        routed++;
        final byRoad = r.times.entries.toList()
          ..sort((x, y) => x.value.seconds.compareTo(y.value.seconds));
        final byLine = _stations.entries.toList()
          ..sort(
            (x, y) => x.value
                .distanceTo(b.center!)
                .compareTo(y.value.distanceTo(b.center!)),
          );
        final road = byRoad.first, line = byLine.first.key;
        final lineRoadSec = r.times[line]!.seconds;
        if (road.key == line) samePick++;
        if ({for (final e in byRoad.take(3)) e.key}
            .containsAll({for (final e in byLine.take(3)) e.key})) {
          sameTop3++;
        }
        final saved = lineRoadSec - road.value.seconds;
        savedSec.add(saved);
        savedPct.add(saved / lineRoadSec * 100);
        // How far the straight-line ETA (the fallback) is from the road ETA.
        final lineEta = straight.minutesFor(
          _stations[road.key]!.distanceTo(b.center!),
        );
        etaDiffMin.add(lineEta - road.value.seconds / 60);
        sugRows.add([
          b.name,
          b.district,
          road.key,
          _r(road.value.seconds / 60),
          _r(road.value.meters / 1000),
          line,
          _r(lineRoadSec / 60),
          _r(saved / 60),
          _r(lineEta),
          _r(_ms(r.computeTime), 3),
        ]);
      }
      _csv('suggestions.csv', [
        'barangay',
        'district',
        'dijkstra_unit',
        'dijkstra_minutes',
        'dijkstra_km',
        'straight_line_unit',
        'straight_line_unit_road_minutes',
        'minutes_saved',
        'straight_line_eta_minutes',
        'compute_ms',
      ], sugRows);
      final differ = savedSec.where((s) => s > 0.5).toList();
      summary['suggestions'] = {
        'incident_points': incidents.length,
        'all_units_routed': routed,
        'same_first_unit': samePick,
        'same_top3_set': sameTop3,
        'different_first_unit': differ.length,
        'minutes_saved_when_different': _stats([
          for (final s in differ) s / 60,
        ]),
        'percent_saved_when_different': _stats([
          for (var i = 0; i < savedSec.length; i++)
            if (savedSec[i] > 0.5) savedPct[i],
        ]),
        'percent_saved_all_points': _stats(savedPct),
        'straight_line_eta_minus_road_eta_minutes': _stats(etaDiffMin),
        'compute_ms': _stats(sugMs),
      };
      expect(
        savedSec.every((s) => s >= -1e-6),
        isTrue,
        reason: 'the unit picked by road is never slower by road',
      );

      // ---------------------------------------------------------------- 3
      // The route on dispatch (dashboard drawer) and on the responder's phone
      // (navigation): from the suggested unit's station to the incident.
      final routeRows = <List<Object?>>[];
      final routeMs = <double>[];
      final detour = <double>[];
      var continuous = 0, endsRight = 0, matchesSuggestion = 0, total = 0;
      for (final (i, row) in sugRows.indexed) {
        final b = incidents.firstWhere((x) => x.name == row[0]);
        final unit = row[2]! as String;
        final from = _stations[unit]!;
        final route = router.route(from, b.center!)!;
        if (i >= _warmUp) routeMs.add(_ms(route.computeTime));
        total++;
        // The edges join up, start at the station's corner, end at the
        // incident's corner.
        final a = graph.nearestNode(from)!.node;
        final z = graph.nearestNode(b.center!)!.node;
        final edges = dijkstra(graph, a, targets: {z}).edgesTo(z)!;
        var ok = edges.isEmpty || _sourceOf(graph, edges.first) == a;
        for (var k = 1; k < edges.length && ok; k++) {
          ok = _sourceOf(graph, edges[k]) == graph.targets[edges[k - 1]];
        }
        if (ok) continuous++;
        if (route.points.first == from && route.points.last == b.center) {
          endsRight++;
        }
        // The ETA on the route equals the ETA the suggestion showed.
        final sugMin = double.parse(row[3]! as String);
        if ((route.seconds / 60 - sugMin).abs() < 0.01) matchesSuggestion++;
        final line = from.distanceTo(b.center!);
        if (line > 200) detour.add(route.meters / line);
        routeRows.add([
          b.name,
          unit,
          _r(route.seconds / 60),
          _r(route.meters / 1000),
          _r(line / 1000),
          route.steps.length,
          route.points.length,
          _r(_ms(route.computeTime), 3),
        ]);
      }
      _csv('routes.csv', [
        'barangay',
        'from_unit',
        'minutes',
        'road_km',
        'straight_km',
        'turn_steps',
        'map_points',
        'compute_ms',
      ], routeRows);
      summary['routes'] = {
        'routes': total,
        'edges_join_up': continuous,
        'start_and_end_at_the_right_points': endsRight,
        'eta_equals_suggestion': matchesSuggestion,
        'road_over_straight_distance': _stats(detour),
        'minutes': _stats([
          for (final r in routeRows) double.parse(r[2]! as String),
        ]),
        'compute_ms': _stats(routeMs),
      };
      expect(continuous, total);
      expect(endsRight, total);

      // ---------------------------------------------------------------- 4
      // Re-routing as the responder drives (phone): from points along the
      // route. A part of a shortest path is itself a shortest path, so the
      // time left must equal the total minus the time already driven.
      final rerouteMs = <double>[];
      var reroutes = 0, consistent = 0;
      final rng = math.Random(42);
      for (var k = 0; k < 100; k++) {
        final b = incidents[rng.nextInt(incidents.length)];
        final from = _stations.values.elementAt(rng.nextInt(_stations.length));
        final a = graph.nearestNode(from)!.node;
        final z = graph.nearestNode(b.center!)!.node;
        final full = dijkstra(graph, a, targets: {z});
        final edges = full.edgesTo(z)!;
        for (var e = 5; e < edges.length; e += 5) {
          final node = graph.targets[edges[e - 1]];
          final watch = Stopwatch()..start();
          final again = router.route(graph.pointOf(node), b.center!);
          watch.stop();
          reroutes++;
          if (reroutes > _warmUp) rerouteMs.add(_ms(watch.elapsed));
          final left = dijkstra(graph, node, targets: {z}).seconds[z];
          if ((left - (full.seconds[z] - full.seconds[node])).abs() < 1e-6 &&
              again != null) {
            consistent++;
          }
        }
      }
      summary['rerouting'] = {
        'reroutes': reroutes,
        'time_left_consistent': consistent,
        'compute_ms': _stats(rerouteMs),
      };
      expect(consistent, reroutes);

      // ---------------------------------------------------------------- 5
      // Routing around a confirmed flood or fire (FR10): put the hazard in the
      // middle of the fastest dry route and route again.
      final hazardRows = <List<Object?>>[];
      final hazardSummary = <String, Object?>{};
      for (final type in [IncidentType.flood, IncidentType.fire]) {
        var tried = 0, avoided = 0;
        final savedMin = <double>[], extraKm = <double>[], ms = <double>[];
        final rng2 = math.Random(type.index + 7);
        while (tried < 100) {
          final b = incidents[rng2.nextInt(incidents.length)];
          final from = _stations.values.elementAt(
            rng2.nextInt(_stations.length),
          );
          final a = graph.nearestNode(from)!.node;
          final z = graph.nearestNode(b.center!)!.node;
          final dry = dijkstra(graph, a, targets: {z});
          final dryEdges = dry.edgesTo(z)!;
          final dryMeters = dryEdges.fold<double>(
            0,
            (s, e) => s + graph.meters[e],
          );
          if (dryMeters < 1500 || dryEdges.length < 6) continue;
          final mid = graph.pointOf(
            graph.targets[dryEdges[dryEdges.length ~/ 2]],
          );
          if (mid.distanceTo(graph.pointOf(a)) < 400 ||
              mid.distanceTo(graph.pointOf(z)) < 400) {
            continue;
          }
          tried++;
          final penalty = HazardPenalty([HazardZone(mid, type)]);
          final watch = Stopwatch()..start();
          final w = penalty.weightsFor(graph)!;
          final wet = dijkstra(graph, a, targets: {z}, weights: w);
          watch.stop();
          ms.add(_ms(watch.elapsed));
          final wetEdges = wet.edgesTo(z)!;
          final throughHazard = dryEdges.fold<double>(0, (s, e) => s + w[e]);
          final clear = wetEdges.every((e) => w[e] == graph.seconds[e]);
          if (clear) avoided++;
          final wetMeters = wetEdges.fold<double>(
            0,
            (s, e) => s + graph.meters[e],
          );
          savedMin.add((throughHazard - wet.seconds[z]) / 60);
          extraKm.add((wetMeters - dryMeters) / 1000);
          hazardRows.add([
            type.name,
            b.name,
            _r(dry.seconds[z] / 60),
            _r(throughHazard / 60),
            _r(wet.seconds[z] / 60),
            clear ? 'yes' : 'no',
            _r((wetMeters - dryMeters) / 1000),
            _r(ms.last, 3),
          ]);
          expect(wet.seconds[z], lessThanOrEqualTo(throughHazard + 1e-6));
        }
        hazardSummary[type.name] = {
          'cases': tried,
          'route_avoids_the_zone': avoided,
          'radius_m': HazardZone(const GeoPoint(0, 0), type).radiusMeters,
          'slow_down_factor': HazardZone(const GeoPoint(0, 0), type).factor,
          'minutes_saved_vs_driving_through': _stats(savedMin),
          'extra_km': _stats(extraKm),
          'compute_ms_with_penalty': _stats(ms),
        };
      }
      _csv('hazards.csv', [
        'hazard',
        'barangay',
        'dry_minutes',
        'through_hazard_minutes',
        'around_minutes',
        'avoids_zone',
        'extra_km',
        'compute_ms',
      ], hazardRows);
      summary['hazards'] = hazardSummary;

      // ---------------------------------------------------------------- 6
      // The worst case: a full search over the whole graph (no early stop).
      final fullMs = <double>[];
      for (var k = 0; k < 50; k++) {
        final w = Stopwatch()..start();
        dijkstra(graph, rng.nextInt(graph.nodeCount));
        w.stop();
        if (k >= 5) fullMs.add(_ms(w.elapsed));
      }
      summary['full_graph_search_ms'] = _stats(fullMs);

      File(
        '$_out/summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: run
        ? false
        : 'set SAGIP_EVAL=1 to run (writes docs/testing/dijkstra)',
  );
}
