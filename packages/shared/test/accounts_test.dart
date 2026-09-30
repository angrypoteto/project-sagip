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
