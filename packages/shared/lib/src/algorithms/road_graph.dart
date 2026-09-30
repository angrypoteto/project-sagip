import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/geo_point.dart';

/// The directed Manila road graph (plan 10.2): intersections as nodes, road
/// segments as edges, one edge per allowed direction, weighted by estimated
/// travel time.
///
/// Built from OpenStreetMap by `ml/road_graph/build_road_graph.py` and
/// bundled as `assets/road_graph/manila_drive_v1.bin`. Edges are stored in
/// compressed sparse rows: node `i`'s outgoing edges are
/// `offsets[i] .. offsets[i + 1] - 1`.
class RoadGraph {
  RoadGraph._({
    required this.built,
    required this.lat,
    required this.lng,
    required this.offsets,
    required this.targets,
    required this.seconds,
    required this.meters,
    required this.nameIndex,
    required this.roadClass,
    required this.shapeOffsets,
    required this.shape,
    required this.names,
    required this.edgeOfReversed,
  });

  /// The graph file's asset key, for `rootBundle.load`.
  static const assetKey =
      'packages/sagip_shared/assets/road_graph/manila_drive_v1.bin';

  static const noName = 0xFFFF;

  /// When the graph was built from OpenStreetMap.
  final DateTime built;

  final Float64List lat;
  final Float64List lng;
  final Uint32List offsets;
  final Uint32List targets;

  /// Travel time of each edge in seconds.
  final Float32List seconds;

  /// Length of each edge in meters.
  final Float32List meters;

  /// Index into [names], or [noName].
  final Uint16List nameIndex;

  /// OSM road class code (1 motorway ... 8 living street, 9 other).
  final Uint8List roadClass;

  /// The edge's shape between its two ends: points
  /// `shapeOffsets[e] .. shapeOffsets[e + 1] - 1` of [shape] (lat, lng pairs).
  final Uint32List shapeOffsets;
  final Float64List shape;

  final List<String> names;

  /// For a reversed graph: the edge in the original graph that each edge
  /// came from. Null for the original.
  final Uint32List? edgeOfReversed;

  int get nodeCount => lat.length;
  int get edgeCount => targets.length;

  GeoPoint pointOf(int node) => GeoPoint(lat[node], lng[node]);

  String? nameOf(int edge) {
    final i = nameIndex[edge];
    return i == noName ? null : names[i];
  }

  /// Reads the file written by `build_road_graph.py` (format version 1).
  factory RoadGraph.decode(ByteData data) {
    var pos = 0;
    int u32() {
      final v = data.getUint32(pos, Endian.little);
      pos += 4;
      return v;
    }

    int i32() {
      final v = data.getInt32(pos, Endian.little);
      pos += 4;
      return v;
    }

    const magic = 'SAGIPRG1';
    for (var i = 0; i < magic.length; i++) {
      if (data.getUint8(i) != magic.codeUnitAt(i)) {
        throw const FormatException('Not a S.A.G.I.P. road graph file.');
      }
    }
    pos = magic.length;
    final version = u32();
    if (version != 1) {
      throw FormatException('Road graph version $version is not supported.');
    }
    final builtRaw = u32();
    final n = u32();
    final m = u32();
    final k = u32();
    final g = u32();

    final lat = Float64List(n);
    final lng = Float64List(n);
    for (var i = 0; i < n; i++) {
      lat[i] = i32() / 1e6;
      lng[i] = i32() / 1e6;
    }
    final offsets = Uint32List(n + 1);
    for (var i = 0; i <= n; i++) {
      offsets[i] = u32();
    }
    final targets = Uint32List(m);
    for (var i = 0; i < m; i++) {
      targets[i] = u32();
    }
    final seconds = Float32List(m);
    for (var i = 0; i < m; i++, pos += 4) {
      seconds[i] = data.getFloat32(pos, Endian.little);
    }
    final meters = Float32List(m);
    for (var i = 0; i < m; i++, pos += 4) {
      meters[i] = data.getFloat32(pos, Endian.little);
    }
    final nameIndex = Uint16List(m);
    for (var i = 0; i < m; i++, pos += 2) {
      nameIndex[i] = data.getUint16(pos, Endian.little);
    }
    final roadClass = Uint8List(m);
    for (var i = 0; i < m; i++, pos += 1) {
      roadClass[i] = data.getUint8(pos);
    }
    final shapeOffsets = Uint32List(m + 1);
    for (var i = 0; i <= m; i++) {
      shapeOffsets[i] = u32();
    }
    final shape = Float64List(g * 2);
    for (var i = 0; i < g * 2; i++) {
      shape[i] = i32() / 1e6;
    }
    final names = <String>[];
    for (var i = 0; i < k; i++) {
      final len = data.getUint16(pos, Endian.little);
      pos += 2;
      names.add(
        utf8.decode(data.buffer.asUint8List(data.offsetInBytes + pos, len)),
      );
      pos += len;
    }
    if (pos != data.lengthInBytes) {
      throw const FormatException('Road graph file has trailing bytes.');
    }
    return RoadGraph._(
      built: DateTime(builtRaw ~/ 10000, builtRaw ~/ 100 % 100, builtRaw % 100),
      lat: lat,
      lng: lng,
      offsets: offsets,
      targets: targets,
      seconds: seconds,
      meters: meters,
      nameIndex: nameIndex,
      roadClass: roadClass,
      shapeOffsets: shapeOffsets,
      shape: shape,
      names: names,
      edgeOfReversed: null,
    );
  }

