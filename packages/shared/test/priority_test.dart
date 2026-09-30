import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Incident incident({
  String id = 'INC-1',
  IncidentOrigin origin = IncidentOrigin.sos,
  IncidentStatus status = IncidentStatus.pendingVerification,
  Duration waiting = Duration.zero,
  List<VulnerabilityType> vulnerable = const [],
  bool mockLocation = false,
}) {
  final now = DateTime(2026, 10, 1, 15);
  return Incident(
    id: id,
    origin: origin,
    channel: ReportChannel.app,
    status: status,
    location: const GeoPoint(14.6, 121.0),
    barangay: 'Barangay 1',
    district: 'Tondo',
    capturedAt: now.subtract(waiting),
    receivedAt: now.subtract(waiting),
    vulnerable: vulnerable,
    mockLocationSuspected: mockLocation,
  );
}

void main() {
  final now = DateTime(2026, 10, 1, 15);
  const rules = PriorityRules();

  test('an SOS from a vulnerable household waiting 4 minutes is critical', () {
    final b = rules.score(
      incident(
        waiting: const Duration(minutes: 4),
        vulnerable: [VulnerabilityType.pwd],
      ),
      now,
    );
    expect(b.total, 50 + 30 + 8);
    expect(b.severity, Severity.critical);
    expect(
      b.factors.map((f) => f.kind),
      containsAll([
        PriorityFactorKind.sos,
        PriorityFactorKind.vulnerable,
        PriorityFactorKind.waiting,
      ]),
    );
  });

  test('waiting points are capped', () {
    final b = rules.score(incident(waiting: const Duration(hours: 2)), now);
    final waiting = b.factors.firstWhere(
      (f) => f.kind == PriorityFactorKind.waiting,
    );
    expect(waiting.points, rules.maxWaitingPoints);
  });

  test('a mock location lowers the score but keeps the SOS on the board', () {
    final b = rules.score(incident(mockLocation: true), now);
    expect(b.total, 50 - 20);
    expect(b.severity, Severity.normal);
  });

  test('queue order: needs dispatch first, then by score, then by waiting', () {
    final assignedVulnerable = incident(
      id: 'assigned',
      status: IncidentStatus.assigned,
      vulnerable: [VulnerabilityType.seniorCitizen],
    );
    final plainSos = incident(id: 'plain', waiting: const Duration(minutes: 1));
    final vulnerableSos = incident(
      id: 'vulnerable',
      vulnerable: [VulnerabilityType.pregnant],
    );
    final cluster = incident(
      id: 'cluster',
      origin: IncidentOrigin.crowdCluster,
      status: IncidentStatus.confirmed,
      waiting: const Duration(minutes: 2),
    );
    final ordered = rules.order([
      assignedVulnerable,
      plainSos,
      vulnerableSos,
      cluster,
    ], now);
    expect(ordered.map((i) => i.id), [
      'vulnerable', // 80
      'plain', // 52
      'cluster', // 44
      'assigned', // already has a unit
    ]);
  });
}
