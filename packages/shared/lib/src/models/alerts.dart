import 'package:flutter/foundation.dart';

import 'enums.dart';

/// Who issued an alert (R7). PHIVOLCS advisories are relayed only; the
/// system does not forecast earthquakes or volcanoes (scope guardrail).
enum AlertSource { pagasa, phivolcs, efcos, mdrrmd }

/// How urgent an alert is. Drives the icon and tone, never color alone.
enum AlertLevel { info, warning, critical }

/// The PAGASA readings the threshold engine watches (FR5).
enum WeatherHazard { rainfall, signal, surge }

/// The ways an alert goes out (FR6). The apps always show it.
enum AlertChannel { app, push, sms, facebook }

/// What happened to an alert on one channel (`alert_delivery`).
enum AlertDeliveryStatus {
  /// Waiting for the sender.
  queued,

  /// Claimed by a run of the sender.
  sending,
  sent,
  failed,

  /// The channel was switched off on A3 when the alert was issued.
  off,

  /// A simulated alert: shown in the apps, never texted or posted.
  simulated,

  /// The channel has no provider yet (no Semaphore key, no Firebase
  /// project, no Facebook Page token).
  notSetUp,

  /// The alert expired before it was sent.
  ended,
}

/// A public alert shown to residents (R7, R8, FR14): weather warnings,
/// relayed advisories, and MDRRMD notices.
@immutable
class PublicAlert {
  const PublicAlert({
    required this.id,
    required this.source,
    required this.level,
    required this.title,
    required this.body,
    required this.issuedAt,
    this.guidance = const [],
    this.barangays = const [],
    this.read = false,
    this.isSimulated = false,
    this.hazard,
    this.expiresAt,
  });

  final String id;
  final AlertSource source;
  final AlertLevel level;

  /// Title and text come from the issuing agency, so they are content,
  /// not UI strings.
  final String title;
  final String body;
  final DateTime issuedAt;

  /// What to do, one step per entry (for example, wear a face mask during
  /// ashfall, FR14).
  final List<String> guidance;

  /// Affected barangays. Empty means all of Manila.
  final List<String> barangays;

  /// Whether this resident has opened it.
  final bool read;

  /// Raised by simulated data (the demo data or simulation mode).
  final bool isSimulated;

  /// Set on alerts the threshold engine issued: the reading that crossed
  /// its threshold (FR5).
  final WeatherHazard? hazard;

  /// When it stopped being current (conditions eased, or it was replaced);
  /// null while it is active.
  final DateTime? expiresAt;

  bool activeAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  PublicAlert copyWith({bool? read, DateTime? expiresAt}) => PublicAlert(
    id: id,
    source: source,
    level: level,
    title: title,
    body: body,
    issuedAt: issuedAt,
    guidance: guidance,
    barangays: barangays,
    read: read ?? this.read,
    isSimulated: isSimulated,
    hazard: hazard,
    expiresAt: expiresAt ?? this.expiresAt,
  );

  factory PublicAlert.fromJson(Map<String, Object?> json) => PublicAlert(
    id: '${json['alert_id']}',
    source: enumFromJson(AlertSource.values, json['source']),
    level: enumFromJson(AlertLevel.values, json['level']),
    title: json['title']! as String,
    body: json['body']! as String,
    issuedAt: timeFromJson(json['issued_at']),
    guidance: [
      for (final g in (json['guidance'] as List<Object?>? ?? const []))
        g! as String,
    ],
    barangays: [
      for (final b in (json['barangays'] as List<Object?>? ?? const []))
        b! as String,
    ],
    read: json['read'] as bool? ?? false,
    isSimulated: json['is_simulated'] as bool? ?? false,
    hazard: enumFromJsonOrNull(WeatherHazard.values, json['hazard']),
    expiresAt: timeFromJsonOrNull(json['expires_at']),
  );

  Map<String, Object?> toJson() => {
    'alert_id': id,
    'source': source.name,
    'level': level.name,
    'title': title,
    'body': body,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'guidance': guidance,
    'barangays': barangays,
    'read': read,
    'is_simulated': isSimulated,
    'hazard': hazard?.name,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };
}

