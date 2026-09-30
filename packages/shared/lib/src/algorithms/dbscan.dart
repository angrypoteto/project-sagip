import '../models/geo_point.dart';

/// Label for points that belong to no cluster.
const int kDbscanNoise = -1;

/// DBSCAN (Density-Based Spatial Clustering of Applications with Noise) over
/// geographic points, using haversine distance (thesis Chapter 3).
///
/// Returns one label per input point, in input order: a cluster number
/// starting at 0, or [kDbscanNoise].
///
/// A point is a *core point* when at least [minPts] points, itself included,
/// lie within [epsMeters] of it. Clusters grow outward from core points;
/// points reachable from a core point but not core themselves join as
/// *border points*. Everything else is noise. With the thesis values
/// (eps 50 m, minPts 3), three reports within 50 m form a confirmed incident
/// and a lone report stays unverified (FR7).
///
/// This runs in O(n^2), which is fine for the reports of one 60-minute
/// window. The production version runs in the database (plan 10.3).
List<int> dbscan<T>(
  List<T> items, {
  required GeoPoint Function(T item) locate,
  double epsMeters = 50,
  int minPts = 3,
}) {
  const unvisited = -2;
  final points = [for (final item in items) locate(item)];
  final labels = List<int>.filled(points.length, unvisited);

  List<int> neighbours(int i) => [
    for (var j = 0; j < points.length; j++)
      if (points[i].distanceTo(points[j]) <= epsMeters) j,
  ];

  var cluster = 0;
  for (var i = 0; i < points.length; i++) {
    if (labels[i] != unvisited) continue;

    final seeds = neighbours(i);
    if (seeds.length < minPts) {
      labels[i] = kDbscanNoise; // May become a border point later.
      continue;
    }

    labels[i] = cluster;
    final queue = [...seeds]..remove(i);
    while (queue.isNotEmpty) {
      final j = queue.removeLast();
      if (labels[j] == kDbscanNoise) labels[j] = cluster; // Border point.
      if (labels[j] != unvisited) continue;

      labels[j] = cluster;
      final more = neighbours(j);
      if (more.length >= minPts) queue.addAll(more); // j is a core point.
    }
    cluster++;
  }
  return labels;
}
