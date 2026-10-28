import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

Matcher authFails(AuthFailure reason) =>
    throwsA(isA<AuthException>().having((e) => e.reason, 'reason', reason));

void main() {
  late MockBackend backend;
  late MockAccountRepository accounts;
  late MockAuthRepository auth;

  setUp(() async {
    backend = MockBackend(latency: Duration.zero);
    accounts = MockAccountRepository(backend);
    auth = MockAuthRepository(backend);
    await auth.signIn(
      email: 'admin@sagip.test',
      password: MockSeed.demoPassword,
    );
  });

  tearDown(() => backend.dispose());

  Future<void> signInAs(String email, String password) async {
    await auth.signOut();
    await auth.signIn(email: email, password: password);
  }

  test('personnel IDs and crew lists follow the database rules', () async {
    final units = MockUnitRepository(backend);
    // An admin sets one: trimmed, in capitals, audited.
    await accounts.setPersonnelId('usr-resp-06', ' mdrrmd-0103 ');
    expect(
      (await accounts.watchStaff().first)
          .firstWhere((s) => s.id == 'usr-resp-06')
          .personnelId,
      'MDRRMD-0103',
    );
    await expectLater(
      accounts.setPersonnelId('usr-resp-04', 'MDRRMD-0103'),
      rejected(ActionRejection.alreadyExists),
    );
    await expectLater(
      accounts.setPersonnelId('usr-resp-04', 'ID 42!'),
      rejected(ActionRejection.invalidValue),
    );
    expect(
      (await backend.watchAudit(10).first).first.detail,
      'personnel ID none → MDRRMD-0103',
    );

    // Dispatchers see every unit's crew; C. Garcia is on no unit.
    await signInAs('dispatcher@sagip.test', MockSeed.demoPassword);
    final all = await units.watchCrew().first;
    expect(
      {for (final c in all) c.unitId},
      {'unit-r03', 'unit-r05', 'unit-r07'},
    );
    expect(all.where((c) => c.unitId == 'unit-r03').map((c) => c.displayName), [
      'J. Reyes',
      'L. Cruz',
      'R. Mendoza',
    ]);
    expect(all.any((c) => c.staffId == 'usr-resp-04'), isFalse);
    await expectLater(
      accounts.setPersonnelId('usr-resp-04', 'X-1'),
      rejected(ActionRejection.notAllowed),
    );

    // A responder sees only their own unit's crew.
    await signInAs('j.reyes@sagip.test', MockSeed.demoPassword);
    final mine = await units.watchCrew().first;
    expect(mine.map((c) => c.unitId).toSet(), {'unit-r03'});
    expect(mine, hasLength(3));
  });

  test('crew heads ask, admins decide: the database rules', () async {
    final crew = MockCrewRepository(backend);
    final resources = MockResourceRepository(backend);
    Future<CrewRequest> latest() async =>
        (await crew.watchRequests().first).first;

    // A member who is not a head cannot ask.
    await signInAs('l.cruz@sagip.test', MockSeed.demoPassword);
    await expectLater(
      crew.requestAdd('usr-resp-04'),
      rejected(ActionRejection.notAllowed),
    );
    expect(await crew.watchRequests().first, isEmpty);

    // The head (J. Reyes) asks to add C. Garcia, once.
    await signInAs('j.reyes@sagip.test', MockSeed.demoPassword);
    expect(
      (await crew.watchCandidates().first).map((c) => c.displayName),
      isNot(contains('R. Mendoza')),
    );
    await crew.requestAdd('usr-resp-04', note: 'Trained boat crew');
    await expectLater(
      crew.requestAdd('usr-resp-04'),
      rejected(ActionRejection.alreadyExists),
    );
    await expectLater(
      crew.requestRemove('usr-resp-01'),
      rejected(ActionRejection.ownAccount),
    );

    // The assistant head (R. Mendoza) asks too: off with J. Reyes, and a
    // new person with no account.
    await signInAs('r.mendoza@sagip.test', MockSeed.demoPassword);
    await crew.requestRemove('usr-resp-01', note: 'Replaced as head');
    await crew.requestNew(
      name: 'Ana Ramos',
      email: 'Ana.Ramos@Sagip.test',
      personnelId: 'mdrrmd-0104',
    );
    await expectLater(
      crew.requestNew(name: 'Again', email: 'j.reyes@sagip.test'),
      rejected(ActionRejection.alreadyExists),
    );
    expect(await crew.watchRequests().first, hasLength(3));

    // The admin decides.
    await signInAs('admin@sagip.test', MockSeed.demoPassword);
    final all = await crew.watchRequests().first;
    final add = all.firstWhere((r) => r.kind == CrewRequestKind.add);
    final remove = all.firstWhere((r) => r.kind == CrewRequestKind.remove);
    final fresh = all.firstWhere((r) => r.kind == CrewRequestKind.newMember);
    expect(fresh.newEmail, 'ana.ramos@sagip.test');
    await crew.decide(add.id, approve: true);
    expect(
      (await resources.watchResponders().first)
          .firstWhere((s) => s.id == 'usr-resp-04')
          .unitId,
      'unit-r03',
    );
    await expectLater(
      crew.decide(remove.id, approve: false),
      rejected(ActionRejection.invalidValue),
    );
    await crew.decide(remove.id, approve: false, note: 'Keep him this week');
    final made = await accounts.createStaff(
      email: 'ana.ramos@sagip.test',
      displayName: 'Ana Ramos',
      role: UserRole.responder,
      unitId: 'unit-r03',
    );
    await crew.decide(fresh.id, approve: true, createdStaffId: made.id);
    expect(
      (await accounts.watchStaff().first)
          .firstWhere((s) => s.id == made.id)
          .personnelId,
      'MDRRMD-0104',
    );
    expect((await latest()).status, isNot(CrewRequestStatus.pending));
    expect(
      (await crew.watchRequests().first)
          .firstWhere((r) => r.id == remove.id)
          .decisionNote,
      'Keep him this week',
    );

    // A head moved off the unit is no longer its head.
    await resources.setResponderUnit('usr-resp-01', null);
    final r03 = (await backend.watchUnits().first).firstWhere(
      (u) => u.id == 'unit-r03',
    );
    expect(r03.crewHeadId, isNull);
    expect(r03.assistantHeadId, 'usr-resp-05');
    // Leads must be on the unit.
    await expectLater(
      crew.setLeads('unit-r03', headId: 'usr-resp-02'),
      rejected(ActionRejection.invalidValue),
    );
    await crew.setLeads(
      'unit-r03',
      headId: 'usr-resp-05',
      assistantId: 'usr-resp-06',
    );
    final audit = await backend.watchAudit(30).first;
    expect(
      audit.map((e) => e.action),
      containsAll([
        AuditAction.crewRequested,
        AuditAction.crewRequestDecided,
        AuditAction.crewLeadsChanged,
      ]),
    );
  });

  test('A1 follows the same rules as the database', () async {
    final made = await accounts.createStaff(
      email: ' New.Dispatcher@Test.local ',
      displayName: 'New Dispatcher',
      role: UserRole.dispatcher,
    );
    await expectLater(
      accounts.createStaff(
        email: 'new.dispatcher@test.local',
        displayName: 'Again',
        role: UserRole.dispatcher,
      ),
      rejected(ActionRejection.alreadyExists),
    );
    await expectLater(
      accounts.createStaff(
        email: 'not-an-email',
        displayName: 'X',
        role: UserRole.dispatcher,
      ),
      rejected(ActionRejection.invalidValue),
    );

    // Admins cannot act on their own account here.
    await expectLater(
      accounts.setStaffActive('usr-admin-01', active: false),
      rejected(ActionRejection.ownAccount),
    );
    await expectLater(
      accounts.resetPassword('usr-admin-01'),
      rejected(ActionRejection.ownAccount),
    );
    await expectLater(
      accounts.updateStaff(
        'usr-admin-01',
        displayName: 'E. Navarro',
        role: UserRole.dispatcher,
      ),
      rejected(ActionRejection.ownAccount),
    );

    // Deactivated accounts cannot sign in; reactivated ones can.
    await accounts.setStaffActive(made.id, active: false);
    await auth.signOut();
    await expectLater(
      auth.signIn(
        email: 'new.dispatcher@test.local',
        password: made.temporaryPassword,
      ),
      authFails(AuthFailure.accountDisabled),
    );
    await signInAs('admin@sagip.test', MockSeed.demoPassword);
    await accounts.setStaffActive(made.id, active: true);
    await signInAs('new.dispatcher@test.local', made.temporaryPassword);
    expect(auth.currentUser!.displayName, 'New Dispatcher');

    // A reset replaces the password.
    await signInAs('admin@sagip.test', MockSeed.demoPassword);
    final fresh = await accounts.resetPassword(made.id);
    await auth.signOut();
    await expectLater(
      auth.signIn(
        email: 'new.dispatcher@test.local',
        password: made.temporaryPassword,
      ),
      authFails(AuthFailure.wrongCredentials),
    );
    await signInAs('new.dispatcher@test.local', fresh);

    // Dispatchers cannot manage accounts.
    await expectLater(
      accounts.resetPassword('usr-disp-01'),
      rejected(ActionRejection.notAllowed),
    );
  });

  test('suspending a resident and the audit trail', () async {
    await accounts.setResidentSuspended('res-001', suspended: true);
    var residents = await accounts.watchResidents().first;
    expect(residents.firstWhere((r) => r.id == 'res-001').suspended, isTrue);
    await accounts.setResidentSuspended('res-001', suspended: false);
    residents = await accounts.watchResidents().first;
    expect(residents.firstWhere((r) => r.id == 'res-001').suspended, isFalse);
    await accounts.updateStaff(
      'usr-disp-01',
      displayName: 'R. Santos-Cruz',
      role: UserRole.dispatcher,
    );
    final audit = await MockAuditRepository(backend).watchRecent().first;
    expect(
      audit.map((e) => e.action),
      containsAll([
        AuditAction.residentSuspended,
        AuditAction.residentRestored,
        AuditAction.accountUpdated,
      ]),
    );
    final staff = await accounts.watchStaff().first;
    expect(
      staff.firstWhere((s) => s.id == 'usr-disp-01').displayName,
      'R. Santos-Cruz',
    );
  });

  test('rows from the database parse', () {
    final s = StaffAccount.fromJson({
      'id': '00000000-0000-4000-8000-00000000000d',
      'display_name': 'Test Dispatcher',
      'email': 'rls-dispatcher@test.local',
      'role': 'dispatcher',
      'unit_id': null,
      'deactivated_at': '2026-10-01T01:00:00+00:00',
    });
    expect(s.active, isFalse);
    final r = Resident.fromJson({
      'manila_resident_id': 'res-001',
      'fullname': 'Maria Dela Cruz',
      'contact_number': '0917 ••• 4821',
      'barangay': 'Barangay 412',
      'district': 'Sampaloc',
      'consent_given_at': null,
      'updated_at': null,
      'household': [],
      'suspended_at': '2026-10-01T01:00:00+00:00',
    });
    expect(r.suspended, isTrue);
    expect(
      databaseRefusal('account_suspended'),
      isA<ReportRejected>().having(
        (e) => e.reason,
        'reason',
        ReportRejection.accountSuspended,
      ),
    );
    expect(
      databaseRefusal('own_account'),
      isA<ActionRejected>().having(
        (e) => e.reason,
        'reason',
        ActionRejection.ownAccount,
      ),
    );
  });
}
