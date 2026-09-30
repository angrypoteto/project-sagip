import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  late DateTime now;
  late MockMobileBackend b;

  setUp(() {
    now = DateTime(2026, 9, 30, 15, 42);
    b = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      autoOffers: false,
    );
  });

  tearDown(() => b.dispose());

  Future<PhoneAuthFailure?> failure(Future<Object?> Function() run) async {
    try {
      await run();
      return null;
    } on PhoneAuthException catch (e) {
      return e.reason;
    }
  }

  test('Philippine mobile numbers are normalized', () {
    expect(normalizePhMobile('0917 000 4821'), '+639170004821');
    expect(normalizePhMobile('9170004821'), '+639170004821');
    expect(normalizePhMobile('+63 917-000-4821'), '+639170004821');
    expect(normalizePhMobile('02 8527 0000'), isNull, reason: 'landline');
    expect(normalizePhMobile('0917 000'), isNull);
  });

  test('sign-in by code: errors, then success', () async {
    expect(
      await failure(() => b.sendCode('123')),
      PhoneAuthFailure.invalidNumber,
    );
    expect(
      await failure(() => b.sendCode('0918 111 2222')),
      PhoneAuthFailure.notRegistered,
    );
    b.setSignal(SignalState.smsOnly);
    expect(
      await failure(() => b.sendCode('0917 000 4821')),
      PhoneAuthFailure.offline,
    );
    b.setSignal(SignalState.internet);

    expect(await failure(() => b.sendCode('0917 000 4821')), isNull);
    expect(
      await failure(() => b.verifyCode('0917 000 4821', '000000')),
      PhoneAuthFailure.wrongCode,
    );
    final user = await b.verifyCode(
      '0917 000 4821',
      MockMobileBackend.demoCode,
    );
    expect(user.id, 'res-001');
    expect(b.currentUser?.id, 'res-001');
  });

  test('too many code requests in a minute are refused', () async {
    for (var i = 0; i < 3; i++) {
      expect(await failure(() => b.sendCode('09170004821')), isNull);
    }
    expect(
      await failure(() => b.sendCode('09170004821')),
      PhoneAuthFailure.tooManyAttempts,
    );
    now = now.add(const Duration(minutes: 1, seconds: 1));
    expect(await failure(() => b.sendCode('09170004821')), isNull);
  });

  test('registering creates the resident once the code is checked', () async {
    const brgy = Barangay('Barangay 700', 'Malate');
    expect(
      await failure(
        () => b.register(
          fullName: 'Maria Dela Cruz',
          phone: '0917 000 4821',
          barangay: brgy,
        ),
      ),
      PhoneAuthFailure.numberTaken,
    );

    await b.register(
      fullName: 'Ana Reyes',
      phone: '0918 555 0101',
      barangay: brgy,
    );
    expect(b.currentUser, isNull, reason: 'not signed in until the code');
    final user = await b.verifyCode(
      '0918 555 0101',
      MockMobileBackend.demoCode,
    );
    expect(user.displayName, 'Ana Reyes');
    final profile = await b.watchResident(user.id).first;
    expect(profile!.barangay, 'Barangay 700');
    expect(profile.district, 'Malate');
  });

  test('data deletion requests are recorded', () async {
    await b.verifyCode('09170004821', MockMobileBackend.demoCode);
    await b.requestDataDeletion();
    expect(b.deletionRequests, ['res-001']);
  });

  test('permissions start unasked and can be refused', () async {
    final start = await b.watchPermissions().first;
    expect(start.values, everyElement(PermissionState.notAsked));
    expect(
      await b.requestPermission(AppPermission.location),
      PermissionState.granted,
    );
    b.denyNextPermission(PermissionState.permanentlyDenied);
    expect(
      await b.requestPermission(AppPermission.sms),
      PermissionState.permanentlyDenied,
    );
    final now = await b.watchPermissions().first;
    expect(now[AppPermission.location], PermissionState.granted);
    expect(now[AppPermission.sms], PermissionState.permanentlyDenied);
  });
}
