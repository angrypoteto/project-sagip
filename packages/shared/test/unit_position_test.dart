import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final now = DateTime(2026, 10, 12, 19);
  const station = GeoPoint(14.58013, 121.00813);
  const scene = GeoPoint(14.58648, 121.00263);

  ResponseUnit unit({
    GeoPoint? home = station,
    GeoPoint? location,
    Duration? fixAge,
    UnitStatus status = UnitStatus.available,
    String? incident,
  }) => ResponseUnit(
    id: 'unit-bfp-staana',
    callSign: 'BFP-STAANA',
    type: UnitType.fireTruck,
    station: 'Santa Ana Fire Station',
    status: status,
    home: home,
    location: location,
    lastLocationAt: fixAge == null ? null : now.subtract(fixAge),
    currentIncidentId: incident,
  );

  test('a free unit is drawn at its station; its crew is the ghost', () {
    final u = unit(location: scene, fixAge: const Duration(minutes: 2));
    expect(u.onJob, isFalse);
    expect(u.mapPosition, station);
    expect(u.ghostPosition(now), scene);
    // A route for it starts where its crew really is.
    expect(u.startingPoint(now), scene);
  });

  test('an old fix from a free unit is not shown or routed from', () {
    final u = unit(location: scene, fixAge: const Duration(minutes: 11));
    expect(u.hasLiveFix(now), isFalse);
    expect(u.mapPosition, station);
    expect(u.ghostPosition(now), isNull);
    expect(u.startingPoint(now), station);
  });

  test('on a job the crew is the marker and the station is the ghost', () {
    final u = unit(
      location: scene,
      // Old: the crew may be offline, and it is still the best there is.
      fixAge: const Duration(minutes: 40),
      status: UnitStatus.enRoute,
      incident: 'INC-0001',
    );
    expect(u.onJob, isTrue);
    expect(u.mapPosition, scene);
    expect(u.ghostPosition(now), station);
    expect(u.startingPoint(now), scene);
    // Sent but not yet moving (status still Available) counts as on a job.
    expect(unit(incident: 'INC-0001').onJob, isTrue);
  });

  test('one marker when there is only one place, or both are one spot', () {
    // Never reported: the station alone.
    final fresh = unit();
    expect(fresh.mapPosition, station);
    expect(fresh.ghostPosition(now), isNull);
    expect(fresh.crewPosition, station);
    // On a job before any fix: still the station, no ghost.
    final sent = unit(status: UnitStatus.enRoute, incident: 'INC-0001');
    expect(sent.mapPosition, station);
    expect(sent.ghostPosition(now), isNull);
    // No station recorded: the last fix, however old.
    final noHome = unit(
      home: null,
      location: scene,
      fixAge: const Duration(hours: 3),
    );
    expect(noHome.mapPosition, scene);
    expect(noHome.ghostPosition(now), isNull);
    expect(noHome.startingPoint(now), scene);
    // The crew is at the station.
    final atHome = unit(
      location: const GeoPoint(14.58020, 121.00820),
      fixAge: const Duration(minutes: 1),
    );
    expect(atHome.ghostPosition(now), isNull);
    // Nothing known at all.
    expect(unit(home: null).mapPosition, isNull);
  });

  test('the station comes from the row and goes back into it', () {
    final u = ResponseUnit.fromJson({
      'unit_id': 'unit-bfp-staana',
      'call_sign': 'BFP-STAANA',
      'unit_type': 'fireTruck',
      'station': 'Santa Ana Fire Station, Pedro Gil Street',
      'crew_size': null,
      'status': 'available',
      'agency': 'bfp',
      'home_latitude': 14.58013,
      'home_longitude': 121.00813,
      'last_latitude': null,
      'last_longitude': null,
      'last_location_at': null,
    });
    expect(u.home, station);
    expect(u.location, isNull);
    expect(ResponseUnit.fromJson(u.toJson()).home, station);
    expect(u.copyWith(clearHome: true).home, isNull);
  });

  test('suggestions start from the station when the fix is old', () async {
    const incident = GeoPoint(14.5805, 121.0085);
    final near = unit(location: scene, fixAge: const Duration(minutes: 30));
    final sos = Incident(
      id: 'INC-1',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.app,
      status: IncidentStatus.pendingVerification,
      location: incident,
      barangay: 'Barangay 1',
      district: 'Santa Ana',
      capturedAt: now,
      receivedAt: now,
    );
    final suggester = StraightLineSuggester(now: () => now);
    final old = (await suggester.suggest(sos, [near])).single;
    final live = (await suggester.suggest(sos, [
      unit(location: scene, fixAge: const Duration(minutes: 1)),
    ])).single;
    // The station is beside the incident; the old fix is not.
    expect(old.distanceKm, lessThan(0.2));
    expect(live.distanceKm, greaterThan(0.8));
  });

  group('an admin sets a unit\'s station position (mock)', () {
    late MockBackend backend;
    setUp(
      () => backend = MockBackend(clock: () => now, latency: Duration.zero),
    );
    tearDown(() => backend.dispose());

    test('set, clear, and refused outside Manila; audited', () async {
      await backend.signIn('admin@sagip.test', MockSeed.demoPassword);
      await backend.setUnitHome('unit-r03', station);
      var units = await backend.watchAllUnits().first;
      expect(units.firstWhere((u) => u.id == 'unit-r03').home, station);
      final log = await backend.watchAudit(1).first;
      expect(log.first.action, AuditAction.unitEdited);
      expect(log.first.detail, 'station position set to 14.58013, 121.00813');

      await expectLater(
        backend.setUnitHome('unit-r03', const GeoPoint(15.2, 121)),
        throwsA(isA<ActionRejected>()),
      );
      await backend.setUnitHome('unit-r03', null);
      units = await backend.watchAllUnits().first;
      expect(units.firstWhere((u) => u.id == 'unit-r03').home, isNull);
    });

    test('a dispatcher cannot', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await expectLater(
        backend.setUnitHome('unit-r03', station),
        throwsA(isA<ActionRejected>()),
      );
    });
  });
}
