import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

RoadGraph loadManila() {
  final bytes = File('assets/road_graph/manila_drive_v1.bin').readAsBytesSync();
  return RoadGraph.decode(ByteData.sublistView(bytes));
}

Map<String, Object?> loadReference() => jsonDecode(
  File('test/fixtures/road_graph_reference.json').readAsStringSync(),
) as Map<String, Object?>;

/// A square block with a one-way street:
///
///   0 ---- 1
///   |      |      0→1 and 1→3 are one-way; the rest go both ways.
///   2 ---- 3
RoadGraph block() {
  const nodes = [
    GeoPoint(14.600, 120.980),
    GeoPoint(14.600, 120.990),
    GeoPoint(14.590, 120.980),
    GeoPoint(14.590, 120.990),
  ];
  ({int from, int to, double seconds, double meters, String? name}) e(
    int from,
    int to,
    double seconds, [
    String? name,
  ]) =>
      (from: from, to: to, seconds: seconds, meters: seconds * 10, name: name);
  return RoadGraph.fromEdges(nodes, [
    e(0, 1, 60, 'Top St'),
    e(1, 3, 60, 'East St'),
    e(0, 2, 100, 'West St'),
    e(2, 0, 100, 'West St'),
    e(2, 3, 100, 'Bottom St'),
    e(3, 2, 100, 'Bottom St'),
  ]);
}

