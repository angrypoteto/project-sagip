import 'package:sagip_shared/sagip_shared.dart';

// A unit's marker between two positions its crew's phone reported: it
// moves along the streets, not straight across the blocks (Joshua,
// 2026-10-12). The two positions are real; the way between them is the
// road graph's fastest way, an estimate.

/// How long the marker takes from one reported position to the next: a
/// little under the phone's reporting interval, so it has arrived when the
/// next one comes.
const unitGlideTime = Duration(seconds: 4);

/// Shorter than this is GPS jitter: the marker is simply placed.
const unitGlideMinMeters = 8.0;

/// Longer than this is not a drive between two reports (the phone was
/// offline, or the unit was put somewhere else): the marker jumps.
const unitGlideMaxMeters = 900.0;

/// The length of a line through [points], in meters.
double pathMeters(List<GeoPoint> points) {
  var meters = 0.0;
  for (var i = 1; i < points.length; i++) {
    meters += points[i - 1].distanceTo(points[i]);
  }
  return meters;
}

/// The way the marker takes from [from] to [to]: [road] (the road graph's
/// route between them) when it is a plausible drive, otherwise straight.
///
/// The road route goes by the nearest intersections, so for two points on
/// one block it can run to the corner and back; a route much longer than
/// the straight line is that, or a one-way detour, and is not used.
List<GeoPoint> glidePoints(GeoPoint from, GeoPoint to, List<GeoPoint>? road) {
  final straight = from.distanceTo(to);
  if (road == null || road.length < 3) return [from, to];
  return pathMeters(road) <= straight * 1.5 + 15 ? road : [from, to];
}

/// The point a share [t] (0 to 1) of the way along [points], by distance.
GeoPoint pointAlong(List<GeoPoint> points, double t) {
  if (points.length == 1 || t <= 0) return points.first;
  if (t >= 1) return points.last;
  var left = pathMeters(points) * t;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final leg = a.distanceTo(b);
    if (left <= leg) {
      final f = leg == 0 ? 0.0 : left / leg;
      return GeoPoint(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f);
    }
    left -= leg;
  }
  return points.last;
}

/// One marker on its way.
class UnitGlide {
  UnitGlide({required this.points, required this.startedAt});

  /// Straight at first; replaced by the road way once it is worked out.
  List<GeoPoint> points;
  final DateTime startedAt;

  GeoPoint get to => points.last;

  double progress(DateTime now) =>
      (now.difference(startedAt).inMilliseconds / unitGlideTime.inMilliseconds)
          .clamp(0.0, 1.0);

  bool done(DateTime now) => progress(now) >= 1;

  GeoPoint at(DateTime now) => pointAlong(points, progress(now));
}
