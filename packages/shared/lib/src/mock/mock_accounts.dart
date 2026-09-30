part of 'mock_mobile_backend.dart';

/// Resident accounts by mobile number, the codes sent by SMS, and the
/// phone's permissions (S2 to S5, S7). The code is always
/// [MockMobileBackend.demoCode]; the real one comes from Supabase's Send SMS
/// hook (plan Q37).
class _AccountsSim {
  _AccountsSim(this._b);

  final MockMobileBackend _b;

  /// Maria's verified number from the sample data.
  final _accounts = <String, AppUser>{
    '+639170004821': MockMobileBackend.resident,
  };
  final _pending = <String, ({AppUser user, Resident resident})>{};
  final _sends = <String, List<DateTime>>{};
  final deletionRequests = <String>[];
  var _nextResident = 200;

  final permissions = LiveValue<Map<AppPermission, PermissionState>>({
    for (final p in AppPermission.values) p: PermissionState.notAsked,
  });

  /// Code requests allowed per number per minute before "Try again in
  /// 60 s" (S3).
  static const sendLimit = 3;

  String _normalize(String phone) {
    final n = normalizePhMobile(phone);
    if (n == null) {
      throw const PhoneAuthException(PhoneAuthFailure.invalidNumber);
    }
    return n;
  }

  void _requireOnline() {
    if (_b._signal.value != SignalState.internet) {
      throw const PhoneAuthException(PhoneAuthFailure.offline);
    }
  }

  Future<void> sendCode(String phone) async {
    final n = _normalize(phone);
    await _b._pause();
    _requireOnline();
    if (!_accounts.containsKey(n) && !_pending.containsKey(n)) {
      throw const PhoneAuthException(PhoneAuthFailure.notRegistered);
    }
    final now = _b._clock();
    final recent = [
      for (final t in _sends[n] ?? const <DateTime>[])
        if (now.difference(t) < const Duration(minutes: 1)) t,
    ];
    if (recent.length >= sendLimit) {
      throw const PhoneAuthException(PhoneAuthFailure.tooManyAttempts);
    }
    _sends[n] = [...recent, now];
  }

  Future<AppUser> verifyCode(String phone, String code) async {
    final n = _normalize(phone);
    await _b._pause();
    _requireOnline();
    if (code.trim() != MockMobileBackend.demoCode) {
      throw const PhoneAuthException(PhoneAuthFailure.wrongCode);
    }
    final pending = _pending.remove(n);
    if (pending != null) {
      _accounts[n] = pending.user;
      _b._residents[pending.user.id] = pending.resident;
    }
    final user = _accounts[n];
    if (user == null) {
      throw const PhoneAuthException(PhoneAuthFailure.notRegistered);
    }
    _b._user.value = user;
    return user;
  }

  Future<void> register({
    required String fullName,
    required String phone,
    required Barangay barangay,
  }) async {
    final n = _normalize(phone);
    await _b._pause();
    _requireOnline();
    if (_accounts.containsKey(n)) {
      throw const PhoneAuthException(PhoneAuthFailure.numberTaken);
    }
    final id = 'res-${_nextResident++}';
    _pending[n] = (
      user: AppUser(
        id: id,
        displayName: fullName.trim(),
        email: '',
        role: UserRole.resident,
      ),
      resident: Resident(
        id: id,
        fullName: fullName.trim(),
        contactNumber: n,
        barangay: barangay.name,
        district: barangay.district,
      ),
    );
    await sendCode(n);
  }

  Future<void> requestDataDeletion() async {
    await _b._pause();
    if (_b._signal.value != SignalState.internet) {
      throw const ActionRejected(ActionRejection.offline);
    }
    final id = _b._user.value?.id;
    if (id != null) deletionRequests.add(id);
  }

  /// The mock grants whatever is asked. [denyNext] lets tests and the demo
  /// show the refused and "Open settings" states.
  PermissionState? denyNext;

  Future<PermissionState> request(AppPermission p) async {
    final result = denyNext ?? PermissionState.granted;
    denyNext = null;
    permissions.value = {...permissions.value, p: result};
    return result;
  }
}
