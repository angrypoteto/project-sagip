import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  test('a barangay radius is its area as a circle, in meters', () {
    // Barangays in Manila are small: tens to a few hundred meters across.
    for (final b in manilaBarangays.take(50)) {
      final r = barangayRadiusMeters(b.name);
      expect(r, isNotNull, reason: b.name);
      expect(r, inInclusiveRange(10, 2000), reason: b.name);
    }
    expect(barangayRadiusMeters('Nowhere'), isNull);
  });
}