void main() {
  group('binary heap', () {
    test('pops in key order, duplicates included', () {
      final rng = math.Random(7);
      final heap = BinaryHeap();
      final keys = [for (var i = 0; i < 500; i++) rng.nextInt(100).toDouble()];
      for (var i = 0; i < keys.length; i++) {
        heap.push(keys[i], i);
      }
      final popped = <double>[];
      while (!heap.isEmpty) {
        final k = heap.minKey;
        final v = heap.pop();
        expect(keys[v], k);
        popped.add(k);
      }
      expect(popped, [...keys]..sort());
    });
  });

  group('dijkstra on a small block', () {
    test('respects one-way streets', () {
      final g = block();
      // 0 to 3: the one-way pair (120 s) beats the two-way side (200 s).
      final from0 = dijkstra(g, 0);
      expect(from0.seconds[3], 120);
      expect(from0.edgesTo(3)!.map((e) => g.targets[e]), [1, 3]);
      // 3 to 0 cannot use the one-ways backwards: 3 → 2 → 0.
      final from3 = dijkstra(g, 3);
      expect(from3.seconds[0], 200);
      // Nothing leaves toward 1 except 0 → 1.
      expect(dijkstra(g, 2).seconds[1], 160);
    });

    test('the reversed graph gives travel times to a node', () {
      final g = block();
      final toThree = dijkstra(g.reversed, 3);
      for (var from = 0; from < 4; from++) {
        expect(toThree.seconds[from], dijkstra(g, from).seconds[3]);
      }
    });

    test('stops early once the targets are settled', () {
      final g = block();
      final paths = dijkstra(g, 0, targets: {1});
      expect(paths.seconds[1], 60);
      expect(paths.reached(2), isFalse);
      expect(paths.edgesTo(2), isNull);
      expect(paths.edgesTo(0), isEmpty);
    });

    test('maxSeconds limits the search', () {
      final paths = dijkstra(block(), 0, maxSeconds: 90);
      expect(paths.reached(1), isTrue);
      expect(paths.reached(3), isFalse);
    });
  });

  group('the Manila road graph', () {
    final graph = loadManila();

    test('decodes', () {
      expect(graph.nodeCount, greaterThan(5000));
      expect(graph.edgeCount, greaterThan(graph.nodeCount));
      expect(graph.names, contains('Taft Avenue'));
      expect(graph.built.year, greaterThanOrEqualTo(2026));
      // Every node sits in or near the City of Manila.
      for (var i = 0; i < graph.nodeCount; i++) {
        expect(graph.lat[i], inInclusiveRange(14.48, 14.70));
        expect(graph.lng[i], inInclusiveRange(120.90, 121.07));
      }
    });

    test('matches networkx on 50 random origin and destination pairs', () {
      final pairs = loadReference()['pairs']! as List;
      expect(pairs, hasLength(50));
      final watch = Stopwatch()..start();
      for (final raw in pairs) {
        final p = raw as Map<String, Object?>;
        final from = p['from']! as int;
        final to = p['to']! as int;
        final expected = (p['seconds']! as num).toDouble();
        final paths = dijkstra(graph, from, targets: {to});
        expect(
          paths.seconds[to],
          closeTo(expected, 1e-6),
          reason: 'from $from to $to',
        );
        // The path's edges add up to the reported time.
        final edges = paths.edgesTo(to)!;
        final sum = edges.fold<double>(0, (s, e) => s + graph.seconds[e]);
        expect(sum, closeTo(expected, 1e-6));
      }
      watch.stop();
      // Informational: printed so Chapter 4 can quote a rough figure.
      // ignore: avoid_print
      print(
        '50 point-to-point runs: ${watch.elapsedMilliseconds} ms '
        '(${graph.nodeCount} nodes, ${graph.edgeCount} edges)',
      );
    });

    test('one reversed run matches networkx for every unit', () {
      final many = loadReference()['toIncident']! as Map<String, Object?>;
      final incident = many['incident']! as int;
      final paths = dijkstra(graph.reversed, incident);
      for (final raw in many['units']! as List) {
        final u = raw as Map<String, Object?>;
        expect(
          paths.seconds[u['from']! as int],
          closeTo((u['seconds']! as num).toDouble(), 1e-6),
        );
      }
    });

    test('every intersection can reach every other one', () {
      final all = dijkstra(graph, 0);
      final back = dijkstra(graph.reversed, 0);
      for (var i = 0; i < graph.nodeCount; i++) {
        expect(all.reached(i) && back.reached(i), isTrue, reason: 'node $i');
      }
    });

    test('nearestNode agrees with a full scan', () {
      final rng = math.Random(3);
      for (var k = 0; k < 40; k++) {
        final p = GeoPoint(
          14.56 + rng.nextDouble() * 0.07,
          120.96 + rng.nextDouble() * 0.06,
        );
        var best = -1;
        var bestMeters = double.infinity;
        for (var i = 0; i < graph.nodeCount; i++) {
          final d = p.distanceTo(graph.pointOf(i));
          if (d < bestMeters) {
            bestMeters = d;
            best = i;
          }
        }
        final snap = graph.nearestNode(p, maxMeters: 5000);
        expect(snap?.meters, closeTo(bestMeters, 1e-9), reason: '$p');
        expect(graph.pointOf(snap!.node).distanceTo(graph.pointOf(best)), 0);
      }
    });

    test('a point far from Manila does not snap', () {
      expect(graph.nearestNode(const GeoPoint(10.3157, 123.8854)), isNull);
    });
  });

  group('routes', () {
    final router = RoadRouter(loadManila());
    // Manila City Hall to the University of Santo Tomas, across the Pasig.
    const cityHall = GeoPoint(14.5896, 120.9811);
    const ust = GeoPoint(14.6096, 120.9894);

    test('a route runs from start to destination along roads', () {
      final route = router.route(cityHall, ust)!;
      expect(route.points.first, cityHall);
      expect(route.points.last, ust);
      final straight = cityHall.distanceTo(ust);
      expect(route.meters, greaterThan(straight));
      expect(route.meters, lessThan(straight * 3));
      // Between 2 and 30 minutes by the provisional speeds.
      expect(route.minutes, inInclusiveRange(2, 30));
      expect(route.steps.first.turn, TurnDirection.depart);
      expect(route.steps.length, greaterThan(1));
      final stepMeters = route.steps.fold<double>(0, (s, x) => s + x.meters);
      expect(stepMeters, lessThanOrEqualTo(route.meters));
      expect(route.computeTime, greaterThan(Duration.zero));
    });

    test('there and back can differ (one-way streets)', () {
      final there = router.route(cityHall, ust)!;
      final back = router.route(ust, cityHall)!;
      expect(there.seconds, isNot(back.seconds));
    });

    test('JSON keeps the route', () {
      final route = router.route(cityHall, ust)!;
      final copy = RoadRoute.fromJson(
        jsonDecode(jsonEncode(route.toJson())) as Map<String, Object?>,
      );
      expect(copy.points.length, route.points.length);
      expect(copy.points.last.distanceTo(ust), lessThan(2));
      expect(copy.seconds, route.seconds.roundToDouble());
      expect(copy.steps.length, route.steps.length);
      expect(copy.graphBuilt, router.graph.built);
    });

    test('no route off the map', () {
      expect(router.route(cityHall, const GeoPoint(10.3157, 123.8854)), isNull);
    });

    test('times to one place from many match point-to-point routes', () {
      final origins = {
        'a': const GeoPoint(14.6040, 120.9730), // Divisoria
        'b': const GeoPoint(14.5764, 120.9830), // Ermita
        'c': const GeoPoint(14.6180, 121.0050), // Sampaloc
      };
      final many = router.timesTo(cityHall, origins);
      for (final entry in origins.entries) {
        final single = router.route(entry.value, cityHall)!;
        expect(many.times[entry.key]!.seconds, closeTo(single.seconds, 1e-6));
        expect(many.times[entry.key]!.meters, closeTo(single.meters, 0.5));
      }
    });
  });

  group('unit suggestions by road', () {
    final graph = loadManila();
    final incident = Incident(
      id: 'INC-1',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.app,
      status: IncidentStatus.confirmed,
      location: const GeoPoint(14.5896, 120.9811),
      barangay: 'Barangay 659',
      district: 'Ermita',
      capturedAt: DateTime(2026, 9, 30, 12),
      receivedAt: DateTime(2026, 9, 30, 12),
    );
    ResponseUnit unit(String id, GeoPoint? at, {UnitStatus? status}) =>
        ResponseUnit(
          id: id,
          callSign: id,
          type: UnitType.rescueTeam,
          station: 'Test',
          crewSize: 4,
          status: status ?? UnitStatus.available,
          location: at,
        );

    test('ranks by road travel time and skips busy units', () async {
      final log = MemoryRoutingLog();
      final suggester = RoadNetworkSuggester(
        () async => RoadRouter(graph),
        onRun: log.log,
        platform: RoutingPlatform.web,
      );
      final ranked = await suggester.suggest(incident, [
        unit('far', const GeoPoint(14.6180, 121.0050)),
        unit('near', const GeoPoint(14.5920, 120.9800)),
        unit(
          'busy',
          const GeoPoint(14.5897, 120.9812),
          status: UnitStatus.enRoute,
        ),
        unit('mid', const GeoPoint(14.6040, 120.9730)),
      ]);
      expect(ranked.map((s) => s.unit.id), ['near', 'mid', 'far']);
      expect(
        ranked.every((s) => s.method == RoutingMethod.roadNetwork),
        isTrue,
      );
      final run = log.runs.single;
      expect(run.kind, RoutingRunKind.suggestions);
      expect(run.platform, RoutingPlatform.web);
      expect(run.incidentId, 'INC-1');
      expect(run.candidates, 3, reason: 'the busy unit is not a candidate');
      expect(run.nodeCount, graph.nodeCount);
      expect(run.computeMs, greaterThan(0));
    });

    test('a unit the graph cannot place falls back to straight line', () async {
      final suggester = RoadNetworkSuggester(() async => RoadRouter(graph));
      final ranked = await suggester.suggest(incident, [
        unit('cebu', const GeoPoint(10.3157, 123.8854)),
        unit('near', const GeoPoint(14.5920, 120.9800)),
      ]);
      expect(ranked.first.unit.id, 'near');
      expect(ranked.first.method, RoutingMethod.roadNetwork);
      expect(ranked.last.method, RoutingMethod.straightLine);
    });

    test('a graph that fails to load falls back for every unit', () async {
      var attempts = 0;
      final suggester = RoadNetworkSuggester(() async {
        attempts++;
        throw const FormatException('broken');
      });
      final ranked = await suggester.suggest(incident, [
        unit('near', const GeoPoint(14.5920, 120.9800)),
      ]);
      expect(ranked.single.method, RoutingMethod.straightLine);
      await suggester.suggest(incident, const []);
      expect(attempts, 2, reason: 'loading is tried again next time');
    });
  });

  group('route helpers and storage', () {
    final router = RoadRouter(loadManila());
    const cityHall = GeoPoint(14.5896, 120.9811);
    const ust = GeoPoint(14.6096, 120.9894);

    test('next turn, distance to it, and the first heading', () {
      final route = router.route(cityHall, ust)!;
      expect(route.nextTurn, route.steps[1]);
      expect(route.metersToNextTurn, greaterThan(route.steps.first.meters));
      expect(route.metersToNextTurn, lessThan(route.meters));
      final bearing = route.initialBearing();
      expect(bearing, inInclusiveRange(0, 360));
    });

    test('an assignment keeps its route through the phone cache', () {
      final route = router.route(cityHall, ust)!;
      final a = Assignment(
        incidentId: 'INC-1',
        offeredAt: DateTime.utc(2026, 9, 30, 12),
        location: ust,
        barangay: 'Barangay 412',
        district: 'Sampaloc',
        channel: ReportChannel.app,
        route: route,
      );
      final copy = Assignment.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>,
      );
      expect(copy.route!.steps.length, route.steps.length);
      expect(copy.route!.points.length, route.points.length);
      expect(copy.copyWith(status: IncidentStatus.enRoute).route, isNotNull);
    });

    test('a broken route from the server is dropped, the job is kept', () {
      final a = Assignment.fromJson({
        'incident_id': 'INC-1',
        'offered_at': '2026-09-30T04:00:00Z',
        'latitude': 14.6,
        'longitude': 120.99,
        'barangay': 'Barangay 412',
        'district': 'Sampaloc',
        'channel': 'app',
        'status': 'assigned',
        'route': {'polyline': 5},
      });
      expect(a.route, isNull);
      expect(a.incidentId, 'INC-1');
    });

    test('the mock keeps the route sent with an assignment', () async {
      final backend = MockBackend(latency: Duration.zero);
      addTearDown(backend.dispose);
      final repo = MockIncidentRepository(backend);
      await MockAuthRepository(
        backend,
      ).signIn(email: 'dispatcher@sagip.test', password: MockSeed.demoPassword);
      final route = router.route(cityHall, ust)!;
      await repo.assignUnit('INC-0147', 'unit-r03', route: route);
      expect(backend.routeFor('INC-0147'), same(route));
    });

    test('the timing log keeps one run per incident a minute', () {
      final inner = MemoryRoutingLog();
      var now = DateTime(2026, 9, 30, 12);
      final log = ThrottledRoutingLog(inner, clock: () => now);
      RoutingRun run(String id, [RoutingRunKind k = RoutingRunKind.route]) =>
          RoutingRun(
            kind: k,
            platform: RoutingPlatform.android,
            computeTime: const Duration(milliseconds: 4),
            incidentId: id,
          );
      log.log(run('A'));
      log.log(run('A'));
      log.log(run('B'));
      log.log(run('A', RoutingRunKind.suggestions));
      expect(inner.runs, hasLength(3));
      now = now.add(const Duration(seconds: 61));
      log.log(run('A'));
      expect(inner.runs, hasLength(4));
    });
  });

  group('polyline', () {
    test('matches the published example', () {
      const points = [
        GeoPoint(38.5, -120.2),
        GeoPoint(40.7, -120.95),
        GeoPoint(43.252, -126.453),
      ];
      expect(encodePolyline(points), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), points);
    });

    test('rejects a cut-off string', () {
      expect(() => decodePolyline('_p~iF~ps|U_'), throwsFormatException);
    });
  });

  test('turns', () {
    expect(turnBetween(0, 5), TurnDirection.straight);
    expect(turnBetween(0, 90), TurnDirection.right);
    expect(turnBetween(0, 270), TurnDirection.left);
    expect(turnBetween(350, 20), TurnDirection.slightRight);
    expect(turnBetween(90, 265), TurnDirection.uTurn);
    expect(turnBetween(180, 40), TurnDirection.sharpLeft);
  });
}
