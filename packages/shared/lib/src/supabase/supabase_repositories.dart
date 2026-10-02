import 'dart:async';

import 'package:supabase/supabase.dart' hide AuthException;
import 'package:supabase/supabase.dart'
    as supa
    show AuthException, AuthRetryableFetchException;

import '../models/account.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/assignment.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
import '../models/incident.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/settings.dart';
import '../models/sos.dart';
import '../offline/mobile_server.dart';
import '../offline/outbox.dart';
import '../offline/streams.dart';
import '../repositories/repositories.dart';
import 'live_query.dart';

part 'mobile_repositories.dart';
part 'web_form_repositories.dart';

// Supabase implementations of the repository interfaces (Phase 3 wiring,
// done early so demo data can be edited in the Supabase Table Editor).
//
// Reads go through tables and views protected by Row Level Security. Every
// write is a security-definer function in supabase/migrations that checks
// the caller's role and writes the audit log (FR11).

/// All repositories for one [SupabaseClient].
class SupabaseBackend {
  SupabaseBackend(SupabaseClient client)
    : auth = SupabaseAuthRepository(client),
      incidents = SupabaseIncidentRepository(client),
      units = SupabaseUnitRepository(client),
      crowdReports = SupabaseCrowdReportRepository(client),
      residents = SupabaseResidentRepository(client),
      weather = SupabaseWeatherRepository(client),
      audit = SupabaseAuditRepository(client),
      connection = SupabaseConnectionMonitor(client),
      routing = SupabaseRoutingLog(client),
      settings = SupabaseSettingsRepository(client),
      alertLog = SupabaseAlertLogRepository(client),
      simulation = SupabaseSimulationRepository(client),
      analytics = SupabaseAnalyticsRepository(client),
      resources = SupabaseResourceRepository(client),
      accounts = SupabaseAccountRepository(client);

  final SupabaseAuthRepository auth;
  final SupabaseIncidentRepository incidents;
  final SupabaseUnitRepository units;
  final SupabaseCrowdReportRepository crowdReports;
  final SupabaseResidentRepository residents;
  final SupabaseWeatherRepository weather;
  final SupabaseAuditRepository audit;
  final SupabaseConnectionMonitor connection;
  final SupabaseRoutingLog routing;
  final SupabaseSettingsRepository settings;
  final SupabaseAlertLogRepository alertLog;
  final SupabaseSimulationRepository simulation;
  final SupabaseAnalyticsRepository analytics;
  final SupabaseResourceRepository resources;
  final SupabaseAccountRepository accounts;
}

/// A1 through the admin_* functions (admins only). The staff table is not
/// sent over Realtime, so lists refresh after each change made here.
class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;
  final _changed = StreamController<Object?>.broadcast();

  Future<T> _change<T>(Future<T> Function() body) async {
    final result = await _call(body);
    _changed.add(null);
    return result;
  }

  @override
  Stream<List<StaffAccount>> watchStaff() => liveQuery(
    _client,
    tables: const ['response_unit'],
    refreshOn: _changed.stream,
    fetch: () async => [
      for (final r
          in await _client
              .from('staff')
              .select('id, display_name, email, role, unit_id, deactivated_at')
              .order('display_name'))
        StaffAccount.fromJson(r),
    ],
  );

  @override
  Stream<List<Resident>> watchResidents() => liveQuery(
    _client,
    tables: const ['vulnerable_member'],
    refreshOn: _changed.stream,
    fetch: () async => [
      for (final r
          in await _client.from('resident_profile').select().order('fullname'))
        Resident.fromJson(r),
    ],
  );

  @override
  Future<({String id, String temporaryPassword})> createStaff({
    required String email,
    required String displayName,
    required UserRole role,
    String? unitId,
  }) async {
    final json = await _change(
      () => _client.rpc<Map<String, dynamic>>(
        'admin_create_staff',
        params: {
          'p_email': email,
          'p_display_name': displayName,
          'p_role': role.name,
          'p_unit_id': unitId,
        },
      ),
    );
    return (
      id: json['id']! as String,
      temporaryPassword: json['temporary_password']! as String,
    );
  }

  @override
  Future<void> updateStaff(
    String id, {
    required String displayName,
    required UserRole role,
  }) => _change(
    () => _client.rpc<void>(
      'admin_update_staff',
      params: {
        'p_staff_id': id,
        'p_display_name': displayName,
        'p_role': role.name,
      },
    ),
  );

  @override
  Future<void> setStaffActive(String id, {required bool active}) => _change(
    () => _client.rpc<void>(
      'admin_set_staff_active',
      params: {'p_staff_id': id, 'p_active': active},
    ),
  );

  @override
  Future<String> resetPassword(String id) async {
    final json = await _change(
      () => _client.rpc<Map<String, dynamic>>(
        'admin_reset_password',
        params: {'p_staff_id': id},
      ),
    );
    return json['temporary_password']! as String;
  }

  @override
  Future<void> setResidentSuspended(
    String residentId, {
    required bool suspended,
  }) => _change(
    () => _client.rpc<void>(
      'admin_set_resident_suspended',
      params: {'p_resident_id': residentId, 'p_suspended': suspended},
    ),
  );
}

