import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

void main() {
  late MockBackend backend;
  late MockResourceRepository repo;
  late MockAuthRepository auth;

  setUp(() async {
    backend = MockBackend(latency: Duration.zero);
    repo = MockResourceRepository(backend);
    auth = MockAuthRepository(backend);
    await auth.signIn(
      email: 'admin@sagip.test',
      password: MockSeed.demoPassword,
    );
  });

  tearDown(() => backend.dispose());

  Future<List<AuditEntry>> audit() =>
      MockAuditRepository(backend).watchRecent().first;

  test('A2 follows the same rules as the database', () async {
    // Add: the call sign is tidied and names the id.
    final id = await repo.saveUnit(
      callSign: ' r-20 ',
      type: UnitType.rescueTeam,
      station: 'Paco station',
      crewSize: 5,
    );
    expect(id, 'unit-r20');
    await expectLater(
      repo.saveUnit(
        callSign: 'r-03',
        type: UnitType.ambulance,
        station: 'Tondo station',
        crewSize: 3,
      ),
      rejected(ActionRejection.alreadyExists),
    );
    await expectLater(
      repo.saveUnit(
        callSign: 'R-21',
        type: UnitType.ambulance,
        station: 'Tondo station',
        crewSize: 0,
      ),
      rejected(ActionRejection.invalidValue),
    );

    // Edit, with the change spelled out in the audit log.
    await repo.saveUnit(
      id: id,
      callSign: 'R-20',
      type: UnitType.rescueTeam,
      station: 'Pandacan station',
      crewSize: 6,
    );
    final edited = (await audit()).firstWhere(
      (e) => e.action == AuditAction.unitEdited,
    );
    expect(
      edited.detail,
      'station Paco station → Pandacan station; crew 5 → 6',
    );

    // A unit on a job cannot be retired.
    await expectLater(
      repo.retireUnit('unit-r05'),
      rejected(ActionRejection.unitNotAvailable),
    );

    // Roster, then retire: the responder comes off the unit.
    await repo.setResponderUnit('usr-resp-04', id);
    await repo.retireUnit(id);
    final crew = await repo.watchResponders().first;
    expect(crew.firstWhere((s) => s.id == 'usr-resp-04').unitId, isNull);
    await expectLater(
      repo.setResponderUnit('usr-resp-04', id),
      rejected(ActionRejection.invalidValue),
    );

    // Retired units stay on A2 but leave the board and cannot be assigned.
    expect((await repo.watchUnits().first).any((u) => u.id == id), isTrue);
    final board = await MockUnitRepository(backend).watchAll().first;
    expect(board.any((u) => u.id == id), isFalse);
    await expectLater(
      MockIncidentRepository(backend).assignUnit('INC-0149', id),
      rejected(ActionRejection.unitNotAvailable),
    );

    await repo.restoreUnit(id);
    expect(
      (await MockUnitRepository(
        backend,
      ).watchAll().first).any((u) => u.id == id),
      isTrue,
    );
    expect(
      [
        for (final e in await audit())
          if (e.action.name.startsWith('unit') &&
                  e.action != AuditAction.unitAssigned &&
                  e.action != AuditAction.unitReassigned ||
              e.action == AuditAction.rosterChanged)
            e.action,
      ],
      containsAll([
        AuditAction.unitAdded,
        AuditAction.unitEdited,
        AuditAction.rosterChanged,
        AuditAction.unitRetired,
        AuditAction.unitRestored,
      ]),
    );
  });

  test('dispatchers cannot change units or the roster', () async {
    await auth.signOut();
    await auth.signIn(
      email: 'dispatcher@sagip.test',
      password: MockSeed.demoPassword,
    );
    await expectLater(
      repo.saveUnit(
        callSign: 'R-20',
        type: UnitType.rescueTeam,
        station: 'Paco station',
        crewSize: 5,
      ),
      rejected(ActionRejection.notAllowed),
    );
    await expectLater(
      repo.setResponderUnit('usr-resp-04', 'unit-r03'),
      rejected(ActionRejection.notAllowed),
    );
  });

  test('units and staff rows from the database parse', () {
    final unit = ResponseUnit.fromJson({
      'unit_id': 'unit-r20',
      'call_sign': 'R-20',
      'unit_type': 'rescueTeam',
      'station': 'Pandacan station',
      'crew_size': 6,
      'status': 'available',
      'last_latitude': null,
      'last_longitude': null,
      'last_location_at': null,
      'current_incident_id': null,
      'retired_at': '2026-10-01T01:00:00+00:00',
    });
    expect(unit.retired, isTrue);
    expect(unit.isDispatchable, isFalse);
    final staff = StaffAccount.fromJson({
      'id': '00000000-0000-4000-8000-000000000011',
      'display_name': 'Test Responder Two',
      'email': 'rls-responder2@test.local',
      'role': 'responder',
      'unit_id': null,
    });
    expect(staff.role, UserRole.responder);
    expect(staff.unitId, isNull);
  });
}
