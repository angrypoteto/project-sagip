import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

RiverLevel station(
  String name,
  double level, {
  double? alert = 12,
  double? alarm = 12.5,
  double? critical = 13,
  DateTime? at,
}) => RiverLevel(
  code: name,
  name: name,
  point: const GeoPoint(14.5953, 120.9697),
  observedAt: at ?? DateTime.utc(2026, 10, 11, 3, 20),
  levelM: level,
  alertM: alert,
  alarmM: alarm,
  criticalM: critical,
);

void main() {
  test('the state is the highest level the water has reached', () {
    expect(station('a', 11.99).state, RiverState.normal);
    expect(station('a', 12).state, RiverState.alert);
    expect(station('a', 12.5).state, RiverState.alarm);
    expect(station('a', 13.4).state, RiverState.critical);
    expect(station('a', 13.4).reachedM, 13);
    expect(station('a', 12.2).reachedM, 12);
    expect(station('a', 11).raised, isFalse);
    expect(station('a', 12).raised, isTrue);
  });

  test('a station with no levels has no state and is never raised', () {
    final s = station('a', 99, alert: null, alarm: null, critical: null);
    expect(s.state, isNull);
    expect(s.raised, isFalse);
    expect(s.reachedM, isNull);
  });

  test('a missing alarm or critical level is never reached', () {
    expect(
      station('a', 50, alarm: null, critical: null).state,
      RiverState.alert,
    );
  });

  test('raised stations come first, highest first, then by name', () {
    final sorted = sortedRiverLevels([
      station('Pandacan', 10),
      station('Angono', 10, alert: null),
      station('Nangka', 12.1),
      station('Ugong', 14),
      station('Burgos', 10),
    ]);
    expect(sorted.map((s) => s.name), [
      'Ugong',
      'Nangka',
      'Burgos',
      'Pandacan',
      'Angono',
    ]);
  });

  test('a reading is old after an hour', () {
    final s = station('a', 10, at: DateTime.utc(2026, 10, 11, 3));
    expect(s.isStale(DateTime.utc(2026, 10, 11, 4)), isFalse);
    expect(s.isStale(DateTime.utc(2026, 10, 11, 4, 1)), isTrue);
  });

  test('river_level rows', () {
    final s = RiverLevel.fromJson({
      'station_code': '11204202',
      'name': 'Fort Santiago',
      'latitude': 14.5952805555556,
      'longitude': 120.969663888889,
      'observed_at': '2026-10-11T03:20:00+00:00',
      'level_m': 11.42,
      'change_m': -0.02,
      'alert_m': 12,
      'alarm_m': 12.5,
      'critical_m': 13,
      'flagged': true,
      'state': 'normal',
      'updated_at': '2026-10-11T03:30:01+00:00',
    });
    expect(s.levelM, 11.42);
    expect(s.changeM, -0.02);
    expect(s.flagged, isTrue);
    expect(s.state, RiverState.normal);
    expect(s.observedAt.toUtc(), DateTime.utc(2026, 10, 11, 3, 20));
    final bare = RiverLevel.fromJson({
      'station_code': '11105201',
      'name': 'Angono',
      'latitude': 14.5268306,
      'longitude': 121.1423667,
      'observed_at': '2026-10-11T03:20:00+00:00',
      'level_m': 12.04,
      'change_m': null,
      'alert_m': null,
      'alarm_m': null,
      'critical_m': null,
    });
    expect(bare.state, isNull);
    expect(bare.flagged, isFalse);
    expect(
      FeedStatus.fromJson({
        'source': 'efcos',
        'checked_at': '2026-10-11T03:30:01+00:00',
        'ok': true,
        'last_success_at': '2026-10-11T03:30:01+00:00',
        'last_error': null,
        'failures': 0,
        'seen': {'stations': 17, 'raised': 2},
      }).source,
      FeedSource.efcos,
    );
  });
}