/// A2 through `save_unit`, `retire_unit`, `restore_unit`, and
/// `set_responder_unit` (admins only). The staff table is not sent over
/// Realtime, so the roster refreshes after each change made here.
class SupabaseResourceRepository implements ResourceRepository {
  SupabaseResourceRepository(this._client);

  final SupabaseClient _client;
  final _changed = StreamController<Object?>.broadcast();

  @override
  Stream<List<ResponseUnit>> watchUnits() => liveQuery(
    _client,
    tables: const ['response_unit'],
    refreshOn: _changed.stream,
    fetch: () async => [
      for (final r
          in await _client.from('response_unit').select().order('call_sign'))
        ResponseUnit.fromJson(r),
    ],
  );

  @override
  Stream<List<StaffAccount>> watchResponders() => liveQuery(
    _client,
    tables: const ['response_unit'],
    refreshOn: _changed.stream,
    fetch: () async => [
      for (final r
          in await _client
              .from('staff')
              .select('id, display_name, email, role, unit_id')
              .eq('role', 'responder')
              .order('display_name'))
        StaffAccount.fromJson(r),
    ],
  );

  Future<T> _change<T>(Future<T> Function() body) async {
    final result = await _call(body);
    _changed.add(null);
    return result;
  }

  @override
  Future<String> saveUnit({
    String? id,
    required String callSign,
    required UnitType type,
    required String station,
    required int crewSize,
  }) => _change(
    () => _client.rpc<String>(
      'save_unit',
      params: {
        'p_unit_id': id,
        'p_call_sign': callSign,
        'p_unit_type': type.name,
        'p_station': station,
        'p_crew_size': crewSize,
      },
    ),
  );

  @override
  Future<void> retireUnit(String id) => _change(
    () => _client.rpc<void>('retire_unit', params: {'p_unit_id': id}),
  );

  @override
  Future<void> restoreUnit(String id) => _change(
    () => _client.rpc<void>('restore_unit', params: {'p_unit_id': id}),
  );

  @override
  Future<void> setResponderUnit(String staffId, String? unitId) => _change(
    () => _client.rpc<void>(
      'set_responder_unit',
      params: {'p_staff_id': staffId, 'p_unit_id': unitId},
    ),
  );
}

/// A4 through `analytics_report` (admins only).
class SupabaseAnalyticsRepository implements AnalyticsRepository {
  const SupabaseAnalyticsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AnalyticsReport> report(DateTime from, DateTime to) async {
    final json = await _call(
      () => _client.rpc<Map<String, dynamic>>(
        'analytics_report',
        params: {
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
        },
      ),
    );
    return AnalyticsReport.fromJson(json);
  }
}

/// A3 settings (`app_setting`), live over Realtime; changes go through
/// `set_setting`, which checks the admin role and audits.
class SupabaseSettingsRepository implements SettingsRepository {
  const SupabaseSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<AppSetting>> watch() => liveQuery(
    _client,
    tables: const ['app_setting'],
    fetch: () async {
      final rows = await _client.from('app_setting').select().order('key');
      return [for (final r in rows) AppSetting.fromJson(r)];
    },
  );

