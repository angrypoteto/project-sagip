part of 'supabase_repositories.dart';

// Supabase side of the mobile app (resident and responder), part 5.
//
// Reads use the database functions and views in
// supabase/migrations/*mobile_actions, which return rows already in the
// app's model shapes (SosRequest, HazardReport, Assignment, ...). Writes of
// records made on the phone (SOS, reports, status updates, completion
// reports) go through [SupabaseMobileRemote]; part 6 puts the Hive offline
// queue in front of it, so these calls are what the queue sends.

/// Everything the mobile app needs from one [SupabaseClient].
class SupabaseMobileBackend {
  SupabaseMobileBackend(SupabaseClient client, {LocalStore? store})
    : this._(client, store, StreamController<Object?>.broadcast());

  SupabaseMobileBackend._(
    SupabaseClient client,
    LocalStore? store,
    this._profileChanged,
  ) : accounts = SupabaseMobileAccounts(client, store: store),
      residents = SupabaseResidentRepository(
        client,
        refreshOn: _profileChanged.stream,
      ),
      vulnerability = SupabaseVulnerabilityRepository(client, _profileChanged),
      alerts = SupabaseAlertRepository(client),
      weather = SupabaseWeatherRepository(client),
      remote = SupabaseMobileRemote(client);

  final StreamController<Object?> _profileChanged;
  final SupabaseMobileAccounts accounts;
  final SupabaseResidentRepository residents;
  final SupabaseVulnerabilityRepository vulnerability;
  final SupabaseAlertRepository alerts;
  final SupabaseWeatherRepository weather;
  final SupabaseMobileRemote remote;

  Future<void> dispose() => _profileChanged.close();
}

// --------------------------------------------------------------- accounts

