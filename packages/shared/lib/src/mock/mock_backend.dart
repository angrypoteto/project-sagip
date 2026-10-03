import 'dart:async';

import 'package:flutter/foundation.dart';

import '../algorithms/alert_thresholds.dart';
import '../algorithms/analytics.dart';
import '../algorithms/dbscan.dart';
import '../algorithms/priority.dart';
import '../algorithms/report_draft.dart';
import '../algorithms/setting_checks.dart';
import '../data/manila_barangays.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
import '../models/ndrrmc.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';
import 'live_value.dart';
import 'mock_seed.dart';

/// In-memory stand-in for the Supabase backend during Phase 1.
///
/// It enforces the same rules the database will (role checks, unit
/// availability, audit entries for every action) so the dashboard can be
/// built and tested before the real backend exists. [startSimulation] makes
/// it feel live: a new SOS arrives, a crowd-report cluster forms, and units
/// accept, drive, arrive, and finish on their own.
class MockBackend {
  MockBackend({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
  }) : _clock = clock ?? DateTime.now {
    _seed = MockSeed(_clock());
    _staff = _seed.staff;
    _incidents = LiveValue({for (final i in _seed.incidents) i.id: i});
    _resolved = LiveValue(_seed.pastIncidents);
    _completions = {..._seed.pastCompletions};
    _units = LiveValue({for (final u in _seed.units) u.id: u});
    _reports = LiveValue(_seed.crowdReports);
    _residents = LiveValue({for (final r in _seed.residents) r.id: r});
    _audit = LiveValue(_seed.audit);
    _weather = LiveValue(_seed.weather);
    _alertLog = LiveValue(_seed.sentAlerts);
    _forecast = LiveValue(ForecastRun.latest(_seed.forecasts));
  }

  final DateTime Function() _clock;

  /// Artificial delay on every action, so loading states are visible.
  final Duration latency;

  late final MockSeed _seed;
  late final List<AppUser> _staff;
  late final LiveValue<Map<String, Incident>> _incidents;
  late final LiveValue<List<Incident>> _resolved;
  late final LiveValue<Map<String, ResponseUnit>> _units;
  late final LiveValue<List<CrowdReport>> _reports;
  late final LiveValue<Map<String, Resident>> _residents;
  late final LiveValue<List<AuditEntry>> _audit;
  late final LiveValue<WeatherStatus> _weather;
  late final LiveValue<List<SentAlert>> _alertLog;
  late final LiveValue<ForecastRun?> _forecast;

  /// What responders reported, by incident (the dashboard mock has no
  /// phones, so only the past rescues have one).
  late final Map<String, DamageRecord> _completions;
  final _ndrrmcReports = LiveValue<List<NdrrmcReport>>(const []);
  final _feeds = LiveValue<List<FeedStatus>>(const []);

  /// The PAGASA feed's health (D10); none on sample data.
  Stream<List<FeedStatus>> watchFeeds() => _feeds.watch();

  /// For tests: what the feed reported.
  void setFeeds(List<FeedStatus> feeds) => _feeds.value = feeds;
  var _nextReportNumber = 1;
  var _nextAlertNumber = 1;
  var _weatherSimulated = false;
  final _user = LiveValue<AppUser?>(null);
  final _link = LiveValue<LinkState>(LinkState.live);

  // Simulation bookkeeping.
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _sosDelivered = false;
  bool _clusterReportAdded = false;
  int _nextIncidentNumber = 151;
  int _nextAuditNumber = 2000;
  final _assignedAt = <String, DateTime>{};
  final _routes = <String, RoadRoute>{};

  /// Every staff account (A1), responders included (A2 roster).
  late final LiveValue<Map<String, StaffAccount>> _accounts = LiveValue({
    for (final u in _staff)
      u.id: StaffAccount(
        id: u.id,
        displayName: u.displayName,
        email: u.email,
        role: u.role,
      ),
    for (final s in _seed.responders) s.id: s,
  });
  final _settings = LiveValue<Map<String, AppSetting>>({
    for (final s in defaultPrioritySettings) s.key: s,
    for (final s in defaultOtherSettings) s.key: s,
  });

  Stream<List<AppSetting>> watchSettings() => _settings.watch().map(
    (m) => [...m.values]..sort((a, b) => a.key.compareTo(b.key)),
  );

  /// A3: admins only, checked like `set_setting`, and audited (FR11).
  Future<void> setSetting(String key, Object value) async {
    final actor = await _authorize();
    if (!actor.isAdmin) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    final problem = checkSetting(_settings.value, key, value);
    if (problem != null) throw ActionRejected(problem);
    final old = _settings.value[key]!;
    final next = normalizeSetting(key, value);
    if (old.value == next) return;
    _settings.value = {
      ..._settings.value,
      key: old.copyWith(
        value: next,
        updatedAt: _clock(),
        updatedBy: actor.displayName,
      ),
    };
    _log(
      actor,
      AuditAction.settingChanged,
      'app_setting',
      key,
      '${_shown(old.value)} → ${_shown(next)}',
    );
  }

  /// A setting value as the audit log writes it.
  static String _shown(Object v) => v is num ? _plain(v) : '$v';

  bool _flag(String key) => _settings.value[key]?.value == true;

  /// What the apps read before sign-in (`client_config()`).
  ClientConfig get clientConfig => ClientConfig(
    hotline: '${_settings.value[SettingKeys.hotline]?.value ?? ''}',
    smsGateway: '${_settings.value[SettingKeys.smsGateway]?.value ?? ''}',
  );

  // ------------------------------------------------------- alerts (FR5, FR6)

