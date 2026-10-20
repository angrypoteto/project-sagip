import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:supabase/supabase.dart' as supa;

/// What the resident is told when a sign-in code cannot be sent or checked
/// (2026-10-20: the gateway refused a code and the app said "offline").
void main() {
  test('no answer at all is offline', () {
    expect(
      phoneAuthFailureFor(supa.AuthRetryableFetchException(message: 'x')),
      PhoneAuthFailure.offline,
    );
    expect(phoneAuthFailureFor(StateError('socket')), PhoneAuthFailure.offline);
  });

  test('a server error, such as the SMS hook failing, is not offline', () {
    expect(
      phoneAuthFailureFor(
        supa.AuthRetryableFetchException(
          message: 'Unexpected status code returned from hook: 502',
          statusCode: '500',
        ),
      ),
      PhoneAuthFailure.unavailable,
    );
  });

  test('too many requests and an expired code keep their reasons', () {
    expect(
      phoneAuthFailureFor(const supa.AuthException('x', statusCode: '429')),
      PhoneAuthFailure.tooManyAttempts,
    );
    expect(
      phoneAuthFailureFor(
        const supa.AuthException('x', code: 'over_sms_send_rate_limit'),
      ),
      PhoneAuthFailure.tooManyAttempts,
    );
    expect(
      phoneAuthFailureFor(const supa.AuthException('x', code: 'otp_expired')),
      PhoneAuthFailure.wrongCode,
    );
    expect(
      phoneAuthFailureFor(const supa.AuthException('x', statusCode: '400')),
      PhoneAuthFailure.unavailable,
    );
  });
}
