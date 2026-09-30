import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A WGS84 coordinate.
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  static const double _earthRadiusMeters = 6371008.8;

  /// Great-circle distance in meters (haversine formula). DBSCAN and the
  /// straight-line unit ranking both use this.
  double distanceTo(GeoPoint other) {
    final dLat = _rad(other.lat - lat);
    final dLng = _rad(other.lng - lng);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(other.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Initial compass bearing to [other], in degrees from north (0 to 360).
  double bearingTo(GeoPoint other) {
    final lat1 = _rad(lat);
    final lat2 = _rad(other.lat);
    final dLng = _rad(other.lng - lng);
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// A point [fraction] of the way from this point to [other] (0 to 1).
  GeoPoint lerpTo(GeoPoint other, double fraction) => GeoPoint(
    lat + (other.lat - lat) * fraction,
    lng + (other.lng - lng) * fraction,
  );

  static double _rad(double deg) => deg * math.pi / 180;

  factory GeoPoint.fromJson(Map<String, Object?> json) => GeoPoint(
    (json['lat']! as num).toDouble(),
    (json['lng']! as num).toDouble(),
  );

  Map<String, Object?> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}
