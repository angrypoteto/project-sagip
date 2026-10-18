import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Safe places (Joshua, 2026-10-19). The scenario is the one in the RLS
/// test (`supabase/tests/rls_test.sql`, "safe places"), so the phone's
/// offline answer and the server's agree.
void main() {
  const here = GeoPoint(14.6000, 120.9900);
  SafePlace place(
    String id,
    SafePlaceKind kind,
    double lat,
    double lng, {
    bool hidden = false,
  }) => SafePlace(
    id: id,
    kind: kind,
    location: GeoPoint(lat, lng),
    hidden: hidden,
  );

  final places = [
    place('adm-00000000a1', SafePlaceKind.school, 14.6009, 120.9900),
    place('adm-00000000b2', SafePlaceKind.basketballCourt, 14.60045, 120.9900),
    place('adm-00000000c3', SafePlaceKind.hospital, 14.6018, 120.9900),
    place('adm-00000000d4', SafePlaceKind.openSpace, 14.6040, 120.9900),
    place('adm-00000000e5', SafePlaceKind.coveredCourt, 14.6000, 120.99325),
    place(
      'adm-00000000f6',
      SafePlaceKind.evacuationCenter,
      14.59955,
      120.9900,
      hidden: true,
    ),
  ];
  List<String> ids(
    IncidentType need, {
    List<HazardZone> avoid = const [],
    int limit = 3,
  }) => [
    for (final o in nearestSafePlaces(
      places,
      here,
      need,
      avoid: avoid,
      limit: limit,
    ))
      o.place.id,
  ];

  test('each emergency gets the kind of place that suits it', () {
    expect(ids(IncidentType.flood), ['adm-00000000a1', 'adm-00000000e5']);
    expect(ids(IncidentType.fire), ['adm-00000000e5', 'adm-00000000d4']);
    expect(ids(IncidentType.structural), ['adm-00000000d4']);
    expect(ids(IncidentType.medical), ['adm-00000000c3']);
    expect(ids(IncidentType.fire, limit: 1), ['adm-00000000e5']);
    final hospital = nearestSafePlaces(places, here, IncidentType.medical);
    // The database says 199 m (on the spheroid); the phone's sphere, 200.
    expect(hospital.single.meters, closeTo(199, 2));
  });

  test('the rules are the database\'s (migration safe_places)', () {
    String kinds(IncidentType t) => (SafePlaceRules.kindsFor(
      t,
    ).map((k) => k.name).toList()..sort()).join(',');
    expect(
      kinds(IncidentType.flood),
      'barangayHall,coveredCourt,evacuationCenter,school',
    );
    expect(
      kinds(IncidentType.fire),
      'basketballCourt,coveredCourt,evacuationCenter,openSpace,school',
    );
    expect(
      kinds(IncidentType.structural),
      'basketballCourt,evacuationCenter,openSpace',
    );
    expect(kinds(IncidentType.medical), 'hospital');
    expect(SafePlaceRules.minMetersFor(IncidentType.fire), 300);
    expect(SafePlaceRules.minMetersFor(IncidentType.structural), 100);
    expect(SafePlaceRules.minMetersFor(IncidentType.flood), 0);
  });

  test('places near a confirmed flood or fire are left out', () {
    const flood = HazardZone(GeoPoint(14.6009, 120.9900), IncidentType.flood);
    const fire = HazardZone(GeoPoint(14.6040, 120.9900), IncidentType.fire);
    expect(ids(IncidentType.flood, avoid: [flood, fire]), ['adm-00000000e5']);
    expect(ids(IncidentType.fire, avoid: [flood, fire]), ['adm-00000000e5']);
    // The school is 343 m from the fire: far enough without the flood.
    expect(ids(IncidentType.flood, avoid: [fire]), [
      'adm-00000000a1',
      'adm-00000000e5',
    ]);
  });

  test(
    'the bundled list: in Manila, one row each, every kind but MDRRMD\'s',
    () {
      expect(manilaSafePlaces.length, greaterThan(700));
      final seen = <String>{};
      for (final p in manilaSafePlaces) {
        expect(seen.add(p.id), isTrue, reason: p.id);
        expect(p.id, matches(RegExp(r'^osm-[nwr][0-9]+$')));
        expect(insideManila(p.location), isTrue, reason: p.id);
        expect(p.barangay, isNotNull, reason: p.id);
        expect(p.official || p.hidden, isFalse, reason: p.id);
      }
      expect(manilaSafePlaces.map((p) => p.kind).toSet(), {
        for (final k in SafePlaceKind.values)
          if (k != SafePlaceKind.evacuationCenter) k,
      });
      // Anywhere in Manila has a safe place for every emergency.
      for (final need in IncidentType.values) {
        final near = nearestSafePlaces(
          manilaSafePlaces,
          const GeoPoint(14.5995, 120.9842),
          need,
        );
        expect(near, hasLength(3), reason: need.name);
      }
    },
  );

  test('a server row reads back', () {
    final option = SafePlaceOption.fromJson(const {
      'place_id': 'adm-0123456789',
      'name': 'Barangay 400 Evacuation Center',
      'kind': 'evacuationCenter',
      'latitude': 14.6002,
      'longitude': 120.9902,
      'barangay': 'Barangay 400',
      'district': 'Sampaloc',
      'official': true,
      'meters': 31.5,
    });
    expect(option.place.official, isTrue);
    expect(option.place.fromMap, isFalse);
    expect(option.place.kind, SafePlaceKind.evacuationCenter);
    expect(option.meters, 31.5);
    final row = SafePlace.fromJson({
      ...option.place.toJson(),
      'hidden_at': '2026-10-19T00:00:00Z',
    });
    expect(row.hidden, isTrue);
    expect(row.copyWith(hidden: false), option.place);
  });

  group('A2 on sample data', () {
    late MockBackend backend;
    late MockSafePlaceRepository repo;
    late MockAuthRepository auth;

    setUp(() async {
      backend = MockBackend(latency: Duration.zero);
      repo = MockSafePlaceRepository(backend);
      auth = MockAuthRepository(backend);
      await auth.signIn(
        email: 'admin@sagip.test',
        password: MockSeed.demoPassword,
      );
    });

    tearDown(() => backend.dispose());

    Future<List<AuditEntry>> audit() =>
        MockAuditRepository(backend).watchRecent().first;

    test('add, rename, hide, and show again, each in the audit log', () async {
      final id = await repo.savePlace(
        name: '  Barangay 400 Evacuation Center ',
        kind: SafePlaceKind.evacuationCenter,
        location: const GeoPoint(14.6002, 120.9902),
        official: true,
      );
      var all = await repo.watchPlaces().first;
      final added = all.singleWhere((p) => p.id == id);
      expect(added.name, 'Barangay 400 Evacuation Center');
      expect(added.official, isTrue);
      expect(added.barangay, isNotNull);
      final near = await repo.nearest(
        const GeoPoint(14.6000, 120.9900),
        IncidentType.flood,
      );
      expect(near.first.place.id, id);

      await expectLater(
        repo.savePlace(
          name: ' ',
          kind: SafePlaceKind.evacuationCenter,
          location: const GeoPoint(14.6002, 120.9902),
          official: true,
        ),
        throwsA(isA<ActionRejected>()),
      );
      await expectLater(
        repo.savePlace(
          name: 'Far away',
          kind: SafePlaceKind.school,
          location: const GeoPoint(14.45, 120.99),
          official: false,
        ),
        throwsA(
          isA<ReportRejected>().having(
            (e) => e.reason,
            'reason',
            ReportRejection.outsideManila,
          ),
        ),
      );

      await repo.setHidden(id, true);
      all = await repo.watchPlaces().first;
      expect(all.singleWhere((p) => p.id == id).hidden, isTrue);
      final after = await repo.nearest(
        const GeoPoint(14.6000, 120.9900),
        IncidentType.flood,
      );
      expect(after.map((o) => o.place.id), isNot(contains(id)));
      await repo.setHidden(id, false);

      final actions = [for (final e in await audit()) e.action];
      expect(
        actions,
        containsAll([
          AuditAction.safePlaceSaved,
          AuditAction.safePlaceHidden,
          AuditAction.safePlaceRestored,
        ]),
      );
    });

    test('a dispatcher cannot change a place', () async {
      await auth.signOut();
      await auth.signIn(
        email: 'dispatcher@sagip.test',
        password: MockSeed.demoPassword,
      );
      await expectLater(
        repo.setHidden(manilaSafePlaces.first.id, true),
        throwsA(
          isA<ActionRejected>().having(
            (e) => e.reason,
            'reason',
            ActionRejection.notAllowed,
          ),
        ),
      );
    });
  });

  test('the bundled repository is read-only and works offline', () async {
    final repo = BundledSafePlaceRepository(
      places: places,
      hazards: () => const [
        HazardZone(GeoPoint(14.6009, 120.9900), IncidentType.flood),
      ],
    );
    final near = await repo.nearest(here, IncidentType.flood);
    expect([for (final o in near) o.place.id], ['adm-00000000e5']);
    expect(
      () => repo.setHidden('adm-00000000a1', true),
      throwsA(isA<ActionRejected>()),
    );
  });
}