/// What an advisory issued from the dashboard may hold (the same limits as
/// `issue_alert`).
abstract final class AdvisoryRules {
  static const maxTitle = 120;
  static const maxBody = 1000;
  static const maxSteps = 8;
  static const maxStep = 200;

  /// "What to do" as typed, one step per line: trimmed, blank lines
  /// dropped, the order kept.
  static List<String> steps(String text) => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  /// Whether the database would accept it.
  static bool accepts({
    required String title,
    required String body,
    required List<String> guidance,
  }) =>
      title.trim().isNotEmpty &&
      title.trim().length <= maxTitle &&
      body.trim().isNotEmpty &&
      body.trim().length <= maxBody &&
      guidance.length <= maxSteps &&
      guidance.every((g) => g.length <= maxStep);
}

/// One channel's outcome for an alert (D10 "log of alerts sent"). Counts
/// only: no numbers or names.
@immutable
class AlertDelivery {
  const AlertDelivery({
    required this.channel,
    required this.status,
    this.recipients,
    this.delivered,
    this.failed,
    this.detail,
  });

  final AlertChannel channel;
  final AlertDeliveryStatus status;
  final int? recipients;
  final int? delivered;
  final int? failed;
  final String? detail;

  factory AlertDelivery.fromJson(Map<String, Object?> json) => AlertDelivery(
    channel: enumFromJson(AlertChannel.values, json['channel']),
    status: enumFromJson(AlertDeliveryStatus.values, json['status']),
    recipients: (json['recipients'] as num?)?.toInt(),
    delivered: (json['delivered'] as num?)?.toInt(),
    failed: (json['failed'] as num?)?.toInt(),
    detail: json['detail'] as String?,
  );

  Map<String, Object?> toJson() => {
    'channel': channel.name,
    'status': status.name,
    'recipients': recipients,
    'delivered': delivered,
    'failed': failed,
    'detail': detail,
  };
}

/// An alert with what happened to it on each channel.
@immutable
class SentAlert {
  const SentAlert({required this.alert, required this.deliveries});

  final PublicAlert alert;

  /// In [AlertChannel] order.
  final List<AlertDelivery> deliveries;

  AlertDelivery? on(AlertChannel channel) {
    for (final d in deliveries) {
      if (d.channel == channel) return d;
    }
    return null;
  }

  /// A `public_alert` row with its `alert_delivery` rows embedded.
  factory SentAlert.fromJson(Map<String, Object?> json) => SentAlert(
    alert: PublicAlert.fromJson(json),
    deliveries: [
      for (final d in (json['alert_delivery'] as List<Object?>? ?? const []))
        AlertDelivery.fromJson((d! as Map).cast<String, Object?>()),
    ]..sort((a, b) => a.channel.index.compareTo(b.channel.index)),
  );
}

/// Hazards the 72-hour forecast covers (LSTM + KDE, plan 10.5).
enum ForecastHazard { flood, fire, stormSurge }

/// Whether a run labelled [modelVersion] forecasts [hazard]. `run-forecast`
/// names the hazards a model was not trained for in the run's label
/// (2026-11-02: the model trained on the recorded 2021 to 2026 data has no
/// storm surge record, so its runs say "storm surge not forecast"), so both
/// apps can say so instead of showing "Low".
bool forecastsHazard(String? modelVersion, ForecastHazard hazard) {
  final name = switch (hazard) {
    ForecastHazard.flood => 'flood',
    ForecastHazard.fire => 'fire',
    ForecastHazard.stormSurge => 'storm surge',
  };
  return !(modelVersion?.contains('$name not forecast') ?? false);
}

enum RiskLevel { low, moderate, high }

/// The 72-hour risk forecast for one barangay (R7 Forecast tab, FR4).
@immutable
class BarangayForecast {
  const BarangayForecast({
    required this.barangay,
    required this.district,
    required this.issuedAt,
    required this.validUntil,
    required this.risks,
    this.isSimulated = false,
    this.modelVersion,
  });

  final String barangay;
  final String district;
  final DateTime issuedAt;
  final DateTime validUntil;
  final Map<ForecastHazard, RiskLevel> risks;