  /// D10: alerts with their deliveries, newest first.
  Stream<List<SentAlert>> watchAlertLog(int limit) => _alertLog.watch().map(
    (all) =>
        ([...all]..sort((a, b) => b.alert.issuedAt.compareTo(a.alert.issuedAt)))
            .take(limit)
            .toList(growable: false),
  );

  /// One delivery row per channel, as `private.queue_alert_deliveries`
  /// writes them.
  List<AlertDelivery> _deliveriesFor({required bool simulated}) => [
    for (final c in AlertChannel.values)
      AlertDelivery(
        channel: c,
        status: c == AlertChannel.app
            ? AlertDeliveryStatus.sent
            : simulated
            ? AlertDeliveryStatus.simulated
            : !_flag('channels.${c.name}')
            ? AlertDeliveryStatus.off
            : AlertDeliveryStatus.queued,
      ),
  ];

  /// The threshold engine (`private.raise_weather_alerts`): when a hazard's
  /// level changes, its earlier automatic alerts expire and, at warning or
  /// critical, a new one is issued.
  void _applyReading(WeatherStatus previous, WeatherStatus reading) {
    final thresholds = AlertThresholds.fromSettings(_settings.value.values);
    var log = _alertLog.value;
    for (final change in thresholds.changes(previous, reading)) {
      log = [
        for (final entry in log)
          entry.alert.hazard == change.hazard &&
                  entry.alert.activeAt(reading.issuedAt)
              ? SentAlert(
                  alert: entry.alert.copyWith(expiresAt: reading.issuedAt),
                  deliveries: entry.deliveries,
                )
              : entry,
      ];
      final level = change.level;
      if (level == null) continue;
      final words = weatherAlertText(change.hazard, level, change.value!);
      log = [
        ...log,
        SentAlert(
          alert: PublicAlert(
            id: 'alert-auto-${_nextAlertNumber++}',
            source: AlertSource.pagasa,
            level: level,
            title: words.title,
            body: words.body,
            guidance: words.guidance,
            issuedAt: reading.issuedAt,
            isSimulated: reading.isSimulated,
            hazard: change.hazard,
          ),
          deliveries: _deliveriesFor(simulated: reading.isSimulated),
        ),
      ];
    }
    _alertLog.value = log;
  }

  /// D10 (`issue_alert`): dispatchers and admins. Simulated while
  /// simulation mode is on. Audited.
  Future<String> issueAlert({
    required AlertSource source,
    required AlertLevel level,
    required String title,
    required String body,
    List<String> guidance = const [],
    List<String> barangays = const [],
  }) async {
    final actor = await _authorize();
    final steps = [
      for (final g in guidance)
        if (g.trim().isNotEmpty) g.trim(),
    ];
    final areas = {
      for (final b in barangays)
        if (b.trim().isNotEmpty) b.trim(),
    }.toList()..sort();
    final known = {for (final b in manilaBarangays) b.name};
    if (!AdvisoryRules.accepts(title: title, body: body, guidance: steps) ||
        areas.any((a) => !known.contains(a))) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    final simulated = _flag(SettingKeys.simulation);
    final id = 'alert-staff-${_nextAlertNumber++}';
    _alertLog.value = [
      ..._alertLog.value,
      SentAlert(
        alert: PublicAlert(
          id: id,
          source: source,
          level: level,
          title: title.trim(),
          body: body.trim(),
          guidance: steps,
          barangays: areas,
          issuedAt: _clock(),
          isSimulated: simulated,
        ),
        deliveries: _deliveriesFor(simulated: simulated),
      ),
    ];
    _log(
      actor,
      AuditAction.alertIssued,
      'public_alert',
      id,
      '${level.name}: ${title.trim()}${simulated ? ' (simulated)' : ''}',
    );
    return id;
  }

  /// D10 (`end_alert`): ending one that already ended does nothing. What
  /// was still waiting to be sent is not sent.
  Future<void> endAlert(String alertId) async {
    final actor = await _authorize();
    final now = _clock();
    final entry = _alertLog.value
        .where((e) => e.alert.id == alertId)
        .firstOrNull;
    if (entry == null) throw const ActionRejected(ActionRejection.notFound);
    if (!entry.alert.activeAt(now)) return;
    _alertLog.value = [
      for (final e in _alertLog.value)
        e.alert.id == alertId
            ? SentAlert(
                alert: e.alert.copyWith(expiresAt: now),
                // What `send-alerts` does with a queued delivery of an
                // alert that has ended: it is not sent.
                deliveries: [
                  for (final d in e.deliveries)
                    d.status == AlertDeliveryStatus.queued
                        ? AlertDelivery(
                            channel: d.channel,
                            status: AlertDeliveryStatus.ended,
                          )
                        : d,
                ],
              )
            : e,
    ];
    _log(
      actor,
      AuditAction.alertEnded,
      'public_alert',
      alertId,
      entry.alert.title,
    );
  }

  /// Simulation mode (`simulate_weather`): admins only, only while the
  /// mode is on, audited.
  Future<void> simulateWeather({
    required int signal,
    required double rainfallMmPerHour,
    double? surgeMeters,
  }) async {
    final actor = await _authorize();
    if (!actor.isAdmin || !_flag(SettingKeys.simulation)) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    final surge = surgeMeters == null || surgeMeters == 0 ? null : surgeMeters;
    if (signal < 0 ||
        signal > 5 ||
        rainfallMmPerHour < 0 ||
        rainfallMmPerHour > 500 ||
        (surge != null && (surge < 0 || surge > 10))) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    final previous = _weather.value;
    _weatherSimulated = true;
    final reading = WeatherStatus(
      signalLevel: signal,
      rainfallMmPerHour: rainfallMmPerHour,
      stormSurgeAdvisory: surge == null
          ? null
          : 'Storm surge up to ${_plain(surge)} m possible along Manila Bay',
      stormSurgeMeters: surge,
      issuedAt: _clock(),
      isSimulated: true,
    );
    _weather.value = reading;
    _applyReading(previous, reading);
    _log(
      actor,
      AuditAction.weatherSimulated,
      'weather_alert',
      'sim-$_nextAuditNumber',
      'Signal $signal, ${_plain(rainfallMmPerHour)} mm/hr'
          '${surge == null ? '' : ', surge ${_plain(surge)} m'}',
    );
  }