  /// A graph from a plain list of nodes and one-way edges (tests and tools).
  /// Edges have no shape between their ends.
  factory RoadGraph.fromEdges(
    List<GeoPoint> nodes,
    List<({int from, int to, double seconds, double meters, String? name})>
    edges, {
    DateTime? built,
  }) {
    final n = nodes.length;
    final sorted = [...edges]..sort((a, b) => a.from.compareTo(b.from));
    final names = <String>[];
    final offsets = Uint32List(n + 1);
    for (final e in sorted) {
      offsets[e.from + 1]++;
    }
    for (var i = 0; i < n; i++) {
      offsets[i + 1] += offsets[i];
    }
    final m = sorted.length;
    final nameIndex = Uint16List(m);
    for (var i = 0; i < m; i++) {
      final name = sorted[i].name;
      if (name == null) {
        nameIndex[i] = noName;
      } else {
        var at = names.indexOf(name);
        if (at < 0) {
          at = names.length;
          names.add(name);
        }
        nameIndex[i] = at;
      }
    }
    return RoadGraph._(
      built: built ?? DateTime(2026, 9, 30),
      lat: Float64List.fromList([for (final p in nodes) p.lat]),
      lng: Float64List.fromList([for (final p in nodes) p.lng]),
      offsets: offsets,
      targets: Uint32List.fromList([for (final e in sorted) e.to]),
      seconds: Float32List.fromList([for (final e in sorted) e.seconds]),
      meters: Float32List.fromList([for (final e in sorted) e.meters]),
      nameIndex: nameIndex,
      roadClass: Uint8List(m),
      shapeOffsets: Uint32List(m + 1),
      shape: Float64List(0),
      names: names,
      edgeOfReversed: null,
    );
  }

  /// The same roads with every edge turned around. A single Dijkstra run
  /// from an incident on the reversed graph gives every unit's travel time
  /// to that incident (plan 10.2).
  late final RoadGraph reversed = _reverse();

  RoadGraph _reverse() {
    final n = nodeCount;
    final m = edgeCount;
    final counts = Uint32List(n + 1);
    for (var e = 0; e < m; e++) {
      counts[targets[e] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      counts[i + 1] += counts[i];
    }
    final next = Uint32List.fromList(counts);
    final rTargets = Uint32List(m);
    final rSeconds = Float32List(m);
    final rMeters = Float32List(m);
    final rName = Uint16List(m);
    final rClass = Uint8List(m);
    final origin = Uint32List(m);
    for (var u = 0; u < n; u++) {
      for (var e = offsets[u]; e < offsets[u + 1]; e++) {
        final slot = next[targets[e]]++;
        rTargets[slot] = u;
        rSeconds[slot] = seconds[e];
        rMeters[slot] = meters[e];
        rName[slot] = nameIndex[e];
        rClass[slot] = roadClass[e];
        origin[slot] = e;
      }
    }
    return RoadGraph._(
      built: built,
      lat: lat,
      lng: lng,
      offsets: counts,
      targets: rTargets,
      seconds: rSeconds,
      meters: rMeters,
      nameIndex: rName,
      roadClass: rClass,
      shapeOffsets: shapeOffsets,
      shape: shape,
      names: names,
      edgeOfReversed: origin,
    );
  }

  // ------------------------------------------------------------ snapping

  static const double _cellDeg = 0.004; // about 440 m

  late final Map<int, List<int>> _grid = () {
    final grid = <int, List<int>>{};
    for (var i = 0; i < nodeCount; i++) {
      grid.putIfAbsent(_cellKey(_cell(lat[i]), _cell(lng[i])), () => []).add(i);
    }
    return grid;
  }();

  static int _cell(double deg) => (deg / _cellDeg).floor();
  static int _cellKey(int row, int col) => row * 1000003 + col;

  /// The intersection nearest to [p], or null when none is within
  /// [maxMeters] (the point is off the map, for example outside Manila).
  ({int node, double meters})? nearestNode(
    GeoPoint p, {
    double maxMeters = 1000,
  }) {
    final row = _cell(p.lat);
    final col = _cell(p.lng);
    final rings = (maxMeters / (_cellDeg * 111320 * 0.96)).ceil() + 1;
    int? best;
    var bestMeters = double.infinity;
    for (var r = 0; r <= rings; r++) {
      for (var dr = -r; dr <= r; dr++) {
        for (var dc = -r; dc <= r; dc++) {
          if (math.max(dr.abs(), dc.abs()) != r) continue;
          final cell = _grid[_cellKey(row + dr, col + dc)];
          if (cell == null) continue;
          for (final i in cell) {
            final d = p.distanceTo(GeoPoint(lat[i], lng[i]));
            if (d < bestMeters) {
              bestMeters = d;
              best = i;
            }
          }
        }
      }
      // Anything in a farther ring is at least r cells away.
      if (best != null && bestMeters <= r * _cellDeg * 111320 * 0.96) break;
    }
    if (best == null || bestMeters > maxMeters) return null;
    return (node: best, meters: bestMeters);
  }
}