  /// How far ahead the forecast looks: 72 hours in the thesis, 48 for the
  /// model trained on MDRRMD's records (2026-11-07). From the row's own
  /// times, so the screens follow whichever model made it.
  int get horizonHours => horizonHoursBetween(issuedAt, validUntil);

  /// True while the model runs on a simulated live feed (thesis scope).
  final bool isSimulated;

  /// Which model made it. [ForecastRun.sampleModel] marks made-up values
  /// that stand in until the LSTM and KDE models are trained.
  final String? modelVersion;

  RiskLevel riskOf(ForecastHazard hazard) => risks[hazard] ?? RiskLevel.low;

  /// Whether this run's model forecasts [hazard] (see [forecastsHazard]).
  bool covers(ForecastHazard hazard) => forecastsHazard(modelVersion, hazard);

  /// The hazard with the highest risk, for the preparation tips.
  ForecastHazard? get topHazard {
    ForecastHazard? top;
    for (final h in ForecastHazard.values) {
      final r = risks[h] ?? RiskLevel.low;
      if (r == RiskLevel.low) continue;
      if (top == null || r.index > risks[top]!.index) top = h;
    }
    return top;
  }

  factory BarangayForecast.fromJson(Map<String, Object?> json) =>
      BarangayForecast(
        barangay: json['barangay']! as String,
        district: json['district']! as String,
        issuedAt: timeFromJson(json['issued_at']),
        validUntil: timeFromJson(json['valid_until']),
        risks: {
          for (final e in (json['risks']! as Map<String, Object?>).entries)
            enumFromJson(ForecastHazard.values, e.key): enumFromJson(
              RiskLevel.values,
              e.value,
            ),
        },
        isSimulated: json['is_simulated'] as bool? ?? false,
        modelVersion: json['model_version'] as String?,
      );

  /// A row of the `barangay_forecast` table: one column per hazard.
  factory BarangayForecast.fromRow(Map<String, Object?> row) =>
      BarangayForecast(
        barangay: row['barangay']! as String,
        district: row['district']! as String,
        issuedAt: timeFromJson(row['issued_at']),
        validUntil: timeFromJson(row['valid_until']),
        risks: {
          ForecastHazard.flood: enumFromJson(
            RiskLevel.values,
            row['flood_risk'],
          ),
          ForecastHazard.fire: enumFromJson(RiskLevel.values, row['fire_risk']),
          ForecastHazard.stormSurge: enumFromJson(
            RiskLevel.values,
            row['surge_risk'],
          ),
        },
        isSimulated: row['is_simulated'] as bool? ?? false,
        modelVersion: row['model_version'] as String?,
      );

  Map<String, Object?> toJson() => {
    'barangay': barangay,
    'district': district,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'valid_until': validUntil.toUtc().toIso8601String(),
    'risks': {for (final e in risks.entries) e.key.name: e.value.name},
    'is_simulated': isSimulated,
    'model_version': modelVersion,
  };
}

/// Where incidents of one hazard have been densest (2026-10-29): the KDE's
/// mean density over a barangay's 100 m grid cells, relative to the
/// densest barangay's (1). A hotspot of past incidents, not a forecast;
/// the dashboard's Heatmap page shows it apart from the 72-hour forecast.
@immutable
class HazardDensity {
  const HazardDensity({
    required this.barangay,
    required this.district,
    required this.hazard,
    required this.relative,
    required this.modelVersion,
    required this.computedAt,
  });

  final String barangay;
  final String district;
  final ForecastHazard hazard;

  /// 0 to 1.
  final double relative;

  /// [ForecastRun.sampleModel] while the KDE runs on made-up records.
  final String modelVersion;
  final DateTime computedAt;

  bool get isSample => modelVersion == ForecastRun.sampleModel;

  /// A row of the `hazard_density` table.
  factory HazardDensity.fromRow(Map<String, Object?> row) => HazardDensity(
    barangay: row['barangay']! as String,
    district: row['district']! as String,
    hazard: enumFromJson(ForecastHazard.values, row['hazard']),
    relative: (row['relative']! as num).toDouble(),
    modelVersion: row['model_version']! as String,
    computedAt: timeFromJson(row['computed_at']),
  );
}

