import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

// Also run in a browser (`flutter test --platform chrome`): compiled to
// JavaScript, bit operators on negative numbers behave differently.
void main() {
  test("Google's reference example", () {
    const points = [
      GeoPoint(38.5, -120.2),
      GeoPoint(40.7, -120.95),
      GeoPoint(43.252, -126.453),
    ];
    expect(encodePolyline(points), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), points);
  });

  test('steps in every direction survive the round trip', () {
    const ring = [
      GeoPoint(14.60365, 120.96838),
      GeoPoint(14.60411, 120.96801),
      GeoPoint(14.60301, 120.96912),
      GeoPoint(14.60365, 120.96838),
    ];
    expect(decodePolyline(encodePolyline(ring)), ring);
  });

  test('every bundled barangay outline stays inside Manila', () {
    for (final b in manilaBarangays) {
      for (final ring in barangayOutline(b.name)) {
        for (final p in ring) {
          expect(p.lat, inInclusiveRange(14.53, 14.66), reason: b.name);
          expect(p.lng, inInclusiveRange(120.93, 121.03), reason: b.name);
        }
      }
    }
  });
}
