import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final row = {
    'event_id': 1001338,
    'name': 'CHAMPI-26',
    'alert_level': 'Red',
    'is_current': false,
    'from_at': '2026-10-14T12:00:00+00:00',
    'to_at': '2026-10-25T18:00:00+00:00',
    'max_wind_kmh': 296.29,
    'track': [
      {
        't': '2026-10-14T12:00:00Z',
        'lat': 9.6,
        'lng': 161.2,
        'category': 'TD',
        'forecast': false,
      },
      {
        't': '2026-10-25T18:00:00Z',
        'lat': 31.2,
        'lng': 127.4,
        'category': 'TS',
        'forecast': false,
      },
      {
        't': '2026-10-26T06:00:00Z',
        'lat': 31.9,
        'lng': 130.5,
        'category': 'TD',
        'forecast': true,
      },
    ],
    'wind_zones': [
      {
        'kmh': 60,
        'rings': [
          [
            [10, 120],
            [11, 121],
            [10, 122],
            [10, 120],
          ],
        ],
      },
    ],
    'cone': [
      [
        [30, 127],
        [33, 135],
        [31, 135],
        [30, 127],
      ],
    ],
  };

  test('a storm row reads back as written', () {
    final s = Storm.fromJson(row);
    expect(s.baseName, 'CHAMPI');
    expect(s.maxWindKmh, 296);
    expect(s.track, hasLength(3));
    expect(
      s.latest!.at.lat,
      31.2,
      reason: 'the latest observed, not the forecast',
    );
    expect(s.windZones.single.rings.single[1].lng, 121);
    expect(s.cone.single, hasLength(4));
    final again = Storm.fromJson(s.toJson());
    expect(again.toJson(), s.toJson());
  });

  PagasaWarning w(
    String id, {
    int? signal,
    List<String> refs = const [],
    String? response,
    DateTime? expires,
    String? headline,
  }) => PagasaWarning(
    id: id,
    kind: signal == null ? 'gfa' : 'wcp',
    event: 'x',
    sentAt: DateTime.utc(2026, 11, 1, int.parse(id.substring(1))),
    signalLevel: signal,
    refs: refs,
    responseType: response,
    expiresAt: expires,
    headline: headline,
  );

  test('the warnings in force: not expired, not replaced, not all-clear', () {
    final now = DateTime.utc(2026, 11, 1, 12);
    final later = now.add(const Duration(hours: 6));
    final feeds = HazardFeeds(
      warnings: [
        w('w1', expires: later), // replaced by w2
        w('w2', refs: ['w1'], expires: later),
        w('w3', signal: 1, expires: later),
        w('w4', signal: 3, expires: later),
        w('w5', expires: now.subtract(const Duration(minutes: 1))),
        w('w6', response: 'AllClear', expires: later),
      ],
    );
    expect(feeds.activeAt(now).map((x) => x.id), ['w4', 'w3', 'w2']);
  });

  test('the local name comes from a warning that names both', () {
    final storm = Storm.fromJson(row);
    final feeds = HazardFeeds(
      storms: [storm],
      warnings: [
        w(
          'w1',
          headline:
              'Tropical Cyclone Warning : Typhoon ROSAL (CHAMPI) Signal #1',
        ),
      ],
    );
    expect(feeds.localName(storm), 'Rosal');
    expect(const HazardFeeds().localName(storm), isNull);
    expect(feeds.latest, storm);
    expect(feeds.current, isNull);
  });

  test('the sample has a current typhoon and a signal over Manila', () {
    final feeds = MockSeed(DateTime(2026, 11, 2, 9)).hazardFeeds;
    expect(feeds.current!.name, 'SAMPLE-26');
    expect(feeds.activeAt(DateTime.utc(2026, 11, 2, 1)).first.signalLevel, 2);
  });
}