  @override
  Future<void> set(String key, Object value) async {
    try {
      await _call(
        () => _client.rpc<void>(
          'set_setting',
          params: {'p_key': key, 'p_value': value},
        ),
      );
    } on ActionRejected catch (e) {
      // not_found means an unknown setting here, not a closed incident.
      if (e.reason == ActionRejection.incidentClosed) {
        throw const ActionRejected(ActionRejection.notFound);
      }
      rethrow;
    }
  }
}

/// D10's alert log: `public_alert` with its `alert_delivery` rows.
class SupabaseAlertLogRepository implements AlertLogRepository {
  const SupabaseAlertLogRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<SentAlert>> watchRecent({int limit = 30}) => liveQuery(
    _client,
    tables: const ['public_alert', 'alert_delivery'],
    fetch: () async => [
      for (final r
          in await _client
              .from('public_alert')
              .select('*, alert_delivery(*)')
              .order('issued_at', ascending: false)
              .limit(limit))
        SentAlert.fromJson(r),
    ],
  );

  @override
  Future<String> issue({
    required AlertSource source,
    required AlertLevel level,
    required String title,
    required String body,
    List<String> guidance = const [],
    List<String> barangays = const [],
  }) => _call(
    () => _client.rpc<String>(
      'issue_alert',
      params: {
        'p_source': source.name,
        'p_level': level.name,
        'p_title': title,
        'p_body': body,
        'p_guidance': guidance,
        'p_barangays': barangays,
      },
    ),
  );

  @override
  Future<void> end(String alertId) async {
    try {
      await _call(
        () => _client.rpc<void>('end_alert', params: {'p_alert_id': alertId}),
      );
    } on ActionRejected catch (e) {
      // not_found means an unknown alert here, not a closed incident.
      if (e.reason == ActionRejection.incidentClosed) {
        throw const ActionRejected(ActionRejection.notFound);
      }
      rethrow;
    }
  }
}

/// Simulation mode through `simulate_weather` (admins only).
class SupabaseSimulationRepository implements SimulationRepository {
  const SupabaseSimulationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> simulateWeather({
    required int signal,
    required double rainfallMmPerHour,
    double? surgeMeters,
  }) => _call(
    () => _client.rpc<void>(
      'simulate_weather',
      params: {
        'p_signal': signal,
        'p_rainfall': rainfallMmPerHour,
        'p_surge_m': surgeMeters,
      },
    ),
  );
}

/// The hotline and SMS gateway number from `client_config()`, which needs
/// no account.
class SupabaseClientConfigRepository implements ClientConfigRepository {
  const SupabaseClientConfigRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ClientConfig> fetch() async => ClientConfig.fromJson(
    await _client.rpc<Map<String, dynamic>>('client_config'),
  );
}

/// Sends each timed Dijkstra run to `log_routing_run` (plan 10.2). Failures
/// are dropped: the timing log must never get in the way of dispatch.
class SupabaseRoutingLog implements RoutingLogRepository {
  SupabaseRoutingLog(this._client);

  final SupabaseClient _client;

