import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/incident.dart';

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
/// These weights are placeholders until MDRRMD's triage SOP arrives
/// (Table 3.1 item 4, plan Q15 and Q20). They will move to the A3
/// Configuration screen so an administrator can change them.
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
