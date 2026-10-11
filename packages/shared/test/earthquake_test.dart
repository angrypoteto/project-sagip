import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  test('both limits are inclusive', () {
    final earthquake = Earthquake(
      key: 'test-event',
      occurredAt: DateTime.utc(2026, 10, 11),
      location: 'Test location',
      point: const GeoPoint(0, 0),
      depthKm: 10,
      magnitude: 3.0,
      distanceKm: 200.0,
    );
    expect(earthquake.worthShowing, isTrue);
  });

  test('low magnitude is hidden', () {
    final earthquake = Earthquake(
      key: 'test-event',
      occurredAt: DateTime.utc(2026, 10, 11),
      location: 'Test location',
      point: const GeoPoint(0, 0),
      depthKm: 10,
      magnitude: 2.9,
      distanceKm: 50,
    );
    expect(earthquake.worthShowing, isFalse);
  });

  test('distant earthquake is hidden', () {
    final earthquake = Earthquake(
      key: 'test-event',
      occurredAt: DateTime.utc(2026, 10, 11),
      location: 'Test location',
      point: const GeoPoint(0, 0),
      depthKm: 10,
      magnitude: 6.0,
      distanceKm: 200.1,
    );
    expect(earthquake.worthShowing, isFalse);
  });

  test('limits match the constants', () {
    expect(Earthquake.minMagnitude, 3.0);
    expect(Earthquake.withinKm, 200.0);
  });

  test('missing bulletin URL stays null', () {
    final earthquake = Earthquake.fromJson({
      'event_key': 'test-event',
      'occurred_at': '2026-10-11T00:00:00Z',
      'location': 'Test location',
      'latitude': 0.0,
      'longitude': 0.0,
      'depth_km': 10.0,
      'magnitude': 3.0,
      'distance_km': 200.0,
    });
    expect(earthquake.bulletinUrl, isNull);
  });
}
