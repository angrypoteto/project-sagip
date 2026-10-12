import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_dashboard/src/features/board/unit_glide.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  // A corner in Sampaloc: 100 m north along one street, then 100 m east
  // along the next.
  const from = GeoPoint(14.6100, 120.9900);
  const corner = GeoPoint(14.6109, 120.9900);
  const to = GeoPoint(14.6109, 120.99093);

  test('around a corner the marker takes the streets', () {
    final way = glidePoints(from, to, [from, corner, to]);
    expect(way, [from, corner, to]);
    expect(pathMeters(way), closeTo(200, 3));
    // Half way it is at the corner, not in the middle of the block.
    final half = pointAlong(way, 0.5);
    expect(half.distanceTo(corner), lessThan(3));
    expect(pointAlong(way, 0), from);
    expect(pointAlong(way, 1), to);
    expect(pointAlong(way, 0.25).lng, from.lng);
  });

  test('a road way that runs to an intersection and back is not used', () {
    // Two positions 30 m apart on one block; the graph's route goes by the
    // corner 100 m away.
    const near = GeoPoint(14.61027, 120.9900);
    expect(glidePoints(from, near, [from, corner, near]), [from, near]);
    // No road way at all (off the graph): straight.
    expect(glidePoints(from, to, null), [from, to]);
    expect(glidePoints(from, to, [from, to]), [from, to]);
  });

  test('a marker on its way arrives after the glide time', () {
    final start = DateTime(2026, 10, 12, 20);
    final glide = UnitGlide(points: [from, corner, to], startedAt: start);
    expect(glide.at(start), from);
    expect(glide.done(start.add(const Duration(seconds: 2))), isFalse);
    expect(
      glide.at(start.add(unitGlideTime ~/ 2)).distanceTo(corner),
      lessThan(3),
    );
    expect(glide.done(start.add(unitGlideTime)), isTrue);
    expect(glide.at(start.add(const Duration(minutes: 1))), to);
  });
}