/// One hazard's result on the forecast model's test part (FR4): the
/// three-day windows it never trained on, how many had an incident, and how
/// the LSTM did. The confusion matrix follows from these: [caught] from
/// recall, the correct answers from accuracy.
@immutable
class HazardTest {
  const HazardTest({
    required this.windows,
    required this.positives,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.rmse,
    required this.majorityAccuracy,
  });

  factory HazardTest.fromJson(Map<String, Object?> json) {
    final lstm = (json['lstm']! as Map).cast<String, Object?>();
    double d(Object? v) => (v! as num).toDouble();
    return HazardTest(
      windows: (json['windows']! as num).toInt(),
      positives: (json['positives']! as num).toInt(),
      accuracy: d(lstm['accuracy']),
      precision: d(lstm['precision']),
      recall: d(lstm['recall']),
      f1: d(lstm['f1']),
      rmse: d(lstm['rmse']),
      majorityAccuracy: d(json['always_majority_accuracy']),
    );
  }

  final int windows;

  /// Windows with at least one incident.
  final int positives;
  final double accuracy;
  final double precision;
  final double recall;
  final double f1;

  /// Root mean squared error of the chance against what happened (0 or 1).
  final double rmse;

  /// The accuracy of always giving the commoner answer (never warn, or
  /// always warn): the baseline the model is compared with (plan Q23).
  final double majorityAccuracy;

  int get negatives => windows - positives;

  /// Windows with an incident that the model warned of.
  int get caught => (recall * positives).round();
  int get missed => positives - caught;

  /// Quiet windows the model correctly left quiet.
  int get quiet => ((accuracy * windows).round() - caught).clamp(0, negatives);
  int get falseAlarms => negatives - quiet;

  /// The mean of the share caught and the share correctly quiet: 50% is a
  /// coin toss, whatever the mix of windows.
  double get balancedAccuracy =>
      ((positives == 0 ? 0 : caught / positives) +
          (negatives == 0 ? 0 : quiet / negatives)) /
      2;

  /// True when the commoner answer is "no incident" (the baseline never
  /// warns); false when it is "an incident" (it always warns).
  bool get baselineNeverWarns => positives * 2 < windows;
}

/// The active forecast model's measured accuracy (`forecast_model_test()`,
/// dispatchers and admins; FR4).
@immutable
class ForecastModelTest {
  const ForecastModelTest({
    required this.version,
    required this.hazards,
    this.trainedFrom,
    this.trainedTo,
  });

  factory ForecastModelTest.fromJson(Map<String, Object?> json) {
    final trained = json['trained_on'] as List<Object?>?;
    return ForecastModelTest(
      version: json['version']! as String,
      trainedFrom: trained == null
          ? null
          : DateTime.parse(trained[0]! as String),
      trainedTo: trained == null ? null : DateTime.parse(trained[1]! as String),
      hazards: {
        for (final e in ((json['test'] as Map?) ?? const {}).entries)
          ?ForecastRun._hazardKey(e.key as String): HazardTest.fromJson(
            (e.value as Map).cast<String, Object?>(),
          ),
      },
    );
  }

  final String version;
  final DateTime? trainedFrom;
  final DateTime? trainedTo;
  final Map<ForecastHazard, HazardTest> hazards;
}

/// Whole hours from [issued] to [validUntil]; 72 (the thesis) when the times
/// say nothing sensible.
int horizonHoursBetween(DateTime issued, DateTime validUntil) {
  final hours = (validUntil.difference(issued).inMinutes / 60).round();
  return hours > 0 && hours <= 240 ? hours : 72;
}

/// One run of the forecast model: the forecasts issued together, one per
/// barangay (D8, FR4). The model runs once a day.
@immutable
class ForecastRun {
  const ForecastRun({
    required this.issuedAt,
    required this.validUntil,
    required this.forecasts,
    this.isSimulated = false,
    this.modelVersion,
    this.chances,
    this.rule,
  });

  /// The `model_version` of made-up values (the demo data).
  static const sampleModel = 'sample';

