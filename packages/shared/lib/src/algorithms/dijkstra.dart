import 'dart:typed_data';

import 'road_graph.dart';

/// A min-priority queue of node ids keyed by travel time, as a binary heap
/// (thesis algorithm parameters: "Use a binary-heap priority queue").
///
/// Dijkstra pushes a node again when it finds a shorter way to it instead of
/// decreasing its key; the older entry is skipped when popped (lazy
/// deletion). That keeps every operation O(log n).
class BinaryHeap {
  final List<double> _keys = [];
  final List<int> _values = [];

  bool get isEmpty => _keys.isEmpty;
  int get length => _keys.length;

  /// The smallest key, without removing it.
  double get minKey => _keys.first;

  void push(double key, int value) {
    _keys.add(key);
    _values.add(value);
    var i = _keys.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_keys[parent] <= key) break;
      _keys[i] = _keys[parent];
      _values[i] = _values[parent];
      i = parent;
    }
    _keys[i] = key;
    _values[i] = value;
  }

  /// Removes and returns the value with the smallest key.
  int pop() {
    final top = _values.first;
    final lastKey = _keys.removeLast();
    final lastValue = _values.removeLast();
    final n = _keys.length;
    if (n > 0) {
      var i = 0;
      while (true) {
        final left = 2 * i + 1;
        if (left >= n) break;
        final right = left + 1;
        final child = right < n && _keys[right] < _keys[left] ? right : left;
        if (_keys[child] >= lastKey) break;
        _keys[i] = _keys[child];
        _values[i] = _values[child];
        i = child;
      }
      _keys[i] = lastKey;
      _values[i] = lastValue;
    }
    return top;
  }
}

/// The result of one Dijkstra run from [source]: the travel time to every
/// node it settled, and the edge used to reach each one.
class ShortestPaths {
  ShortestPaths._(this.graph, this.source, this.seconds, this._via, this._from);

  final RoadGraph graph;
  final int source;

  /// Travel time in seconds from [source]; infinity when not reached.
  final Float64List seconds;

  /// The edge that reaches each node on its shortest path, and the node it
  /// leaves from; -1 for none.
  final Int32List _via;
  final Int32List _from;

  bool reached(int node) => seconds[node].isFinite;

  /// The edges from [source] to [target], in order. Empty when [target] is
  /// the source; null when it was not reached.
  List<int>? edgesTo(int target) {
    if (!reached(target)) return null;
    final edges = <int>[];
    var node = target;
    while (node != source) {
      edges.add(_via[node]);
      node = _from[node];
    }
    return edges.reversed.toList();
  }
}

/// Dijkstra's shortest paths from [source] over [graph], by travel time.
///
/// Stops early once every node in [targets] is settled (all of them when
/// null), or when the next node is farther than [maxSeconds].
ShortestPaths dijkstra(
  RoadGraph graph,
  int source, {
  Set<int>? targets,
  double maxSeconds = double.infinity,
}) {
  final n = graph.nodeCount;
  final dist = Float64List(n)..fillRange(0, n, double.infinity);
  final via = Int32List(n)..fillRange(0, n, -1);
  final from = Int32List(n)..fillRange(0, n, -1);
  final settled = Uint8List(n);
  var remaining = targets == null ? -1 : targets.length;

  final heap = BinaryHeap();
  dist[source] = 0;
  heap.push(0, source);
  while (!heap.isEmpty) {
    final d = heap.minKey;
    final u = heap.pop();
    if (settled[u] == 1 || d > dist[u]) continue; // stale entry
    if (d > maxSeconds) break;
    settled[u] = 1;
    if (targets != null && targets.contains(u) && --remaining == 0) break;
    for (var e = graph.offsets[u]; e < graph.offsets[u + 1]; e++) {
      final v = graph.targets[e];
      final nd = d + graph.seconds[e];
      if (nd < dist[v]) {
        dist[v] = nd;
        via[v] = e;
        from[v] = u;
        heap.push(nd, v);
      }
    }
  }
  // Nodes found but not settled may still have a shorter way; only settled
  // nodes are final.
  for (var i = 0; i < n; i++) {
    if (settled[i] == 0) dist[i] = double.infinity;
  }
  return ShortestPaths._(graph, source, dist, via, from);
}