  @override
  void log(RoutingRun run) {
    unawaited(
      _client
          .rpc<void>(
            'log_routing_run',
            params: {
              'p_kind': run.kind.name,
              'p_platform': run.platform.name,
              'p_compute_ms': run.computeMs,
              'p_incident_id': run.incidentId,
              'p_candidates': run.candidates,
              'p_node_count': run.nodeCount,
              'p_edge_count': run.edgeCount,
              'p_graph_built': run.graphBuilt == null
                  ? null
                  : dateOnly(run.graphBuilt!),
            },
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

typedef _Row = Map<String, dynamic>;

// ------------------------------------------------------------------- auth

/// Staff sign-in. Only accounts with a row in `staff` get in; anyone else is
/// signed out again (residents use the mobile app).
class SupabaseAuthRepository implements AuthRepository, StaffSessionRepository {
  SupabaseAuthRepository(this._client) {
    _client.auth.onAuthStateChange.listen(
      (state) => _onSession(state.session),
      onError: (Object _) {},
    );
  }

  final SupabaseClient _client;
  final _changes = StreamController<AppUser?>.broadcast();
  final _expired = StreamController<void>.broadcast();
  AppUser? _user;
  var _known = false;
  var _signingOut = false;
  final _staff = <String, Future<AppUser?>>{};

  void _set(AppUser? user) {
    _user = user;
    _known = true;
    _changes.add(user);
  }

  Future<AppUser?> _staffRow(String userId) => _staff[userId] ??= _client
      .from('staff')
      .select('id, display_name, email, role')
      .eq('id', userId)
      .maybeSingle()
      .then((row) => row == null ? null : AppUser.fromJson(row));

  Future<void> _onSession(Session? session) async {
    if (session == null) {
      _staff.clear();
      // Signed in a moment ago and nobody chose to sign out: it expired.
      if (_user != null && !_signingOut) _expired.add(null);
      _signingOut = false;
      _set(null);
      return;
    }
    final id = session.user.id;
    if (_known && _user?.id == id) return; // token refresh
    try {
      final user = await _staffRow(id);
      if (user == null) {
        await _client.auth.signOut();
        return;
      }
      if (_client.auth.currentUser?.id == id) _set(user);
    } catch (_) {
      // Offline while restoring a session: forget the cached lookup and
      // show sign-in; the next auth event retries.
      _staff.remove(id);
      if (!_known) _set(null);
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

  @override
  Stream<void> watchExpired() => _expired.stream;

  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const AuthException(AuthFailure.notStaff);
    if (next.length < StaffSessionRepository.minPasswordLength) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    try {
      // Checking the current password is a fresh sign-in as the same user.
      await _client.auth.signInWithPassword(email: email, password: current);
    } on supa.AuthRetryableFetchException {
      throw const AuthException(AuthFailure.offline);
    } on supa.AuthException {
      throw const AuthException(AuthFailure.wrongCredentials);
    } catch (_) {
      throw const AuthException(AuthFailure.offline);
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: next));
    } on supa.AuthRetryableFetchException {
      throw const AuthException(AuthFailure.offline);
    } on supa.AuthException {
      // For example the project's password rules.
      throw const ActionRejected(ActionRejection.invalidValue);
    } catch (_) {
      throw const AuthException(AuthFailure.offline);
    }
  }

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
      user = await _staffRow(id);
    } catch (_) {
      _staff.remove(id);
      await _client.auth.signOut();
      throw const AuthException(AuthFailure.offline);
    }
    if (user == null) {
      await _client.auth.signOut();
      throw const AuthException(AuthFailure.notStaff);
    }
    _set(user);
    return user;
  }

  @override
  Future<void> signOut() {
    // Cleared when the signed-out event arrives (it may come later).
    _signingOut = true;
    return _client.auth.signOut();
  }
}

// -------------------------------------------------------------- incidents

class SupabaseIncidentRepository implements IncidentRepository {
  const SupabaseIncidentRepository(this._client);

  final SupabaseClient _client;

  static const _boardTables = [
    'incident_report',
    'incident_event',
    'crowd_report',
  ];

  List<Incident> _incidents(List<_Row> rows) => [
    for (final r in rows) Incident.fromJson(r),
  ];

  @override
  Stream<List<Incident>> watchActive() => liveQuery(
    _client,
    tables: _boardTables,
    fetch: () async => _incidents(
      await _client
          .from('incident_board')
          .select()
          .neq('status', IncidentStatus.resolved.name)
          .order('received_at'),
    ),
  );

  @override
  Stream<List<Incident>> watchResolved({
    Duration since = const Duration(hours: 12),
  }) => liveQuery(
    _client,
    tables: _boardTables,
    fetch: () async => _incidents(
      await _client
          .from('incident_board')
          .select()
          .eq('status', IncidentStatus.resolved.name)
          .gte('resolved_at', _utcAgo(since))
          .order('resolved_at', ascending: false),
    ),
  );