  /// A run older than this is overdue: the next one should have replaced
  /// it (plan D8: "a forecast older than 24 hours shows a stale warning").
  static const staleAfter = Duration(hours: 24);

  /// The newest run among [rows]: the forecasts that share the latest
  /// issue time. Null when there are none.
  static ForecastRun? latest(Iterable<BarangayForecast> rows) {
    DateTime? newest;
    for (final f in rows) {
      if (newest == null || f.issuedAt.isAfter(newest)) newest = f.issuedAt;
    }
    if (newest == null) return null;
    final run = [
      for (final f in rows)
        if (f.issuedAt.isAtSameMomentAs(newest)) f,
    ]..sort((a, b) => a.barangay.compareTo(b.barangay));
    return ForecastRun(
      issuedAt: newest,
      validUntil: run
          .map((f) => f.validUntil)
          .reduce((a, b) => a.isBefore(b) ? a : b),
      forecasts: run,
      isSimulated: run.any((f) => f.isSimulated),
      modelVersion: run.first.modelVersion,
    );
  }

  final DateTime issuedAt;
  final DateTime validUntil;
  final List<BarangayForecast> forecasts;

  /// How far ahead this run looks (see [BarangayForecast.horizonHours]).
  int get horizonHours => horizonHoursBetween(issuedAt, validUntil);

  /// True when any forecast in the run came from a simulated feed.
  final bool isSimulated;
  final String? modelVersion;

  /// The LSTM's chance (0 to 1) of at least one incident of each hazard in
  /// Manila in the next 72 hours (`forecast_run_detail`, 2026-11-02). Null
  /// when the run did not record it (sample runs, older runs).
  final Map<ForecastHazard, double>? chances;

  /// The rule that turned the chance and each barangay's density into its
  /// level. Null with [chances].
  final ForecastRule? rule;

  /// This run with its chances and rule (a `forecast_run_detail` row).
  ForecastRun withDetail(Map<String, Object?> row) => ForecastRun(
    issuedAt: issuedAt,
    validUntil: validUntil,
    forecasts: forecasts,
    isSimulated: isSimulated,
    modelVersion: modelVersion,
    chances: {
      for (final e in (row['probabilities']! as Map).entries)
        ?_hazardKey(e.key as String): (e.value as num).toDouble(),
    },
    rule: ForecastRule.fromJson((row['rule']! as Map).cast<String, Object?>()),
  );

  static ForecastHazard? _hazardKey(String key) => switch (key) {
    'flood' => ForecastHazard.flood,
    'fire' => ForecastHazard.fire,
    'storm_surge' || 'stormSurge' => ForecastHazard.stormSurge,
    _ => null,
  };

  /// Made-up values, not model output.
  bool get isSample => modelVersion == sampleModel;

  /// A run on this week's real weather (2026-11-02): `run-forecast` names
  /// it "live weather".
  bool get isLiveWeather => modelVersion?.contains('live weather') ?? false;

  /// Whether this run forecasts [hazard] (see [forecastsHazard]).
  bool covers(ForecastHazard hazard) => forecastsHazard(modelVersion, hazard);

  bool isStaleAt(DateTime now) => now.difference(issuedAt) > staleAfter;

  BarangayForecast? forBarangay(String barangay) {
    for (final f in forecasts) {
      if (f.barangay == barangay) return f;
    }
    return null;
  }

  /// The barangays for one hazard, highest risk first, then by name.
  List<BarangayForecast> ranked(ForecastHazard hazard) =>
      [...forecasts]..sort((a, b) {
        final byRisk = b.riskOf(hazard).index.compareTo(a.riskOf(hazard).index);
        return byRisk != 0 ? byRisk : a.barangay.compareTo(b.barangay);
      });

  /// How many barangays sit at [level] for [hazard].
  int count(ForecastHazard hazard, RiskLevel level) =>
      forecasts.where((f) => f.riskOf(hazard) == level).length;
}

/// One condition of the rule: the chance at least [chance] and the
/// barangay's relative density at least [density] (both 0 to 1).
typedef RiskCondition = ({double chance, double density});

