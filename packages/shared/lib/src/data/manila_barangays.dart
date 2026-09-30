import '../models/account.dart';
import '../models/geo_point.dart';

/// A SAMPLE of Manila's barangays, only the ones the demo data uses.
///
/// The app needs all 897 with their districts, bundled so the picker works
/// offline (plan S4, R5). The Data role supplies that list; replace this
/// constant with it (or load it from an asset) when it arrives. The centers
/// are rough points taken from the demo data, not surveyed boundaries.
const sampleManilaBarangays = <Barangay>[
  Barangay('Barangay 105', 'Tondo', GeoPoint(14.61972, 120.96706)),
  Barangay('Barangay 128', 'Tondo', GeoPoint(14.6258, 120.9718)),
  Barangay('Barangay 287', 'Binondo', GeoPoint(14.6003, 120.9745)),
  Barangay('Barangay 306', 'Quiapo', GeoPoint(14.5990, 120.9840)),
  Barangay('Barangay 412', 'Sampaloc', GeoPoint(14.6091, 120.9925)),
  Barangay('Barangay 461', 'Sampaloc', GeoPoint(14.6075, 120.9985)),
  Barangay('Barangay 490', 'Sampaloc', GeoPoint(14.6123, 120.9968)),
  Barangay('Barangay 560', 'Sampaloc', GeoPoint(14.61103, 121.00012)),
  Barangay('Barangay 649', 'Port Area', GeoPoint(14.5869, 120.9690)),
  Barangay('Barangay 700', 'Malate', GeoPoint(14.5712, 120.9888)),
];

/// The sample barangay whose center is nearest [point], if one is within
/// [withinMeters]. Stands in for a lookup in bundled barangay boundaries;
/// the server decides the barangay either way.
Barangay? nearestBarangay(GeoPoint point, {double withinMeters = 400}) {
  Barangay? best;
  var bestMeters = withinMeters;
  for (final b in sampleManilaBarangays) {
    final c = b.center;
    if (c == null) continue;
    final d = point.distanceTo(c);
    if (d <= bestMeters) {
      best = b;
      bestMeters = d;
    }
  }
  return best;
}
