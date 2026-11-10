import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

// The farthest a map zooms out is all of Manila City (2026-11-10).
void main() {
  // How many pixels a span takes at [zoom] (Web Mercator, 256 px tiles).
  double widthAt(double zoom) =>
      (manilaCityBounds.east - manilaCityBounds.west) /
      360 *
      256 *
      math.pow(2, zoom);

  test('a wide dashboard map: Manila fits, one step out would not', () {
    const size = Size(1376, 800);
    final z = manilaMinZoom(size);
    expect(z, greaterThan(13));
    expect(z, lessThan(15));
    expect(widthAt(z), lessThanOrEqualTo(size.width + 0.5));
  });

  test('a phone map zooms out farther than a wide one', () {
    expect(
      manilaMinZoom(const Size(400, 700)),
      lessThan(manilaMinZoom(const Size(1376, 800))),
    );
  });

  test('never below the floor, and the floor when the size is unknown', () {
    expect(manilaMinZoom(const Size(10, 10)), mapMinZoom);
    expect(manilaMinZoom(Size.infinite), mapMinZoom);
    expect(manilaMinZoom(Size.zero), mapMinZoom);
  });

  test('a start farther out than the limit starts at the limit', () {
    expect(startZoom(12, 13.5), 13.5);
    expect(startZoom(16, 13.5), 16);
  });
}