/// How the 72-hour chance (LSTM) and a barangay's density of past
/// incidents (KDE) give its level (plan Q22, provisional): high when [high]
/// holds, moderate when any of [moderate] holds, otherwise low.
@immutable
class ForecastRule {
  const ForecastRule({required this.high, required this.moderate});

  final RiskCondition high;
  final List<RiskCondition> moderate;

  static RiskCondition _condition(Object? json) {
    final m = (json! as Map).cast<String, Object?>();
    return (
      chance: (m['probability']! as num).toDouble(),
      density: (m['density']! as num).toDouble(),
    );
  }

  factory ForecastRule.fromJson(Map<String, Object?> json) => ForecastRule(
    high: _condition(json['high']),
    moderate: [for (final c in json['moderate']! as List) _condition(c)],
  );

  static bool _holds(RiskCondition c, double chance, double density) =>
      chance >= c.chance && density >= c.density;

  RiskLevel levelOf(double chance, double density) =>
      _holds(high, chance, density)
      ? RiskLevel.high
      : moderate.any((c) => _holds(c, chance, density))
      ? RiskLevel.moderate
      : RiskLevel.low;

  /// The condition that gave [chance] and [density] their level: [high],
  /// the first moderate one that holds, or null for low.
  RiskCondition? matched(double chance, double density) {
    if (_holds(high, chance, density)) return high;
    for (final c in moderate) {
      if (_holds(c, chance, density)) return c;
    }
    return null;
  }

  /// The smallest chance any moderate or high condition needs.
  double get lowestChance => [
    high.chance,
    for (final c in moderate) c.chance,
  ].reduce((a, b) => a < b ? a : b);
}

/// What a resident is told about their own SOS as the rescue moves on
/// (FR6). The values are the incident statuses that raise one.
enum RescueConfirmationKind {
  /// A unit was assigned (or changed).
  assigned,

  /// The unit arrived.
  onScene,

  /// The SOS was closed.
  resolved;

  IncidentStatus get status => switch (this) {
    assigned => IncidentStatus.assigned,
    onScene => IncidentStatus.onScene,
    resolved => IncidentStatus.resolved,
  };
}

/// One rescue confirmation (`rescue_confirmation`), shown on the Alerts tab
/// (R7) above the public alerts.
@immutable
class RescueConfirmation {
  const RescueConfirmation({
    required this.id,
    required this.incidentId,
    required this.kind,
    required this.at,
    this.unitCallSign,
    this.read = false,
  });

  /// How long a confirmation stays on the Alerts tab.
  static const shownFor = Duration(days: 7);

  final String id;
  final String incidentId;
  final RescueConfirmationKind kind;

  /// The unit at that moment; null when the SOS was closed with no unit.
  final String? unitCallSign;
  final DateTime at;

  /// Whether the resident has opened it.
  final bool read;

  RescueConfirmation copyWith({bool? read}) => RescueConfirmation(
    id: id,
    incidentId: incidentId,
    kind: kind,
    at: at,
    unitCallSign: unitCallSign,
    read: read ?? this.read,
  );

  /// Reads a `rescue_confirmation` row, or the phone's saved copy.
  factory RescueConfirmation.fromJson(Map<String, Object?> json) =>
      RescueConfirmation(
        id: '${json['confirmation_id']}',
        incidentId: json['incident_id']! as String,
        kind: enumFromJson(RescueConfirmationKind.values, json['kind']),
        at: timeFromJson(json['created_at']),
        unitCallSign: json['unit_call_sign'] as String?,
        read: json['read_at'] != null,
      );

  Map<String, Object?> toJson() => {
    'confirmation_id': id,
    'incident_id': incidentId,
    'kind': kind.name,
    'created_at': at.toUtc().toIso8601String(),
    'unit_call_sign': unitCallSign,
    'read_at': read ? at.toUtc().toIso8601String() : null,
  };
}

/// What happened to one rescue confirmation on one channel, as the
/// dispatcher sees it on the incident drawer (D4).
enum NoticeDelivery {
  /// This step is not sent on this channel (only the first unit is texted).
  none,

  /// Queued or being sent.
  waiting,
  sent,
  failed,

  /// The channel was switched off on A3.
  off,