  @override
  Future<void> verify(String incidentId, VerificationMethod method) => _rpc(
    'verify_incident',
    {'p_incident_id': incidentId, 'p_method': method.name},
  );

  @override
  Future<void> sendSmsCheck(String incidentId) =>
      _rpc('send_sms_check', {'p_incident_id': incidentId});

  @override
  Future<void> markFalseReport(String incidentId, {String? reason}) => _rpc(
    'mark_false_report',
    {'p_incident_id': incidentId, 'p_reason': reason},
  );

  @override
  Future<void> confirmType(String incidentId, IncidentType type) => _rpc(
    'confirm_incident_type',
    {'p_incident_id': incidentId, 'p_type': type.name},
  );

  @override
  Future<void> assignUnit(
    String incidentId,
    String unitId, {
    String? overrideReason,
    RoadRoute? route,
  }) => _rpc('assign_unit', {
    'p_incident_id': incidentId,
    'p_unit_id': unitId,
    'p_override_reason': overrideReason,
    if (route != null) 'p_route': route.toJson(),
  });

  @override
  Future<void> resolve(String incidentId) =>
      _rpc('resolve_incident', {'p_incident_id': incidentId});

  Future<void> _rpc(String name, Map<String, Object?> params) =>
      _call(() => _client.rpc<void>(name, params: params));
}

// ------------------------------------------------------------------ units

class SupabaseUnitRepository implements UnitRepository {
  const SupabaseUnitRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<ResponseUnit>> watchAll() => liveQuery(
    _client,
    tables: const ['response_unit'],
    fetch: () async => [
      // Retired units are not dispatched; A2 lists them separately.
      for (final r
          in await _client
              .from('response_unit')
              .select()
              .isFilter('retired_at', null)
              .order('call_sign'))
        ResponseUnit.fromJson(r),
    ],
  );
}

// ---------------------------------------------------------- crowd reports

class SupabaseCrowdReportRepository implements CrowdReportRepository {
  const SupabaseCrowdReportRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<CrowdReport>> watchRecent({
    Duration window = const Duration(minutes: 60),
  }) => liveQuery(
    _client,
    tables: const ['crowd_report'],
    // Old reports leave the window even when nothing new arrives.
    refreshEvery: const Duration(minutes: 1),
    fetch: () async => [
      for (final r
          in await _client
              .from('crowd_report')
              .select()
              .gte('submitted_at', _utcAgo(window))
              .order('submitted_at', ascending: false))
        CrowdReport.fromJson(r),
    ],
  );
}

// -------------------------------------------------------------- residents

class SupabaseResidentRepository implements ResidentRepository {
  const SupabaseResidentRepository(this._client, {this.refreshOn});

  final SupabaseClient _client;

  /// Emits after the app changes the resident record itself (consent),
  /// which realtime does not deliver.
  final Stream<Object?>? refreshOn;

  // manila_resident is not in the realtime publication (its full contact
  // number column is hidden from clients), so household changes drive
  // refreshes.
  static const _tables = ['vulnerable_member'];

  @override
  Stream<Resident?> watchResident(String residentId) => liveQuery(
    _client,
    tables: _tables,
    refreshOn: refreshOn,
    fetch: () async {
      final row = await _client
          .from('resident_profile')
          .select()
          .eq('manila_resident_id', residentId)
          .maybeSingle();
      return row == null ? null : Resident.fromJson(row);
    },
  );

  @override
  Stream<List<Resident>> watchVulnerable() => liveQuery(
    _client,
    tables: _tables,
    fetch: () async => [
      for (final r
          in await _client
              .from('vulnerable_resident_list')
              .select()
              .order('fullname'))
        Resident.fromJson(r),
    ],
  );

