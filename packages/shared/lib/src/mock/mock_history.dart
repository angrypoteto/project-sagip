part of 'mock_mobile_backend.dart';

/// Past records for the demo accounts (R6 My activity, F7 History), dated
/// back from when the backend was created. Only added with
/// `withHistory: true`, so tests start empty.
void _seedHistory(MockMobileBackend b) {
  final now = b._t0;
  DateTime daysAgo(int days, int hour, int minute) {
    final d = now.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  const maria = 'res-001';
  const home = GeoPoint(14.6091, 120.9925);

  // An SOS from a flood twelve days ago, rescued by R-03.
  final sosAt = daysAgo(12, 21, 14);
  var sos = SosRequest(
    clientId: 'hist-sos-1',
    capturedAt: sosAt,
    delivery: DeliveryState.delivered,
    location: home,
    accuracyMeters: 9,
    barangay: 'Barangay 412',
    district: 'Sampaloc',
    details: const SosDetails(type: IncidentType.flood, peopleCount: 3),
    sentVia: ReportChannel.app,
    sentAt: sosAt,
    deliveredAt: sosAt.add(const Duration(seconds: 2)),
    incidentId: 'INC-0118',
    unitCallSign: 'R-03',
    unitType: UnitType.rescueBoat,
    responderLocation: home,
  );
  for (final (status, minutes) in const [
    (IncidentStatus.pendingVerification, 0),
    (IncidentStatus.confirmed, 3),
    (IncidentStatus.assigned, 5),
    (IncidentStatus.enRoute, 6),
    (IncidentStatus.onScene, 19),
    (IncidentStatus.resolved, 48),
  ]) {
    sos = sos.withStatus(status, sosAt.add(Duration(minutes: minutes)));
  }
  b._owner[sos.clientId] = maria;
  b._sos.value = [sos];

  // Three reports: one that joined a confirmed incident, one whose
  // incident is resolved, and one no one else reported.
  HazardReport report(
    String id,
    DateTime at,
    String text,
    IncidentType type,
    GeoPoint point,
    String barangay,
    ReportStage stage, [
    String? incident,
  ]) {
    b._owner[id] = maria;
    return HazardReport(
      clientId: id,
      capturedAt: at,
      description: text,
      type: type,
      location: point,
      accuracyMeters: 12,
      barangay: barangay,
      district: 'Sampaloc',
      delivery: DeliveryState.delivered,
      deliveredAt: at.add(const Duration(seconds: 1)),
      serverId: 'rep-${id.substring(9)}',
      stage: stage,
      incidentId: incident,
    );
  }

  b._reports.value = [
    report(
      'hist-rep-311',
      daysAgo(3, 16, 5),
      'Knee-deep flood on Dapitan St near the market',
      IncidentType.flood,
      const GeoPoint(14.6112, 120.9901),
      'Barangay 412',
      ReportStage.confirmed,
      'INC-0141',
    ),
    report(
      'hist-rep-287',
      daysAgo(12, 20, 40),
      'Fallen electric post blocking Laong Laan Rd',
      IncidentType.structural,
      const GeoPoint(14.6120, 120.9935),
      'Barangay 412',
      ReportStage.resolved,
      'INC-0117',
    ),
    report(
      'hist-rep-240',
      daysAgo(20, 9, 30),
      'Smell of smoke near España Blvd',
      IncidentType.fire,
      const GeoPoint(14.6103, 120.9890),
      'Barangay 412',
      ReportStage.notConfirmed,
    ),
  ];

  b._responder.seedHistory([
    CompletedAssignment(
      incidentId: 'INC-0139',
      completedAt: daysAgo(2, 14, 20),
      type: IncidentType.flood,
      barangay: 'Barangay 105',
      district: 'Tondo',
      outcome: RescueOutcome.rescued,
      personsAssisted: 4,
      reportDelivery: DeliveryState.delivered,
    ),
    CompletedAssignment(
      incidentId: 'INC-0131',
      completedAt: daysAgo(4, 10, 5),
      type: IncidentType.medical,
      barangay: 'Barangay 490',
      district: 'Sampaloc',
      outcome: RescueOutcome.transported,
      personsAssisted: 1,
      reportDelivery: DeliveryState.delivered,
    ),
    CompletedAssignment(
      incidentId: 'INC-0124',
      completedAt: daysAgo(8, 18, 45),
      type: IncidentType.flood,
      barangay: 'Barangay 560',
      district: 'Sampaloc',
      outcome: RescueOutcome.rescued,
      personsAssisted: 2,
      reportDelivery: DeliveryState.delivered,
    ),
    CompletedAssignment(
      incidentId: 'INC-0118',
      completedAt: daysAgo(12, 22, 5),
      type: IncidentType.flood,
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      outcome: RescueOutcome.rescued,
      personsAssisted: 3,
      reportDelivery: DeliveryState.delivered,
    ),
    CompletedAssignment(
      incidentId: 'INC-0109',
      completedAt: daysAgo(16, 7, 50),
      type: IncidentType.structural,
      barangay: 'Barangay 287',
      district: 'Binondo',
      outcome: RescueOutcome.noOneFound,
      personsAssisted: 0,
      reportDelivery: DeliveryState.delivered,
    ),
  ]);
}
