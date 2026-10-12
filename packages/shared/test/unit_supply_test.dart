import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final at = DateTime(2026, 10, 12, 9);

  UnitSupply supply(
    SupplyItem item,
    double quantity,
    double capacity, {
    String unit = 'unit-r03',
    DateTime? updatedAt,
  }) => UnitSupply(
    unitId: unit,
    item: item,
    quantity: quantity,
    capacity: capacity,
    updatedAt: updatedAt ?? at,
    updatedByName: 'J. Reyes',
  );

  test('a supply is low at or below the percent, and out at zero', () {
    expect(supply(SupplyItem.fuel, 31, 100).stateAt(30), SupplyState.ok);
    expect(supply(SupplyItem.fuel, 30, 100).stateAt(30), SupplyState.low);
    expect(supply(SupplyItem.fuel, 0, 100).stateAt(30), SupplyState.out);
    // A stock is judged against its own full load.
    expect(
      supply(SupplyItem.drinkingWater, 6, 24).stateAt(30),
      SupplyState.low,
    );
    expect(supply(SupplyItem.drinkingWater, 8, 24).stateAt(30), SupplyState.ok);
    expect(
      supply(SupplyItem.drinkingWater, 8, 24).stateAt(50),
      SupplyState.low,
    );
    expect(supply(SupplyItem.lifeVests, 10, 12).level, closeTo(0.833, 0.001));
  });

  test('only fuel and tank water are a percent', () {
    expect(
      [
        for (final i in SupplyItem.values)
          if (i.isPercent) i,
      ],
      [SupplyItem.fuel, SupplyItem.tankWater],
    );
  });

  test('a report is old after a day', () {
    final s = supply(SupplyItem.fuel, 50, 100);
    expect(s.isStale(at.add(const Duration(hours: 24))), isFalse);
    expect(s.isStale(at.add(const Duration(hours: 25))), isTrue);
  });

  test(
    'a unit\'s supplies come in the order of the list, the short ones apart',
    () {
      final all = [
        supply(SupplyItem.lifeVests, 10, 12),
        supply(SupplyItem.fuel, 25, 100),
        supply(SupplyItem.medicalKits, 0, 6),
        supply(SupplyItem.fuel, 90, 100, unit: 'unit-r02'),
      ];
      final mine = suppliesOf('unit-r03', all);
      expect(mine.map((s) => s.item), [
        SupplyItem.fuel,
        SupplyItem.medicalKits,
        SupplyItem.lifeVests,
      ]);
      expect(shortSupplies(mine, 30).map((s) => s.item), [
        SupplyItem.fuel,
        SupplyItem.medicalKits,
      ]);
      expect(suppliesOf('unit-x', all), isEmpty);
    },
  );

  test('unit_supply and response_unit rows', () {
    final s = UnitSupply.fromJson({
      'unit_id': 'unit-bfp-pandacan',
      'item': 'tankWater',
      'quantity': 20,
      'capacity': 100,
      'updated_at': '2026-10-12T01:00:00+00:00',
      'updated_by': '00000000-0000-4000-8000-00000000000b',
      'updated_by_name': 'Test Responder',
    });
    expect(s.item, SupplyItem.tankWater);
    expect(s.stateAt(30), SupplyState.low);
    expect(UnitSupply.fromJson(s.toJson()).quantity, 20);

    final listed = ResponseUnit.fromJson({
      'unit_id': 'unit-bfp-pandacan',
      'call_sign': 'BFP-PANDACAN',
      'unit_type': 'fireTruck',
      'station': 'Pandacan Fire Station, L. Certeza Street',
      'crew_size': null,
      'status': 'available',
      'agency': 'bfp',
      'source': 'OpenStreetMap, 2026-10-12',
      'last_latitude': 14.592,
      'last_longitude': 121.01193,
      'last_location_at': null,
      'current_incident_id': null,
      'retired_at': null,
    });
    expect(listed.type, UnitType.fireTruck);
    expect(listed.agency, UnitAgency.bfp);
    expect(listed.crewSize, isNull);
    expect(listed.source, 'OpenStreetMap, 2026-10-12');
    // A row from before the migration is MDRRMD's own.
    final old = ResponseUnit.fromJson({
      'unit_id': 'unit-r03',
      'call_sign': 'R-03',
      'unit_type': 'rescueBoat',
      'station': 'Sampaloc station',
      'crew_size': 4,
      'status': 'available',
    });
    expect(old.agency, UnitAgency.mdrrmd);
    expect(old.crewSize, 4);
  });

  group('the crew reports their own unit (mock)', () {
    late MockBackend backend;
    var now = at;

    setUp(() {
      now = at;
      backend = MockBackend(clock: () => now, latency: Duration.zero);
    });
    tearDown(() => backend.dispose());

    Future<List<UnitSupply>> mine() => backend.watchMySupplies().first;

    test('a responder changes only the unit they are on', () async {
      await backend.signIn('j.reyes@sagip.test', MockSeed.demoPassword);
      expect((await backend.watchMyUnit().first)!.callSign, 'R-03');
      final before = await mine();
      expect(before.map((s) => s.item), contains(SupplyItem.fuel));

      now = now.add(const Duration(minutes: 5));
      await backend.setSupply(SupplyItem.fuel, 85);
      await backend.setSupply(SupplyItem.medicalKits, 4, capacity: 6);
      // The full load is remembered.
      await backend.setSupply(SupplyItem.medicalKits, 2);
      final after = {for (final s in await mine()) s.item: s};
      expect(after[SupplyItem.fuel]!.quantity, 85);
      expect(after[SupplyItem.fuel]!.updatedAt, now);
      expect(after[SupplyItem.fuel]!.updatedByName, 'J. Reyes');
      expect(after[SupplyItem.medicalKits]!.quantity, 2);
      expect(after[SupplyItem.medicalKits]!.capacity, 6);

      // Other units are untouched.
      final all = await backend.watchSupplies().first;
      expect(
        all
            .firstWhere(
              (s) => s.unitId == 'unit-r02' && s.item == SupplyItem.fuel,
            )
            .quantity,
        90,
      );
    });

    test('what cannot be true is refused', () async {
      await backend.signIn('j.reyes@sagip.test', MockSeed.demoPassword);
      Future<void> refused(Future<void> call) => expectLater(
        call,
        throwsA(
          isA<ActionRejected>().having(
            (e) => e.reason,
            'reason',
            ActionRejection.invalidValue,
          ),
        ),
      );
      await refused(backend.setSupply(SupplyItem.fuel, 101));
      await refused(backend.setSupply(SupplyItem.fuel, -1));
      await refused(backend.setSupply(SupplyItem.rescueGear, 3));
      await refused(backend.setSupply(SupplyItem.rescueGear, 7, capacity: 5));
      await refused(backend.setSupply(SupplyItem.rescueGear, 2.5, capacity: 5));
      await refused(backend.setSupply(SupplyItem.rescueGear, 0, capacity: 0));
    });

    test(
      'dispatchers, admins, and responders on no unit cannot report',
      () async {
        for (final email in [
          'dispatcher@sagip.test',
          'admin@sagip.test',
          'c.garcia@sagip.test',
        ]) {
          await backend.signIn(email, MockSeed.demoPassword);
          await expectLater(
            backend.setSupply(SupplyItem.fuel, 50),
            throwsA(
              isA<ActionRejected>().having(
                (e) => e.reason,
                'reason',
                ActionRejection.notAllowed,
              ),
            ),
            reason: email,
          );
        }
        expect(await backend.watchMyUnit().first, isNull);
      },
    );
  });
}
