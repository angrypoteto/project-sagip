import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/incident.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';

/// One reason an incident scored the points it did.
enum PriorityFactorKind { sos, cluster, vulnerable, waiting, mockLocation }

@immutable
class PriorityFactor {
  const PriorityFactor(this.kind, this.points);

  final PriorityFactorKind kind;
  final double points;
}

/// The score and the factors behind it, shown in the incident drawer so the
/// ranking is never a black box.
@immutable
class PriorityBreakdown {
  const PriorityBreakdown(this.factors, this.severity);

  final List<PriorityFactor> factors;
  final Severity severity;

  double get total => factors.fold(0, (sum, f) => sum + f.points);
}

/// Provisional Triage Queue ranking (plan 10.1, FR2).
///
/// The weights are placeholders until MDRRMD's triage SOP arrives
/// (Table 3.1 item 4, plan Q15 and Q20). An administrator changes them on
/// A3 Configuration (`app_setting`); the database scores the board with the
/// same rules (`private.priority_breakdown`), so keep the two in step.
@immutable
class PriorityRules {
  const PriorityRules({
    this.sosPoints = 50,
    this.clusterPoints = 40,
    this.vulnerablePoints = 30,
    this.pointsPerMinuteWaiting = 2,
    this.maxWaitingPoints = 30,
    this.mockLocationPenalty = -20,
    this.criticalAt = 80,
    this.highAt = 50,
  });

  /// A single person asking for rescue.
  final double sosPoints;

  /// A confirmed cluster of crowd reports.
  final double clusterPoints;

  /// Someone in the household is on the Vulnerable Resident Priority List.
  final double vulnerablePoints;

  /// Waiting time raises priority so no request waits forever.
  final double pointsPerMinuteWaiting;
  final double maxWaitingPoints;

  /// The phone reported a mock location. Still shown, ranked lower (FR8).
  final double mockLocationPenalty;

  final double criticalAt;
  final double highAt;

  /// The `app_setting` keys, in the order A3 shows them.
  static const settingKeys = [
    'priority.sos',
    'priority.cluster',
    'priority.vulnerable',
    'priority.waiting_per_minute',
    'priority.waiting_max',
    'priority.mock_location',
    'priority.critical_at',
    'priority.high_at',
  ];

  /// Rules from the A3 settings; a missing value keeps its default.
  factory PriorityRules.fromSettings(Iterable<AppSetting> settings) {
    final v = {for (final s in settings) s.key: s.value.toDouble()};
    const d = PriorityRules();
    return PriorityRules(
      sosPoints: v['priority.sos'] ?? d.sosPoints,
      clusterPoints: v['priority.cluster'] ?? d.clusterPoints,
      vulnerablePoints: v['priority.vulnerable'] ?? d.vulnerablePoints,
      pointsPerMinuteWaiting:
          v['priority.waiting_per_minute'] ?? d.pointsPerMinuteWaiting,
      maxWaitingPoints: v['priority.waiting_max'] ?? d.maxWaitingPoints,
      mockLocationPenalty: v['priority.mock_location'] ?? d.mockLocationPenalty,
      criticalAt: v['priority.critical_at'] ?? d.criticalAt,
      highAt: v['priority.high_at'] ?? d.highAt,
    );
  }

  /// These rules as setting values, keyed like [settingKeys].
  Map<String, double> toSettings() => {
    'priority.sos': sosPoints,
    'priority.cluster': clusterPoints,
    'priority.vulnerable': vulnerablePoints,
    'priority.waiting_per_minute': pointsPerMinuteWaiting,
    'priority.waiting_max': maxWaitingPoints,
    'priority.mock_location': mockLocationPenalty,
    'priority.critical_at': criticalAt,
    'priority.high_at': highAt,
  };