  /// A5: every report, newest first.
  Stream<List<NdrrmcReport>> watchNdrrmcReports() => _ndrrmcReports.watch().map(
    (all) => [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  ReportSource _reportSource(DateTime from, DateTime to) {
    if (!to.isAfter(from) || to.difference(from) > const Duration(days: 400)) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    return buildReportSource(
      incidents: [..._incidents.value.values, ..._resolved.value],
      completions: _completions,
      alerts: [for (final a in _alertLog.value) a.alert],
      // The mock keeps only the current reading.
      readings: [_weather.value],
      from: from,
      to: to,
    );
  }

  /// A6 (`report_source`): admins only.
  Future<ReportSource> reportSource(DateTime from, DateTime to) async {
    await _authorizeAdmin();
    return _reportSource(from, to);
  }

  /// A6 (`save_ndrrmc_report`): a new draft keeps the period's figures as
  /// they are now; an existing draft only changes its text.
  Future<String> saveNdrrmcReport({
    String? id,
    required DateTime from,
    required DateTime to,
    required String title,
    required List<ReportSection> sections,
    int? generationMs,
  }) async {
    final actor = await _authorizeAdmin();
    if (!reportTextAccepted(title, sections)) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    final now = _clock();
    if (id == null) {
      final source = _reportSource(from, to);
      final newId = 'RPT-${(_nextReportNumber++).toString().padLeft(4, '0')}';
      _ndrrmcReports.value = [
        ..._ndrrmcReports.value,
        NdrrmcReport(
          id: newId,
          title: title.trim(),
          status: ReportStatus.draft,
          source: source,
          sections: sections,
          createdByName: actor.displayName,
          createdAt: now,
          updatedAt: now,
          generationMs: generationMs,
        ),
      ];
      _log(
        actor,
        AuditAction.reportDrafted,
        'ndrrmc_report',
        newId,
        title.trim(),
      );
      return newId;
    }
    final existing = _ndrrmcReports.value.where((r) => r.id == id).firstOrNull;
    if (existing == null) throw const ActionRejected(ActionRejection.notFound);
    if (existing.isFinal) {
      throw const ActionRejected(ActionRejection.alreadyFinal);
    }
    _replaceReport(
      NdrrmcReport(
        id: existing.id,
        title: title.trim(),
        status: existing.status,
        source: existing.source,
        sections: sections,
        createdByName: existing.createdByName,
        createdAt: existing.createdAt,
        updatedAt: now,
        method: existing.method,
        generationMs: existing.generationMs,
      ),
    );
    return id;
  }

  /// A6 (`finalize_ndrrmc_report`).
  Future<void> finalizeNdrrmcReport(String id) async {
    final actor = await _authorizeAdmin();
    final existing = _ndrrmcReports.value.where((r) => r.id == id).firstOrNull;
    if (existing == null) throw const ActionRejected(ActionRejection.notFound);
    if (existing.isFinal) {
      throw const ActionRejected(ActionRejection.alreadyFinal);
    }
    final now = _clock();
    _replaceReport(
      NdrrmcReport(
        id: existing.id,
        title: existing.title,
        status: ReportStatus.finalized,
        source: existing.source,
        sections: existing.sections,
        createdByName: existing.createdByName,
        createdAt: existing.createdAt,
        updatedAt: now,
        method: existing.method,
        generationMs: existing.generationMs,
        finalizedAt: now,
        finalizedByName: actor.displayName,
      ),
    );
    _log(
      actor,
      AuditAction.reportFinalized,
      'ndrrmc_report',
      id,
      existing.title,
    );
  }

  void _replaceReport(NdrrmcReport report) {
    _ndrrmcReports.value = [
      for (final r in _ndrrmcReports.value) r.id == report.id ? report : r,
    ];
  }

  /// A4, admins only; the same definitions as `analytics_report`.
  Future<AnalyticsReport> analytics(
    DateTime from,
    DateTime to, {
    Iterable<RoutingRun> runs = const [],
  }) async {
    final actor = await _authorize();
    if (!actor.isAdmin) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    if (!to.isAfter(from)) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    return buildAnalytics(
      incidents: [..._incidents.value.values, ..._resolved.value],
      units: _units.value,
      from: from,
      to: to,
      runs: runs,
    );
  }

  static String _plain(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
  final _onSceneSince = <String, DateTime>{};

  /// The road route sent with the latest assignment of [incidentId], as the
  /// dispatch record keeps it on Supabase.
  RoadRoute? routeFor(String incidentId) => _routes[incidentId];
  final _smsCheckSentAt = <String, DateTime>{};

  /// When the simulated SOS arrives and when the third Dapitan St report
  /// completes a cluster.
  static const sosArrivesAfter = Duration(seconds: 20);
  static const clusterFormsAfter = Duration(seconds: 35);
  static const acceptAfter = Duration(seconds: 6);
  static const resolveAfterOnScene = Duration(seconds: 90);
  static const smsReplyAfter = Duration(seconds: 6);
  static const unitMetersPerSecond = 60.0;

  // ---------------------------------------------------------------- streams

  Stream<AppUser?> watchUser() => _user.watch();
  AppUser? get currentUser => _user.value;

  Stream<List<Incident>> watchActive() =>
      _incidents.watch().map((m) => m.values.toList(growable: false));

  /// What the resident was told (D4). Follows the database trigger: one
  /// notice per unit assigned, on scene, and closed, for an SOS from a
  /// known resident; only the first unit is texted. The mock pretends every
  /// text and push went out, except push for an SOS sent by SMS (no app).
  Stream<List<ResidentNotice>> watchNotices(String incidentId) {
    List<ResidentNotice> current() {
      final incident =
          _incidents.value[incidentId] ??
          _resolved.value.where((i) => i.id == incidentId).firstOrNull;
      if (incident == null ||
          incident.origin != IncidentOrigin.sos ||
          incident.residentId == null ||
          incident.falseReport) {
        return const [];
      }
      final push = incident.channel == ReportChannel.sms
          ? NoticeDelivery.noApp
          : NoticeDelivery.sent;
      final notices = <ResidentNotice>[];
      String? unit;
      for (final e in incident.events) {
        final kind = switch (e.kind) {
          IncidentEventKind.assigned => RescueConfirmationKind.assigned,
          IncidentEventKind.onScene => RescueConfirmationKind.onScene,
          IncidentEventKind.resolved => RescueConfirmationKind.resolved,
          _ => null,
        };
        if (kind == null) continue;
        if (kind == RescueConfirmationKind.assigned) unit = e.detail;
        final firstText =
            kind == RescueConfirmationKind.assigned &&
            !notices.any((n) => n.kind == RescueConfirmationKind.assigned);
        notices.add(
          ResidentNotice(
            id: '${incident.id}-${notices.length}',
            kind: kind,
            unitCallSign: unit,
            at: e.at,
            sms: firstText ? NoticeDelivery.sent : NoticeDelivery.none,
            push: push,
          ),
        );
      }
      return notices;
    }

    final out = StreamController<List<ResidentNotice>>();
    final subs = <StreamSubscription<Object?>>[];
    out
      ..onListen = () {
        subs
          ..add(_incidents.watch().listen((_) => out.add(current())))
          ..add(_resolved.watch().listen((_) => out.add(current())));
      }
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    return out.stream.distinct(listEquals);
  }

  Stream<List<Incident>> watchResolved(Duration since) =>
      _resolved.watch().map((all) {
        final cutoff = _clock().subtract(since);
        return [
          for (final i in all)
            if ((i.resolvedAt ?? i.receivedAt).isAfter(cutoff)) i,
        ];
      });

  /// Units in service (the board and suggestions).
  Stream<List<ResponseUnit>> watchUnits() => _units.watch().map(
    (m) => [
      for (final u in m.values)
        if (!u.retired) u,
    ],
  );

  /// Every unit, retired ones included (A2).
  Stream<List<ResponseUnit>> watchAllUnits() => _units.watch().map(
    (m) => [...m.values]..sort((a, b) => a.callSign.compareTo(b.callSign)),
  );

  Stream<List<StaffAccount>> watchResponders() => _accounts.watch().map(
    (m) => [
      for (final s in m.values)
        if (s.role == UserRole.responder) s,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName)),
  );

  // ------------------------------------------------------------------ A1

  Stream<List<StaffAccount>> watchStaff() => _accounts.watch().map(
    (m) =>
        [...m.values]..sort((a, b) => a.displayName.compareTo(b.displayName)),
  );

  Stream<List<Resident>> watchAllResidents() => _residents.watch().map(
    (m) => [...m.values]..sort((a, b) => a.fullName.compareTo(b.fullName)),
  );

  var _passwordCounter = 0;

  /// Sample temporary passwords (the database makes random ones).
  String _tempPassword() => 'Temp${1000 + ++_passwordCounter}pass';

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  int _activeAdminsExcept(String id) => _accounts.value.values
      .where((s) => s.role == UserRole.admin && s.active && s.id != id)
      .length;

  /// A1, checked like `admin_create_staff`.
  Future<({String id, String temporaryPassword})> createStaff({
    required String email,
    required String displayName,
    required UserRole role,
    String? unitId,
  }) async {
    final actor = await _authorizeAdmin();
    final mail = email.trim().toLowerCase();
    final name = displayName.trim();
    if (!_emailPattern.hasMatch(mail) ||
        name.isEmpty ||
        name.length > 80 ||
        role == UserRole.resident ||
        role == UserRole.system ||
        (unitId != null && role != UserRole.responder) ||
        (unitId != null && (_units.value[unitId]?.retired ?? true))) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    if (_accounts.value.values.any((s) => s.email.toLowerCase() == mail)) {
      throw const ActionRejected(ActionRejection.alreadyExists);
    }
    final id = 'usr-${_accounts.value.length + 100}';
    final pw = _tempPassword();
    _accounts.value = {
      ..._accounts.value,
      id: StaffAccount(
        id: id,
        displayName: name,
        email: mail,
        role: role,
        unitId: unitId,
      ),
    };
    _passwords[id] = pw;
    _log(actor, AuditAction.accountCreated, 'staff', id, '$name, ${role.name}');
    return (id: id, temporaryPassword: pw);
  }

  Future<void> updateStaff(
    String id, {
    required String displayName,
    required UserRole role,
  }) async {
    final actor = await _authorizeAdmin();
    final name = displayName.trim();
    if (name.isEmpty ||
        name.length > 80 ||
        role == UserRole.resident ||
        role == UserRole.system) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    final s = _accounts.value[id];
    if (s == null) throw const ActionRejected(ActionRejection.notFound);
    final changes = <String>[];
    if (s.role != role) {
      if (s.id == actor.id) {
        throw const ActionRejected(ActionRejection.ownAccount);
      }
      if (s.role == UserRole.admin &&
          s.active &&
          _activeAdminsExcept(id) == 0) {
        throw const ActionRejected(ActionRejection.lastAdmin);
      }
      changes.add('role ${s.role.name} → ${role.name}');
    }
    if (s.displayName != name) changes.add('name ${s.displayName} → $name');
    if (changes.isEmpty) return;
    _accounts.value = {
      ..._accounts.value,
      id: s.copyWith(
        displayName: name,
        role: role,
        clearUnit: role != UserRole.responder,
      ),
    };
    _log(actor, AuditAction.accountUpdated, 'staff', id, changes.join('; '));
  }

  Future<void> setStaffActive(String id, {required bool active}) async {
    final actor = await _authorizeAdmin();
    final s = _accounts.value[id];
    if (s == null) throw const ActionRejected(ActionRejection.notFound);
    if (s.id == actor.id) {
      throw const ActionRejected(ActionRejection.ownAccount);
    }
    if (s.active == active) return;
    if (!active && s.role == UserRole.admin && _activeAdminsExcept(id) == 0) {
      throw const ActionRejected(ActionRejection.lastAdmin);
    }
    _accounts.value = {
      ..._accounts.value,
      id: active
          ? s.copyWith(clearDeactivated: true)
          : s.copyWith(deactivatedAt: _clock()),
    };
    _log(
      actor,
      active ? AuditAction.accountReactivated : AuditAction.accountDeactivated,
      'staff',
      id,
      s.displayName,
    );
  }

  Future<String> resetPassword(String id) async {
    final actor = await _authorizeAdmin();
    final s = _accounts.value[id];
    if (s == null) throw const ActionRejected(ActionRejection.notFound);
    if (s.id == actor.id) {
      throw const ActionRejected(ActionRejection.ownAccount);
    }
    final pw = _tempPassword();
    _passwords[id] = pw;
    _log(actor, AuditAction.passwordReset, 'staff', id, s.displayName);
    return pw;
  }

  Future<void> setResidentSuspended(
    String residentId, {
    required bool suspended,
  }) async {
    final actor = await _authorizeAdmin();
    final r = _residents.value[residentId];
    if (r == null) throw const ActionRejected(ActionRejection.notFound);
    if (r.suspended == suspended) return;
    _residents.value = {
      ..._residents.value,
      residentId: suspended
          ? r.copyWith(suspendedAt: _clock())
          : r.copyWith(clearSuspended: true),
    };
    _log(
      actor,
      suspended ? AuditAction.residentSuspended : AuditAction.residentRestored,
      'manila_resident',
      residentId,
      null,
    );
  }

  Future<AppUser> _authorizeAdmin() async {
    final actor = await _authorize();
    if (!actor.isAdmin) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    return actor;
  }

  static final _callSignPattern = RegExp(r'^[A-Z0-9][A-Z0-9-]{0,11}$');

  /// A2, checked like `save_unit`.
  Future<String> saveUnit({
    String? id,
    required String callSign,
    required UnitType type,
    required String station,
    required int crewSize,
  }) async {
    final actor = await _authorizeAdmin();
    final cs = callSign.trim().toUpperCase();
    final st = station.trim();
    if (!_callSignPattern.hasMatch(cs) ||
        st.isEmpty ||
        st.length > 80 ||
        crewSize < 1 ||
        crewSize > 50) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    if (_units.value.values.any(
      (u) => u.callSign.toUpperCase() == cs && u.id != id,
    )) {
      throw const ActionRejected(ActionRejection.alreadyExists);
    }
    if (id == null) {
      final base =
          'unit-${cs.replaceAll(RegExp('[^A-Z0-9]'), '').toLowerCase()}';
      var newId = base;
      for (var n = 2; _units.value.containsKey(newId); n++) {
        newId = '$base-$n';
      }
      _units.value = {
        ..._units.value,
        newId: ResponseUnit(
          id: newId,
          callSign: cs,
          type: type,
          station: st,
          crewSize: crewSize,
          status: UnitStatus.available,
        ),
      };
      _log(
        actor,
        AuditAction.unitAdded,
        'response_unit',
        newId,
        '$cs, ${type.name}, $st, crew of $crewSize',
      );
      return newId;
    }
    final old = _units.value[id];
    if (old == null) throw const ActionRejected(ActionRejection.notFound);
    final changes = [
      if (old.callSign != cs) 'call sign ${old.callSign} → $cs',
      if (old.type != type) 'type ${old.type.name} → ${type.name}',
      if (old.station != st) 'station ${old.station} → $st',
      if (old.crewSize != crewSize) 'crew ${old.crewSize} → $crewSize',
    ];
    if (changes.isEmpty) return id;
    _units.value = {
      ..._units.value,
      id: old.copyWith(
        callSign: cs,
        type: type,
        station: st,
        crewSize: crewSize,
      ),
    };
    _log(
      actor,
      AuditAction.unitEdited,
      'response_unit',
      id,
      changes.join('; '),
    );
    return id;
  }

  /// A2: only a free unit; its responders come off it.
  Future<void> retireUnit(String id) async {
    final actor = await _authorizeAdmin();
    final unit = _units.value[id];
    if (unit == null) throw const ActionRejected(ActionRejection.notFound);
    if (unit.retired) return;
    if (unit.currentIncidentId != null || unit.status != UnitStatus.available) {
      throw const ActionRejected(ActionRejection.unitNotAvailable);
    }
    final crew = [
      for (final s in _accounts.value.values)
        if (s.unitId == id) s,
    ];
    _accounts.value = {
      ..._accounts.value,
      for (final s in crew) s.id: s.copyWith(clearUnit: true),
    };
    _units.value = {..._units.value, id: unit.copyWith(retiredAt: _clock())};
    final names = (crew.map((s) => s.displayName).toList()..sort()).join(', ');
    _log(
      actor,
      AuditAction.unitRetired,
      'response_unit',
      id,
      crew.isEmpty
          ? unit.callSign
          : '${unit.callSign}; responders taken off: $names',
    );
  }

  Future<void> restoreUnit(String id) async {
    final actor = await _authorizeAdmin();
    final unit = _units.value[id];
    if (unit == null) throw const ActionRejected(ActionRejection.notFound);
    if (!unit.retired) return;
    _units.value = {
      ..._units.value,
      id: unit.copyWith(
        clearRetired: true,
        status: UnitStatus.available,
        clearIncident: true,
      ),
    };
    _log(actor, AuditAction.unitRestored, 'response_unit', id, unit.callSign);
  }

  Future<void> setResponderUnit(String staffId, String? unitId) async {
    final actor = await _authorizeAdmin();
    final s = _accounts.value[staffId];
    if (s == null) throw const ActionRejected(ActionRejection.notFound);
    ResponseUnit? unit;
    if (unitId != null) {
      unit = _units.value[unitId];
      if (unit == null) throw const ActionRejected(ActionRejection.notFound);
      if (unit.retired) {
        throw const ActionRejected(ActionRejection.invalidValue);
      }
    }
    if (s.unitId == unitId) return;
    final from = _units.value[s.unitId]?.callSign ?? 'no unit';
    _accounts.value = {
      ..._accounts.value,
      staffId: unitId == null
          ? s.copyWith(clearUnit: true)
          : s.copyWith(unitId: unitId),
    };
    _log(
      actor,
      AuditAction.rosterChanged,
      'staff',
      staffId,
      '${s.displayName}: $from → ${unit?.callSign ?? 'no unit'}',
    );
  }

  Stream<List<CrowdReport>> watchReports(Duration window) =>
      _reports.watch().map((all) {
        final cutoff = _clock().subtract(window);
        return [
          for (final r in all)
            if (r.submittedAt.isAfter(cutoff)) r,
        ];
      });

  Stream<Resident?> watchResident(String id) =>
      _residents.watch().map((m) => m[id]);

  Stream<List<Resident>> watchVulnerable() => _residents.watch().map(
    (m) => [
      for (final r in m.values)
        if (r.isVulnerable) r,
    ],
  );

  Stream<List<AuditEntry>> watchAudit(int limit) => _audit.watch().map(
    (all) =>
        ([...all]..sort((a, b) {
              final byTime = b.at.compareTo(a.at);
              return byTime != 0 ? byTime : b.id.compareTo(a.id);
            }))
            .take(limit)
            .toList(growable: false),
  );

  Stream<WeatherStatus> watchWeather() => _weather.watch();

  Stream<ForecastRun?> watchForecast() => _forecast.watch();

  /// Scenario switcher: another run of the forecast model, or none yet.
  void setForecast(ForecastRun? run) => _forecast.value = run;

  Stream<LinkState> watchLink() => _link.watch();

  /// Scenario switcher: simulate losing and regaining the connection.
  void setLink(LinkState state) => _link.value = state;

  // -------------------------------------------------------------------- auth

  /// Passwords changed on D11 (the rest use [MockSeed.demoPassword]).
  final _passwords = <String, String>{};
  final _expired = StreamController<void>.broadcast();

  Stream<void> watchExpired() => _expired.stream;

  /// D11, checked like the Supabase version.
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    await _pause();
    if (_link.value == LinkState.offline) {
      throw const AuthException(AuthFailure.offline);
    }
    final user = _user.value;
    if (user == null) throw const AuthException(AuthFailure.notStaff);
    if (current != (_passwords[user.id] ?? MockSeed.demoPassword)) {
      throw const AuthException(AuthFailure.wrongCredentials);
    }
    if (next.length < StaffSessionRepository.minPasswordLength) {
      throw const ActionRejected(ActionRejection.invalidValue);
    }
    _passwords[user.id] = next;
  }

  /// Demo tool (G2): the session ends as if it could not be refreshed.
  void expireSession() {
    if (_user.value == null) return;
    _user.value = null;
    if (!_expired.isClosed) _expired.add(null);
  }

  Future<AppUser> signIn(String email, String password) async {
    await _pause();
    if (_link.value == LinkState.offline) {
      throw const AuthException(AuthFailure.offline);
    }
    final match = _accounts.value.values.where(
      (u) => u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (match.isEmpty ||
        password != (_passwords[match.first.id] ?? MockSeed.demoPassword)) {
      throw const AuthException(AuthFailure.wrongCredentials);
    }
    if (!match.first.active) {
      throw const AuthException(AuthFailure.accountDisabled);
    }
    return _user.value = match.first.asUser;
  }

  Future<void> signOut() async {
    await _pause();
    _user.value = null;
  }

  // ---------------------------------------------------------------- actions

  Future<void> verify(String id, VerificationMethod method) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _putIncident(
      incident
          .copyWith(
            verificationMethod: method,
            status: incident.status == IncidentStatus.pendingVerification
                ? IncidentStatus.confirmed
                : null,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.verified,
              at: now,
              actorName: actor.displayName,
              detail: method.name,
            ),
          ),
    );
    _log(actor, AuditAction.verified, 'incident_report', id, method.name);
  }