  @override
  Future<String> revealContact(String residentId) => _call(
    () => _client.rpc<String>(
      'reveal_resident_contact',
      params: {'p_resident_id': residentId},
    ),
  );
}

// ---------------------------------------------------------------- weather

class SupabaseWeatherRepository implements WeatherRepository {
  const SupabaseWeatherRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<WeatherStatus> watchCurrent() => liveQuery(
    _client,
    tables: const ['weather_alert'],
    fetch: () async {
      final row = await _client
          .from('weather_alert')
          .select()
          .order('issued_at', ascending: false)
          .limit(1)
          .maybeSingle();
      // No reading is an error, not "no signal": a calm default could
      // mislead a dispatcher during a typhoon.
      if (row == null) throw StateError('No weather reading yet');
      return WeatherStatus.fromJson(row);
    },
  );
}

// ------------------------------------------------------------------ audit

class SupabaseAuditRepository implements AuditRepository {
  const SupabaseAuditRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 200}) => liveQuery(
    _client,
    tables: const ['audit_log'],
    fetch: () async => [
      for (final r
          in await _client
              .from('audit_log')
              .select()
              .order('timestamp', ascending: false)
              .order('log_id', ascending: false)
              .limit(limit))
        AuditEntry.fromJson(r),
    ],
  );
}

// ------------------------------------------------------------- connection

/// Reports the realtime link: joined means live, an error or timeout means
/// the client is retrying, and a closed channel means offline.
class SupabaseConnectionMonitor implements ConnectionMonitor {
  SupabaseConnectionMonitor(this._client);

  final SupabaseClient _client;
  final _changes = StreamController<LinkState>.broadcast();
  RealtimeChannel? _channel;
  LinkState? _state;

  void _start() {
    _channel ??= _client.channel('sagip-link').subscribe((status, _) {
      final next = switch (status) {
        RealtimeSubscribeStatus.subscribed => LinkState.live,
        RealtimeSubscribeStatus.channelError ||
        RealtimeSubscribeStatus.timedOut => LinkState.reconnecting,
        RealtimeSubscribeStatus.closed => LinkState.offline,
      };
      if (next == _state) return;
      _state = next;
      _changes.add(next);
    });
  }

  @override
  Stream<LinkState> watch() {
    _start();
    StreamSubscription<LinkState>? sub;
    late final StreamController<LinkState> controller;
    controller = StreamController<LinkState>(
      onListen: () {
        // Nothing until the first status: unknown counts as online, so the
        // banner does not flash on start.
        final state = _state;
        if (state != null) controller.add(state);
        sub = _changes.stream.listen(controller.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}

// ---------------------------------------------------------------- helpers

String _utcAgo(Duration d) =>
    DateTime.now().toUtc().subtract(d).toIso8601String();

/// The exception for a refusal code raised by a database function
/// (supabase/migrations/*dispatch_actions and *mobile_actions).
Exception databaseRefusal(String code) => switch (code) {
  'outside_manila' => const ReportRejected(ReportRejection.outsideManila),
  'rate_limited' => const ReportRejected(ReportRejection.rateLimited),
  'no_location' => const ReportRejected(ReportRejection.noLocation),
  'account_suspended' => const ReportRejected(ReportRejection.accountSuspended),
  'own_account' => const ActionRejected(ActionRejection.ownAccount),
  'last_admin' => const ActionRejected(ActionRejection.lastAdmin),
  'no_assignment' => const StatusRejected(StatusRejection.noAssignment),
  'finish_report_first' => const StatusRejected(
    StatusRejection.finishReportFirst,
  ),
  'already_on_scene' => const StatusRejected(StatusRejection.alreadyOnScene),
  'unit_not_available' => const ActionRejected(
    ActionRejection.unitNotAvailable,
  ),
  'already_assigned' => const ActionRejected(ActionRejection.alreadyAssigned),
  'invalid_value' => const ActionRejected(ActionRejection.invalidValue),
  'already_exists' => const ActionRejected(ActionRejection.alreadyExists),
  'incident_closed' ||
  'not_found' => const ActionRejected(ActionRejection.incidentClosed),
  _ => const ActionRejected(ActionRejection.notAllowed),
};

/// Runs a database function and turns its refusals into the app's
/// exceptions ([databaseRefusal]); network failures become offline.
Future<T> _call<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PostgrestException catch (e) {
    throw databaseRefusal(e.message);
  } on ActionRejected {
    rethrow;
  } on Exception {
    // Network failures surface as client exceptions from the HTTP layer.
    throw const ActionRejected(ActionRejection.offline);
  }
}