  PriorityBreakdown score(Incident incident, DateTime now) {
    final factors = <PriorityFactor>[
      if (incident.origin == IncidentOrigin.sos)
        PriorityFactor(PriorityFactorKind.sos, sosPoints)
      else
        PriorityFactor(PriorityFactorKind.cluster, clusterPoints),
      if (incident.vulnerable.isNotEmpty)
        PriorityFactor(PriorityFactorKind.vulnerable, vulnerablePoints),
    ];

    final waitingMinutes = now.difference(incident.capturedAt).inSeconds / 60;
    final waitingPoints = (waitingMinutes * pointsPerMinuteWaiting).clamp(
      0.0,
      maxWaitingPoints,
    );
    if (waitingPoints > 0) {
      factors.add(
        PriorityFactor(
          PriorityFactorKind.waiting,
          waitingPoints.roundToDouble(),
        ),
      );
    }

    if (incident.mockLocationSuspected) {
      factors.add(
        PriorityFactor(PriorityFactorKind.mockLocation, mockLocationPenalty),
      );
    }

    final total = factors.fold<double>(0, (sum, f) => sum + f.points);
    final severity = total >= criticalAt
        ? Severity.critical
        : (total >= highAt ? Severity.high : Severity.normal);
    return PriorityBreakdown(factors, severity);
  }

  /// Orders the Triage Queue: incidents still needing a dispatch decision
  /// first, then those already in progress, each by score (highest first).
  /// Ties go to whoever has waited longer.
  List<Incident> order(Iterable<Incident> incidents, DateTime now) {
    int group(Incident i) => i.status.needsDispatch ? 0 : 1;
    final scored = [
      for (final i in incidents) (incident: i, score: score(i, now).total),
    ];
    scored.sort((a, b) {
      final byGroup = group(a.incident).compareTo(group(b.incident));
      if (byGroup != 0) return byGroup;
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.incident.capturedAt.compareTo(b.incident.capturedAt);
    });
    return [for (final s in scored) s.incident];
  }
}

/// The priority settings as the `configuration` migration seeds them, with
/// the same ranges (the mock backend starts from these).
const defaultPrioritySettings = [
  AppSetting(
    key: 'priority.sos',
    category: 'priority',
    value: 50,
    min: 0,
    max: 200,
    description: 'Points for a single-person SOS',
  ),
  AppSetting(
    key: 'priority.cluster',
    category: 'priority',
    value: 40,
    min: 0,
    max: 200,
    description: 'Points for a confirmed cluster of crowd reports',
  ),
  AppSetting(
    key: 'priority.vulnerable',
    category: 'priority',
    value: 30,
    min: 0,
    max: 200,
    description: 'Points when the household has a vulnerable member',
  ),
  AppSetting(
    key: 'priority.waiting_per_minute',
    category: 'priority',
    value: 2,
    min: 0,
    max: 20,
    description: 'Points for each minute of waiting',
  ),
  AppSetting(
    key: 'priority.waiting_max',
    category: 'priority',
    value: 30,
    min: 0,
    max: 200,
    description: 'The most points waiting can add',
  ),
  AppSetting(
    key: 'priority.mock_location',
    category: 'priority',
    value: -20,
    min: -200,
    max: 0,
    description: 'Points for a suspected mock location (a penalty)',
  ),
  AppSetting(
    key: 'priority.critical_at',
    category: 'priority',
    value: 80,
    min: 0,
    max: 500,
    description: 'Score at which an incident is Critical',
  ),
  AppSetting(
    key: 'priority.high_at',
    category: 'priority',
    value: 50,
    min: 0,
    max: 500,
    description: 'Score at which an incident is High',
  ),
];

/// Why a setting value is refused (the same checks as `set_setting`), or
/// null when it is fine. [current] holds every setting by key.
ActionRejection? checkSetting(
  Map<String, AppSetting> current,
  String key,
  num value,
) {
  final s = current[key];
  if (s == null) return ActionRejection.notFound;
  if ((s.min != null && value < s.min!) || (s.max != null && value > s.max!)) {
    return ActionRejection.invalidValue;
  }
  final critical = current['priority.critical_at']?.value;
  final high = current['priority.high_at']?.value;
  if ((key == 'priority.high_at' && critical != null && value > critical) ||
      (key == 'priority.critical_at' && high != null && value < high)) {
    return ActionRejection.invalidValue;
  }
  return null;
}
