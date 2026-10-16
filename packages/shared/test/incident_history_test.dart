import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The incident history page's records, filters, and CSV (2026-10-16).
void main() {
  final t0 = DateTime.utc(2026, 10, 16, 1);
  Incident closed(
    String id, {
    IncidentType type = IncidentType.flood,
    String barangay = 'Barangay 856',
    String district = 'Pandacan',
    bool falseReport = false,
    bool cancelled = false,
    Duration? onSceneAfter,
  }) => Incident(
    id: id,
    origin: IncidentOrigin.sos,
    channel: ReportChannel.app,
    status: IncidentStatus.resolved,
    location: const GeoPoint(14.5865, 121.0026),
    barangay: barangay,
    district: district,
    address: '12 Sample Street',
    capturedAt: t0,
    receivedAt: t0,
    suggestedType: type,
    residentId: 'res-001',
    note: 'my grandmother is with me',
    assignedUnitId: 'unit-bfp-staana',
    falseReport: falseReport,
    cancelled: cancelled,
    resolvedAt: t0.add(const Duration(minutes: 40)),
    events: [
      IncidentEvent(kind: IncidentEventKind.received, at: t0),
      if (onSceneAfter != null)
        IncidentEvent(
          kind: IncidentEventKind.onScene,
          at: t0.add(onSceneAfter),
        ),
    ],
  );

  final rows = [
    ClosedIncident(
      incident: closed('INC-0170', onSceneAfter: const Duration(minutes: 12)),
    ).withReport(const {
      'outcome': 'rescued',
      'persons_assisted': 3,
      'houses_damaged': 1,
      'injured': 0,
      'missing': 0,
      'affected_families': 2,
    }),
    ClosedIncident(incident: closed('INC-0169', cancelled: true)),
    ClosedIncident(
      incident: closed(
        'INC-0168',
        type: IncidentType.fire,
        barangay: 'Barangay 105',
        district: 'Tondo',
        falseReport: true,
      ),
    ),
  ];

  test('how each one ended, and the time to reach the scene', () {
    expect(rows.map((r) => r.ending), [
      IncidentEnding.resolved,
      IncidentEnding.cancelled,
      IncidentEnding.falseReport,
    ]);
    expect(rows[0].responseTime, const Duration(minutes: 12));
    expect(rows[1].responseTime, isNull);
    expect(rows[0].outcome, RescueOutcome.rescued);
    expect(rows[0].personsAssisted, 3);
    expect(rows[1].hasReport, isFalse);
  });

  test('filters by type, how it ended, and a search', () {
    List<String> ids(List<ClosedIncident> l) => [
      for (final c in l) c.incident.id,
    ];
    expect(ids(filterHistory(rows, type: IncidentType.fire)), ['INC-0168']);
    expect(ids(filterHistory(rows, ending: IncidentEnding.cancelled)), [
      'INC-0169',
    ]);
    expect(ids(filterHistory(rows, query: 'tondo')), ['INC-0168']);
    expect(ids(filterHistory(rows, query: ' inc-017 ')), ['INC-0170']);
    expect(ids(filterHistory(rows)), hasLength(3));
  });

  test('the CSV has the facts and no personal data', () {
    final csv = historyCsv(rows, unitCallSign: (_) => 'BFP-STAANA');
    final lines = csv.trim().split('\n');
    expect(lines, hasLength(4));
    expect(lines.first, startsWith('incident_id,origin,type,'));
    expect(
      lines[1],
      startsWith(
        'INC-0170,sos,flood,false,Barangay 856,Pandacan,2026-10-16T01:00:00.000Z,'
        ',BFP-STAANA,2026-10-16T01:12:00.000Z,2026-10-16T01:40:00.000Z,12.0,'
        'resolved,rescued,3,1,0,0,2,false',
      ),
    );
    expect(lines[2], contains(',cancelled,'));
    expect(lines[3], contains(',falseReport,'));
    // Nothing that names or locates a person.
    for (final secret in [
      'Sample Street',
      'grandmother',
      'res-001',
      '14.5865',
      '121.0026',
    ]) {
      expect(csv, isNot(contains(secret)), reason: secret);
    }
    expect(
      historyCsvName(DateTime(2026, 10, 9), DateTime(2026, 10, 16)),
      'sagip-incident-history-2026-10-09-to-2026-10-16.csv',
    );
  });
}