  /// Simulation mode: nothing went out.
  simulated,

  /// The channel has no provider yet (no Semaphore key, no Firebase key).
  notSetUp,

  /// Not sent within 30 minutes.
  expired,

  /// Push only: the resident's account has no phone registered.
  noDevice,

  /// Push only: the resident has no app account, so no push was queued.
  noApp;

  static NoticeDelivery fromStatus(String? status) => switch (status) {
    null => noApp,
    'queued' || 'sending' => waiting,
    _ => NoticeDelivery.values.byName(status),
  };
}

/// One thing the resident was told about their SOS (FR6), with how it went
/// out: the Alerts tab always, plus a text and a push (`incident_notices`).
@immutable
class ResidentNotice {
  const ResidentNotice({
    required this.id,
    required this.kind,
    required this.at,
    required this.sms,
    required this.push,
    this.unitCallSign,
    this.readAt,
  });

  final String id;
  final RescueConfirmationKind kind;
  final String? unitCallSign;
  final DateTime at;

  /// When the resident opened it in the app; null if not yet.
  final DateTime? readAt;
  final NoticeDelivery sms;
  final NoticeDelivery push;

  factory ResidentNotice.fromJson(Map<String, Object?> json) => ResidentNotice(
    id: '${json['confirmation_id']}',
    kind: enumFromJson(RescueConfirmationKind.values, json['kind']),
    unitCallSign: json['unit_call_sign'] as String?,
    at: timeFromJson(json['created_at']),
    readAt: timeFromJsonOrNull(json['read_at']),
    sms: NoticeDelivery.fromStatus(json['sms_status'] as String? ?? 'none'),
    push: NoticeDelivery.fromStatus(json['push_status'] as String?),
  );

  @override
  bool operator ==(Object other) =>
      other is ResidentNotice &&
      other.id == id &&
      other.kind == kind &&
      other.unitCallSign == unitCallSign &&
      other.at == at &&
      other.readAt == readAt &&
      other.sms == sms &&
      other.push == push;

  @override
  int get hashCode =>
      Object.hash(id, kind, unitCallSign, at, readAt, sms, push);
}

/// Everything the Alerts tab shows, plus when the phone last received it,
/// so the offline state can say "Last updated 2:15 PM".
@immutable
class AlertFeed {
  const AlertFeed({
    required this.alerts,
    required this.updatedAt,
    this.forecast,
    this.confirmations = const [],
  });

  /// Newest first.
  final List<PublicAlert> alerts;

  /// Confirmations about the resident's own SOS requests (FR6), newest
  /// first. Empty for responders.
  final List<RescueConfirmation> confirmations;

  /// Null when no forecast exists yet for the resident's barangay.
  final BarangayForecast? forecast;
  final DateTime updatedAt;

  int get unread =>
      alerts.where((a) => !a.read).length +
      confirmations.where((c) => !c.read).length;

  AlertFeed copyWith({
    List<PublicAlert>? alerts,
    List<RescueConfirmation>? confirmations,
  }) => AlertFeed(
    alerts: alerts ?? this.alerts,
    confirmations: confirmations ?? this.confirmations,
    forecast: forecast,
    updatedAt: updatedAt,
  );

  /// The phone keeps the last feed so the tab works offline.
  factory AlertFeed.fromJson(Map<String, Object?> json) => AlertFeed(
    alerts: [
      for (final a in (json['alerts'] as List<Object?>? ?? const []))
        PublicAlert.fromJson((a! as Map).cast<String, Object?>()),
    ],
    forecast: json['forecast'] == null
        ? null
        : BarangayForecast.fromJson(
            (json['forecast']! as Map).cast<String, Object?>(),
          ),
    confirmations: [
      for (final c in (json['confirmations'] as List<Object?>? ?? const []))
        RescueConfirmation.fromJson((c! as Map).cast<String, Object?>()),
    ],
    updatedAt: timeFromJson(json['updated_at']),
  );

  Map<String, Object?> toJson() => {
    'alerts': [for (final a in alerts) a.toJson()],
    'confirmations': [for (final c in confirmations) c.toJson()],
    'forecast': forecast?.toJson(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