/// Resident sign-in by mobile number and SMS code (S3 to S5), and
/// responder sign-in with the staff email and password.
///
/// The code is sent to any valid number: whether a number has an account
/// is only known after the code is checked, so the app never reveals which
/// numbers are registered (RA 10173). The SMS itself goes through
/// Supabase's Send SMS hook (plan Q37).
class SupabaseMobileAccounts
    implements AuthRepository, ResidentAccountRepository {
  SupabaseMobileAccounts(this._client, {this._store}) {
    _client.auth.onAuthStateChange.listen(
      (state) => _onSession(state.session),
      onError: (Object _) {},
    );
  }

  final SupabaseClient _client;

  /// Remembers who is signed in, so a phone restarted without a signal
  /// stays signed in and can still send an SOS.
  final LocalStore? _store;
  static const _savedKey = 'account';
  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  var _known = false;

  /// Set by [register] until the code is checked.
  ({String phone, String fullName, Barangay barangay})? _pending;

  /// True while [verifyCode] links or creates the resident record: the
  /// session exists a moment before the account does.
  var _finishing = false;

  void _set(AppUser? user) {
    _user = user;
    _known = true;
    _changes.add(user);
    final authId = _client.auth.currentUser?.id;
    unawaited(
      _store?.write(
        _savedKey,
        user == null || authId == null
            ? null
            : jsonEncodeSafe({'auth_id': authId, 'user': user.toJson()}),
      ),
    );
  }

  /// The account saved for this session, if it is the same login.
  AppUser? _saved(String authId) {
    final text = _store?.read(_savedKey);
    if (text is! String) return null;
    final json = jsonDecodeSafe(text);
    if (json is! Map || json['auth_id'] != authId) return null;
    return AppUser.fromJson((json['user']! as Map).cast<String, Object?>());
  }

  /// The account behind a session: a responder, or a resident record
  /// linked to the verified number. Dispatchers and admins use the web
  /// dashboard.
  Future<AppUser?> _account(String userId) async {
    final staff = await _client
        .from('staff')
        .select('id, display_name, email, role')
        .eq('id', userId)
        .maybeSingle();
    if (staff != null) {
      final user = AppUser.fromJson(staff);
      return user.role == UserRole.responder ? user : null;
    }
    final residentId = await _client.rpc<String?>('link_resident');
    if (residentId == null) return null;
    final row = await _client
        .from('resident_profile')
        .select('manila_resident_id, fullname')
        .eq('manila_resident_id', residentId)
        .single();
    return AppUser(
      id: row['manila_resident_id']! as String,
      displayName: row['fullname']! as String,
      email: '',
      role: UserRole.resident,
    );
  }

  Future<void> _onSession(Session? session) async {
    if (session == null) {
      _set(null);
      return;
    }
    if (_finishing) return;
    final id = session.user.id;
    if (_known && _user != null) return; // token refresh
    try {
      final user = await _account(id);
      if (user == null) {
        // A session without an account: registration was interrupted, or
        // a dashboard account.
        await _client.auth.signOut();
        return;
      }
      if (_client.auth.currentUser?.id == id) _set(user);
    } catch (_) {
      // Offline while restoring a session: use the account saved on the
      // phone, or show sign-in; the next auth event retries.
      final saved = _saved(id);
      if (saved != null) {
        _user = saved;
        _known = true;
        _changes.add(saved);
      } else if (!_known) {
        _set(null);
      }
    }
  }

  @override
  Stream<AppUser?> watchUser() {
    StreamSubscription<AppUser?>? sub;
    late final StreamController<AppUser?> controller;
    controller = StreamController<AppUser?>(
      onListen: () {
        if (_known) controller.add(_user);
        sub = _changes.stream.listen(controller.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  AppUser? get currentUser => _user;

  // -------------------------------------------------------- residents

  static String _normalized(String phone) {
    final n = normalizePhMobile(phone);
    if (n == null) {
      throw const PhoneAuthException(PhoneAuthFailure.invalidNumber);
    }
    return n;
  }

  static PhoneAuthException _phoneFailure(Object error) => PhoneAuthException(
    switch (error) {
      supa.AuthRetryableFetchException() => PhoneAuthFailure.offline,
      supa.AuthException(statusCode: '429') => PhoneAuthFailure.tooManyAttempts,
      supa.AuthException(code: 'over_sms_send_rate_limit') =>
        PhoneAuthFailure.tooManyAttempts,
      supa.AuthException(code: 'otp_expired') => PhoneAuthFailure.wrongCode,
      supa.AuthException() => PhoneAuthFailure.unavailable,
      _ => PhoneAuthFailure.offline,
    },
  );

  @override
  Future<void> sendCode(String phone) async {
    final n = _normalized(phone);
    try {
      await _client.auth.signInWithOtp(phone: n, shouldCreateUser: true);
    } catch (e) {
      throw _phoneFailure(e);
    }
  }

  @override
  Future<AppUser> verifyCode({
    required String phone,
    required String code,
  }) async {
    final n = _normalized(phone);
    _finishing = true;
    try {
      try {
        await _client.auth.verifyOTP(
          phone: n,
          token: code.trim(),
          type: OtpType.sms,
        );
      } on supa.AuthRetryableFetchException {
        throw const PhoneAuthException(PhoneAuthFailure.offline);
      } on supa.AuthException catch (e) {
        throw PhoneAuthException(
          e.statusCode == '429'
              ? PhoneAuthFailure.tooManyAttempts
              : PhoneAuthFailure.wrongCode,
        );
      } catch (_) {
        throw const PhoneAuthException(PhoneAuthFailure.offline);
      }

      final AppUser? user;
      try {
        final pending = _pending;
        if (pending != null && pending.phone == n) {
          await _client.rpc<String>(
            'register_resident',
            params: {
              'p_fullname': pending.fullName,
              'p_barangay': pending.barangay.name,
              'p_district': pending.barangay.district,
            },
          );
        }
        user = await _account(_client.auth.currentUser!.id);
      } catch (_) {
        await _client.auth.signOut();
        throw const PhoneAuthException(PhoneAuthFailure.offline);
      }
      if (user == null) {
        await _client.auth.signOut();
        throw const PhoneAuthException(PhoneAuthFailure.notRegistered);
      }
      _pending = null;
      _set(user);
      return user;
    } finally {
      _finishing = false;
    }
  }

  /// Keeps the details until the code is checked; a number that already
  /// has an account simply signs in.
  @override
  Future<void> register({
    required String fullName,
    required String phone,
    required Barangay barangay,
  }) async {
    final n = _normalized(phone);
    _pending = (phone: n, fullName: fullName.trim(), barangay: barangay);
    await sendCode(n);
  }

  @override
  Future<void> requestDataDeletion() =>
      _call(() => _client.rpc<void>('request_data_deletion'));

  // -------------------------------------------------------- responders

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final String id;
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      id = res.user!.id;
    } on supa.AuthRetryableFetchException {
      throw const AuthException(AuthFailure.offline);
    } on supa.AuthException catch (e) {
      throw AuthException(
        e.code == 'user_banned'
            ? AuthFailure.accountDisabled
            : AuthFailure.wrongCredentials,
      );
    } catch (_) {
      throw const AuthException(AuthFailure.offline);
    }
    final AppUser? user;
    try {
      user = await _account(id);
    } catch (_) {
      await _client.auth.signOut();
      throw const AuthException(AuthFailure.offline);
    }
    if (user == null || user.role != UserRole.responder) {
      await _client.auth.signOut();
      throw const AuthException(AuthFailure.notStaff);
    }
    _set(user);
    return user;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

// ----------------------------------------------------- vulnerability

class SupabaseVulnerabilityRepository implements VulnerabilityRepository {
  const SupabaseVulnerabilityRepository(this._client, this._changed);

  final SupabaseClient _client;

  /// Tells the profile stream to refetch: consent lives on the resident
  /// row, which realtime does not deliver.
  final StreamController<Object?> _changed;

  Future<void> _run(String name, [Map<String, Object?>? params]) async {
    await _call(() => _client.rpc<Object?>(name, params: params));
    _changed.add(null);
  }

  @override
  Future<void> giveConsent() => _run('give_consent');

  @override
  Future<void> withdrawConsent() => _run('withdraw_consent');

  @override
  Future<void> saveMember(VulnerableMember member) =>
      _run('save_vulnerable_member', {
        'p_member_id': member.id == null ? null : int.parse(member.id!),
        'p_label': member.label,
        'p_types': [for (final t in member.types) t.name],
        'p_notes': member.notes,
      });

  @override
  Future<void> removeMember(String memberId) =>
      _run('remove_vulnerable_member', {'p_member_id': int.parse(memberId)});
}

// ------------------------------------------------------------ alerts

class SupabaseAlertRepository implements AlertRepository {
  SupabaseAlertRepository(this._client);

  final SupabaseClient _client;
  final _refresh = StreamController<Object?>.broadcast();

  Future<AlertFeed> _fetch() async {
    final alerts = [
      for (final r
          in await _client
              .from('my_alerts')
              .select()
              .order('issued_at', ascending: false))
        PublicAlert.fromJson(r),
    ];
    // Residents see only their own profile row; responders have none.
    final me = await _client
        .from('resident_profile')
        .select('barangay')
        .maybeSingle();
    BarangayForecast? forecast;
    if (me != null) {
      final row = await _client
          .from('barangay_forecast')
          .select()
          .eq('barangay', me['barangay']! as String)
          .order('issued_at', ascending: false)
          .limit(1)
          .maybeSingle();
      forecast = row == null ? null : BarangayForecast.fromRow(row);
    }
    return AlertFeed(
      alerts: alerts,
      forecast: forecast,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Stream<AlertFeed> watch() => liveQuery(
    _client,
    tables: const ['public_alert', 'alert_read', 'barangay_forecast'],
    refreshOn: _refresh.stream,
    fetch: _fetch,
  );

  @override
  Future<void> refresh() async {
    try {
      await _client.from('public_alert').select('alert_id').limit(1);
    } catch (_) {
      throw const ActionRejected(ActionRejection.offline);
    }
    _refresh.add(null);
  }

  @override
  Future<void> markRead(String alertId) async {
    await _call(
      () =>
          _client.rpc<void>('mark_alert_read', params: {'p_alert_id': alertId}),
    );
    _refresh.add(null);
  }
}

// ------------------------------------------------------------ remote

/// The server calls behind the phone's records. Each takes the record's
/// client id and capture time, so the offline queue (part 6) can send the
/// same record again after a reconnect and the server stores it once
/// (NFR1, plan Q31).
class SupabaseMobileRemote implements MobileServer {
  const SupabaseMobileRemote(this._client);

  final SupabaseClient _client;

  static String _utc(DateTime t) => t.toUtc().toIso8601String();

  static List<Map<String, Object?>> _rows(Object? json) => [
    for (final r in (json as List<Object?>? ?? const []))
      (r! as Map).cast<String, Object?>(),
  ];

  // ------------------------------------------------------- resident

  /// Sends an SOS; returns the incident id (for example "INC-0152").
  @override
  Future<String> submitSos(SosRequest sos) => _call(
    () => _client.rpc<String>(
      'submit_sos',
      params: {
        'p_client_uuid': sos.clientId,
        'p_captured_at': _utc(sos.capturedAt),
        'p_latitude': sos.location?.lat,
        'p_longitude': sos.location?.lng,
        'p_accuracy_m': sos.accuracyMeters,
        'p_barangay': sos.barangay,
        'p_district': sos.district,
        'p_mock_location': sos.mockLocationSuspected,
      },
    ),
  );

  @override
  Future<void> addSosDetails(String clientId, SosDetails details) => _call(
    () => _client.rpc<void>(
      'add_sos_details',
      params: {
        'p_client_uuid': clientId,
        'p_type': details.type?.name,
        'p_people_count': details.peopleCount,
        'p_needs_extra_help': details.needsExtraHelp,
        'p_note': details.note,
      },
    ),
  );

  /// The resident's SOS requests as the server has them. Refreshes often
  /// while a unit is on the way: its position is not sent to residents by
  /// realtime.
  @override
  Stream<List<SosRequest>> watchMySos() => liveQuery(
    _client,
    tables: const ['incident_report', 'incident_event'],
    refreshEvery: const Duration(seconds: 10),
    fetch: () async => [
      for (final r in _rows(await _client.rpc<Object?>('my_sos')))
        SosRequest.fromJson(r),
    ],
  );

  /// Sends a hazard report; returns the report id. Throws [ReportRejected]
  /// for the server's FR15 checks.
  @override
  Future<String> submitReport(HazardReport report) => _call(
    () => _client.rpc<String>(
      'submit_crowd_report',
      params: {
        'p_client_uuid': report.clientId,
        'p_captured_at': _utc(report.capturedAt),
        'p_description': report.description,
        'p_type': report.type?.name,
        'p_latitude': report.location?.lat,
        'p_longitude': report.location?.lng,
        'p_accuracy_m': report.accuracyMeters,
        'p_barangay': report.barangay,
        'p_district': report.district,
      },
    ),
  );

  /// The resident's reports with their stage. Refreshes every minute:
  /// a report turns Not confirmed an hour after it was made.
  @override
  Stream<List<HazardReport>> watchMyReports() => liveQuery(
    _client,
    tables: const ['crowd_report'],
    refreshEvery: const Duration(minutes: 1),
    fetch: () async => [
      for (final r in _rows(await _client.rpc<Object?>('my_crowd_reports')))
        HazardReport.fromJson(r),
    ],
  );

  // ------------------------------------------------------ responder

  /// This responder's unit, or null if the account has no unit.
  @override
  Stream<ResponseUnit?> watchUnit() => liveQuery(
    _client,
    tables: const ['response_unit'],
    fetch: () async {
      final me = await _client
          .from('staff')
          .select('unit_id')
          .eq('id', _client.auth.currentUser?.id ?? '')
          .maybeSingle();
      final unitId = me?['unit_id'] as String?;
      if (unitId == null) return null;
      final row = await _client
          .from('response_unit')
          .select()
          .eq('unit_id', unitId)
          .maybeSingle();
      return row == null ? null : ResponseUnit.fromJson(row);
    },
  );

  /// Open assignments for this unit: status assigned is an offer,
  /// enRoute and onScene the current job.
  @override
  Stream<List<Assignment>> watchAssignments() => liveQuery(
    _client,
    tables: const ['incident_report', 'incident_event'],
    fetch: () async => [
      for (final r in _rows(await _client.rpc<Object?>('my_assignments')))
        Assignment.fromJson(r),
    ],
  );

  @override
  Future<void> accept(String incidentId, DateTime capturedAt) => _call(
    () => _client.rpc<void>(
      'accept_assignment',
      params: {'p_incident_id': incidentId, 'p_captured_at': _utc(capturedAt)},
    ),
  );

  @override
  Future<void> arrive(String incidentId, DateTime capturedAt) => _call(
    () => _client.rpc<void>(
      'mark_on_scene',
      params: {'p_incident_id': incidentId, 'p_captured_at': _utc(capturedAt)},
    ),
  );

  @override
  Future<void> confirmOnScene(
    String incidentId, {
    required bool realEmergency,
    required DateTime capturedAt,
    String? reason,
    int? peopleFound,
  }) => _call(
    () => _client.rpc<void>(
      'confirm_on_scene',
      params: {
        'p_incident_id': incidentId,
        'p_real_emergency': realEmergency,
        'p_reason': reason,
        'p_people_found': peopleFound,
        'p_captured_at': _utc(capturedAt),
      },
    ),
  );

  /// The F1 status control. Throws [StatusRejected] for refused moves.
  @override
  Future<void> setStatus(UnitStatus status, DateTime capturedAt) => _call(
    () => _client.rpc<void>(
      'set_unit_status',
      params: {'p_status': status.name, 'p_captured_at': _utc(capturedAt)},
    ),
  );

  @override
  Future<void> submitCompletion(CompletionReport report) => _call(
    () => _client.rpc<void>(
      'submit_completion_report',
      params: {
        'p_report_id': report.clientId,
        'p_incident_id': report.incidentId,
        'p_captured_at': _utc(report.capturedAt),
        'p_outcome': report.outcome.name,
        'p_persons_assisted': report.personsAssisted,
        'p_time_on_scene_s': report.timeOnScene.inSeconds,
        'p_houses_damaged': report.housesDamaged,
        'p_injured': report.injured,
        'p_missing': report.missing,
        'p_affected_families': report.affectedFamilies,
        'p_notes': report.notes,
      },
    ),
  );

  @override
  Future<void> updateLocation(GeoPoint point, DateTime capturedAt) => _call(
    () => _client.rpc<void>(
      'update_unit_location',
      params: {
        'p_latitude': point.lat,
        'p_longitude': point.lng,
        'p_captured_at': _utc(capturedAt),
      },
    ),
  );

  /// Finished jobs for this unit, newest first (F7).
  @override
  Stream<List<CompletedAssignment>> watchHistory() => liveQuery(
    _client,
    tables: const ['completion_report'],
    fetch: () async => [
      for (final r in _rows(await _client.rpc<Object?>('my_unit_history')))
        CompletedAssignment.fromJson(r),
    ],
  );
}
