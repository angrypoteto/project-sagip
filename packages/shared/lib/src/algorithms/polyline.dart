import '../models/geo_point.dart';

/// Encodes points with the Encoded Polyline Algorithm (precision 1e-5, about
/// 1 m), the compact form routes are stored in (plan 10.2).
String encodePolyline(List<GeoPoint> points) {
  final out = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;
  for (final p in points) {
    final lat = (p.lat * 1e5).round();
    final lng = (p.lng * 1e5).round();
    _encodeValue(lat - prevLat, out);
    _encodeValue(lng - prevLng, out);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}

// Arithmetic instead of `~` and `<<` on negative numbers: compiled to
// JavaScript (the dashboard), Dart's bit operators give unsigned 32-bit
// results, which turned every negative step into a jump of about 43,000
// degrees.
void _encodeValue(int value, StringBuffer out) {
  var v = value < 0 ? -2 * value - 1 : 2 * value;
  while (v >= 0x20) {
    out.writeCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  out.writeCharCode(v + 63);
}

/// The reverse of [encodePolyline]. Throws [FormatException] on bad input.
List<GeoPoint> decodePolyline(String encoded) {
  final points = <GeoPoint>[];
  var i = 0;
  var lat = 0;
  var lng = 0;
  int next() {
    var result = 0;
    var shift = 0;
    int b;
    do {
      if (i >= encoded.length) {
        throw const FormatException('Polyline ends in the middle of a value.');
      }
      b = encoded.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (i < encoded.length) {
    lat += next();
    lng += next();
    points.add(GeoPoint(lat / 1e5, lng / 1e5));
  }
  return points;
}