  Future<void> sendSmsCheck(String id) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _smsCheckSentAt[id] = now;
    _putIncident(
      incident.withEvent(
        IncidentEvent(
          kind: IncidentEventKind.smsCheckSent,
          at: now,
          actorName: actor.displayName,
        ),
      ),
    );
    _log(actor, AuditAction.smsCheckSent, 'incident_report', id, null);
  }

  Future<void> markFalseReport(String id, {String? reason}) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _releaseUnit(incident.assignedUnitId);
    _close(
      incident
          .copyWith(
            status: IncidentStatus.resolved,
            falseReport: true,
            resolvedAt: now,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.markedFalseReport,
              at: now,
              actorName: actor.displayName,
              detail: reason,
            ),
          ),
    );
    _log(actor, AuditAction.markedFalseReport, 'incident_report', id, reason);
  }

  Future<void> confirmType(String id, IncidentType type) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    _putIncident(
      incident
          .copyWith(confirmedType: type)
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.typeConfirmed,
              at: _clock(),
              actorName: actor.displayName,
              detail: type.name,
            ),
          ),
    );
    _log(actor, AuditAction.typeConfirmed, 'incident_report', id, type.name);
  }

  Future<void> assignUnit(
    String id,
    String unitId, {
    String? overrideReason,
    RoadRoute? route,
  }) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final unit = _units.value[unitId];
    if (unit == null || !unit.isDispatchable) {
      throw const ActionRejected(ActionRejection.unitNotAvailable);
    }
    final now = _clock();
    final previous = incident.assignedUnitId;
    _releaseUnit(previous);
    _units.value = {
      ..._units.value,
      unitId: unit.copyWith(currentIncidentId: id),
    };
    _assignedAt[id] = now;
    if (route != null) _routes[id] = route;
    _putIncident(
      incident
          .copyWith(
            status: IncidentStatus.assigned,
            assignedUnitId: unitId,
            suggestionOverridden: overrideReason != null,
            overrideReason: overrideReason,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.assigned,
              at: now,
              actorName: actor.displayName,
              detail: unit.callSign,
            ),
          ),
    );
    _log(
      actor,
      previous == null ? AuditAction.unitAssigned : AuditAction.unitReassigned,
      'dispatch',
      id,
      overrideReason == null
          ? unit.callSign
          : '${unit.callSign} (override: $overrideReason)',
    );
  }

  Future<void> resolve(String id) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    _resolveNow(incident, actor.displayName);
    _log(actor, AuditAction.resolved, 'incident_report', id, null);
  }

  Future<String> revealContact(String residentId) async {
    final actor = await _authorize();
    final resident = _residents.value[residentId];
    if (resident == null) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    _log(actor, AuditAction.contactViewed, 'manila_resident', residentId, null);
    return resident.contactNumber;
  }

  // ------------------------------------------------------------- simulation

  void startSimulation({Duration tick = const Duration(seconds: 1)}) {
    _timer ??= Timer.periodic(tick, (_) => runTick(tick));
  }

  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }

  /// Advances the simulation by [step]. Public so tests can drive it.
  @visibleForTesting
  void runTick(Duration step) {
    if (_link.value != LinkState.live) return;
    _elapsed += step;
    final now = _clock();

    if (!_sosDelivered && _elapsed >= sosArrivesAfter) {
      _sosDelivered = true;
      _putIncident(_seed.arrivingSos(now));
    }
    if (!_clusterReportAdded && _elapsed >= clusterFormsAfter) {
      _clusterReportAdded = true;
      _reports.value = [..._reports.value, _seed.dapitanThirdReport(now)];
      recluster();
    }

    for (final incident in _incidents.value.values.toList()) {
      final unit = _units.value[incident.assignedUnitId];
      switch (incident.status) {
        case IncidentStatus.assigned when unit != null:
          final since = _assignedAt.putIfAbsent(incident.id, () => now);
          if (now.difference(since) >= acceptAfter) {
            _setUnit(unit.copyWith(status: UnitStatus.enRoute));
            _putIncident(
              incident
                  .copyWith(status: IncidentStatus.enRoute)
                  .withEvent(
                    IncidentEvent(
                      kind: IncidentEventKind.enRoute,
                      at: now,
                      actorName: unit.callSign,
                    ),
                  ),
            );
          }
        case IncidentStatus.enRoute when unit != null:
          _moveToward(unit, incident, step, now);
        case IncidentStatus.onScene:
          final since = _onSceneSince.putIfAbsent(incident.id, () => now);
          if (now.difference(since) >= resolveAfterOnScene) {
            _resolveNow(incident, unit?.callSign);
          }
        default:
          break;
      }

      final smsAt = _smsCheckSentAt[incident.id];
      final current = _incidents.value[incident.id];
      if (smsAt != null &&
          current != null &&
          now.difference(smsAt) >= smsReplyAfter) {
        _smsCheckSentAt.remove(incident.id);
        _putIncident(
          current.withEvent(
            IncidentEvent(
              kind: IncidentEventKind.smsReplyReceived,
              at: now,
              detail: 'YES',
            ),
          ),
        );
      }
    }

    // The demo's rainfall drifts a little, until an admin simulates a
    // reading: from then on the weather is what they set.
    if (_elapsed.inSeconds % 30 == 0 && !_weatherSimulated) {
      final w = _weather.value;
      final drift = (_elapsed.inSeconds ~/ 30).isEven ? 1.5 : -1.0;
      _weather.value = WeatherStatus(
        signalLevel: w.signalLevel,
        rainfallMmPerHour: (w.rainfallMmPerHour + drift).clamp(5, 40),
        stormSurgeAdvisory: w.stormSurgeAdvisory,
        stormSurgeMeters: w.stormSurgeMeters,
        issuedAt: now,
        isSimulated: true,
      );
    }
  }

  /// Runs DBSCAN over the last 60 minutes of crowd reports and turns each
  /// cluster into a confirmed incident (the database trigger's job later).
  void recluster({Duration window = const Duration(minutes: 60)}) {
    final now = _clock();
    final recent = [
      for (final r in _reports.value)
        if (now.difference(r.submittedAt) <= window) r,
    ];
    final labels = dbscan(recent, locate: (r) => r.location);
    final clusters = <int, List<CrowdReport>>{};
    for (var i = 0; i < recent.length; i++) {
      if (labels[i] != kDbscanNoise) {
        (clusters[labels[i]] ??= []).add(recent[i]);
      }
    }

    var reports = {for (final r in _reports.value) r.id: r};
    for (final members in clusters.values) {
      final existingId = members
          .map((r) => r.incidentId)
          .firstWhere((id) => id != null, orElse: () => null);
      final ids = [for (final r in members) r.id];

      if (existingId != null && _incidents.value.containsKey(existingId)) {
        final incident = _incidents.value[existingId]!;
        _putIncident(
          incident.copyWith(
            crowdReportIds: {...incident.crowdReportIds, ...ids}.toList(),
          ),
        );
        for (final r in members) {
          reports[r.id] = r.copyWith(incidentId: existingId);
        }
      } else if (existingId == null) {
        final id = 'INC-${(_nextIncidentNumber++).toString().padLeft(4, '0')}';
        _putIncident(_clusterIncident(id, members, now));
        for (final r in members) {
          reports[r.id] = r.copyWith(incidentId: id);
        }
      }
    }
    _reports.value = reports.values.toList(growable: false);
  }

  Incident _clusterIncident(
    String id,
    List<CrowdReport> members,
    DateTime now,
  ) {
    final votes = <IncidentType, int>{};
    for (final r in members) {
      if (r.suggestedType != null) {
        votes[r.suggestedType!] = (votes[r.suggestedType!] ?? 0) + 1;
      }
    }
    final type = votes.isEmpty
        ? null
        : (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final lat =
        members.map((r) => r.location.lat).reduce((a, b) => a + b) /
        members.length;
    final lng =
        members.map((r) => r.location.lng).reduce((a, b) => a + b) /
        members.length;
    final earliest = members
        .map((r) => r.submittedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return Incident(
      id: id,
      origin: IncidentOrigin.crowdCluster,
      channel: members.first.channel,
      status: IncidentStatus.confirmed,
      suggestedType: type,
      location: GeoPoint(lat, lng),
      barangay: members.first.barangay,
      district: members.first.district,
      capturedAt: earliest,
      receivedAt: now,
      crowdReportIds: [for (final r in members) r.id],
      events: [IncidentEvent(kind: IncidentEventKind.received, at: now)],
    );
  }

  void _moveToward(
    ResponseUnit unit,
    Incident incident,
    Duration step,
    DateTime now,
  ) {
    final from = unit.location ?? incident.location;
    final remaining = from.distanceTo(incident.location);
    final travel = unitMetersPerSecond * step.inMilliseconds / 1000;
    if (remaining <= travel + 30) {
      _setUnit(
        unit.copyWith(
          status: UnitStatus.onScene,
          location: incident.location,
          lastLocationAt: now,
        ),
      );
      _onSceneSince[incident.id] = now;
      _putIncident(
        incident
            .copyWith(status: IncidentStatus.onScene)
            .withEvent(
              IncidentEvent(
                kind: IncidentEventKind.onScene,
                at: now,
                actorName: unit.callSign,
              ),
            ),
      );
    } else {
      _setUnit(
        unit.copyWith(
          location: from.lerpTo(incident.location, travel / remaining),
          lastLocationAt: now,
        ),
      );
    }
  }

  void dispose() {
    stopSimulation();
    unawaited(_expired.close());
    for (final live in <LiveValue<Object?>>[
      _feeds,
      _incidents,
      _resolved,
      _units,
      _reports,
      _residents,
      _audit,
      _weather,
      _alertLog,
      _user,
      _link,
      _settings,
      _accounts,
    ]) {
      live.close();
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _pause() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  /// Same checks the database will do with RLS: online, signed in, and
  /// allowed to dispatch.
  Future<AppUser> _authorize() async {
    await _pause();
    if (_link.value == LinkState.offline) {
      throw const ActionRejected(ActionRejection.offline);
    }
    final user = _user.value;
    if (user == null || !user.canDispatch) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    return user;
  }

  Incident _activeIncident(String id) {
    final incident = _incidents.value[id];
    if (incident == null) {
      throw const ActionRejected(ActionRejection.incidentClosed);
    }
    return incident;
  }

  void _putIncident(Incident incident) {
    _incidents.value = {..._incidents.value, incident.id: incident};
  }

  void _setUnit(ResponseUnit unit) {
    _units.value = {..._units.value, unit.id: unit};
  }

  void _releaseUnit(String? unitId) {
    final unit = _units.value[unitId];
    if (unit == null) return;
    _setUnit(unit.copyWith(status: UnitStatus.available, clearIncident: true));
  }

  void _resolveNow(Incident incident, String? actorName) {
    final now = _clock();
    _releaseUnit(incident.assignedUnitId);
    _close(
      incident
          .copyWith(status: IncidentStatus.resolved, resolvedAt: now)
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.resolved,
              at: now,
              actorName: actorName,
            ),
          ),
    );
  }

  void _close(Incident incident) {
    _incidents.value = {..._incidents.value}..remove(incident.id);
    _resolved.value = [..._resolved.value, incident];
    _assignedAt.remove(incident.id);
    _onSceneSince.remove(incident.id);
    _smsCheckSentAt.remove(incident.id);
  }

  void _log(
    AppUser actor,
    AuditAction action,
    String table,
    String targetId,
    String? detail,
  ) {
    _audit.value = [
      ..._audit.value,
      AuditEntry(
        id: 'log-${_nextAuditNumber++}',
        at: _clock(),
        actorId: actor.id,
        actorName: actor.displayName,
        actorRole: actor.role,
        action: action,
        targetTable: table,
        targetId: targetId,
        detail: detail,
      ),
    ];
  }
}
