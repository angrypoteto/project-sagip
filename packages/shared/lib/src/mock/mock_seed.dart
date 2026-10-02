import '../models/alerts.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';

/// Sample Manila data for Phase 1. All names and numbers are fictional.
/// Times are relative to [t0] so the queue always looks "live".
class MockSeed {
  MockSeed(this.t0);

  final DateTime t0;

  DateTime ago(int minutes, [int seconds = 0]) =>
      t0.subtract(Duration(minutes: minutes, seconds: seconds));

  static const demoPassword = 'sagip-demo';

  List<AppUser> get staff => const [
    AppUser(
      id: 'usr-disp-01',
      displayName: 'R. Santos',
      email: 'dispatcher@sagip.test',
      role: UserRole.dispatcher,
    ),
    AppUser(
      id: 'usr-admin-01',
      displayName: 'E. Navarro',
      email: 'admin@sagip.test',
      role: UserRole.admin,
    ),
  ];

  /// Responder accounts for the A2 roster (sample names).
  List<StaffAccount> get responders => const [
    StaffAccount(
      id: 'usr-resp-01',
      displayName: 'J. Reyes',
      email: 'j.reyes@sagip.test',
      role: UserRole.responder,
      unitId: 'unit-r03',
    ),
    StaffAccount(
      id: 'usr-resp-02',
      displayName: 'M. Lim',
      email: 'm.lim@sagip.test',
      role: UserRole.responder,
      unitId: 'unit-r05',
    ),
    StaffAccount(
      id: 'usr-resp-03',
      displayName: 'A. Bautista',
      email: 'a.bautista@sagip.test',
      role: UserRole.responder,
      unitId: 'unit-r07',
    ),
    StaffAccount(
      id: 'usr-resp-04',
      displayName: 'C. Garcia',
      email: 'c.garcia@sagip.test',
      role: UserRole.responder,
    ),
  ];

  List<Resident> get residents => [
    Resident(
      id: 'res-001',
      fullName: 'Maria Dela Cruz',
      contactNumber: '0917 000 4821',
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      household: const [
        VulnerableMember(
          label: 'Lolo Andres',
          types: [VulnerabilityType.seniorCitizen, VulnerabilityType.pwd],
          notes: 'Uses a wheelchair',
        ),
      ],
      consentGivenAt: ago(60 * 24 * 40),
      updatedAt: ago(60 * 24 * 12),
    ),
    const Resident(
      id: 'res-002',
      fullName: 'Jose Ramos',
      contactNumber: '0918 000 3310',
      barangay: 'Barangay 649',
      district: 'Port Area',
    ),
    Resident(
      id: 'res-003',
      fullName: 'Ana Santos',
      contactNumber: '0919 000 7712',
      barangay: 'Barangay 700',
      district: 'Malate',
      household: const [
        VulnerableMember(
          label: 'Ana (self)',
          types: [VulnerabilityType.seniorCitizen],
        ),
      ],
      consentGivenAt: ago(60 * 24 * 90),
      updatedAt: ago(60 * 24 * 90),
    ),
    Resident(
      id: 'res-004',
      fullName: 'Rosa Villanueva',
      contactNumber: '0920 000 1187',
      barangay: 'Barangay 128',
      district: 'Tondo',
      household: const [
        VulnerableMember(
          label: 'Rosa (self)',
          types: [VulnerabilityType.pregnant],
          notes: '8 months',
        ),
      ],
      consentGivenAt: ago(60 * 24 * 21),
      updatedAt: ago(60 * 24 * 21),
    ),
    Resident(
      id: 'res-005',
      fullName: 'Carlos Reyes',
      contactNumber: '0921 000 6604',
      barangay: 'Barangay 105',
      district: 'Tondo',
      household: const [
        VulnerableMember(
          label: 'Son',
          types: [VulnerabilityType.pwd],
          notes: 'Uses crutches',
        ),
      ],
      consentGivenAt: ago(60 * 24 * 55),
      updatedAt: ago(60 * 24 * 30),
    ),
    Resident(
      id: 'res-006',
      fullName: 'Liza Mercado',
      contactNumber: '0922 000 2290',
      barangay: 'Barangay 306',
      district: 'Quiapo',
      household: const [
        VulnerableMember(
          label: 'Parents',
          types: [VulnerabilityType.seniorCitizen],
          notes: 'Both over 75',
        ),
      ],
      consentGivenAt: ago(60 * 24 * 14),
      updatedAt: ago(60 * 24 * 14),
    ),
    Resident(
      id: 'res-007',
      fullName: 'Benjie Cruz',
      contactNumber: '0923 000 5518',
      barangay: 'Barangay 560',
      district: 'Sampaloc',
      household: const [
        VulnerableMember(label: 'Wife', types: [VulnerabilityType.pregnant]),
      ],
      consentGivenAt: ago(60 * 24 * 7),
      updatedAt: ago(60 * 24 * 7),
    ),
    Resident(
      id: 'res-008',
      fullName: 'Teresita Lim',
      contactNumber: '0924 000 9043',
      barangay: 'Barangay 287',
      district: 'Binondo',
      household: const [
        VulnerableMember(
          label: 'Teresita (self)',
          types: [VulnerabilityType.seniorCitizen, VulnerabilityType.pwd],
          notes: 'Hard of hearing',
        ),
      ],
      consentGivenAt: ago(60 * 24 * 120),
      updatedAt: ago(60 * 24 * 60),
    ),
  ];

  List<ResponseUnit> get units => [
    _unit(
      'unit-r03',
      'R-03',
      UnitType.rescueBoat,
      'Sampaloc',
      4,
      14.6045,
      121.0010,
    ),
    _unit(
      'unit-r07',
      'R-07',
      UnitType.rescueTeam,
      'Sampaloc',
      6,
      14.6060,
      121.0020,
    ),
    _unit(
      'unit-a05',
      'A-05',
      UnitType.ambulance,
      'Santa Cruz',
      3,
      14.6190,
      120.9840,
    ),
    _unit(
      'unit-a02',
      'A-02',
      UnitType.ambulance,
      'Binondo',
      3,
      14.5990,
      120.9790,
      incident: 'INC-0144',
    ),
    _unit(
      'unit-r05',
      'R-05',
      UnitType.rescueTeam,
      'Malate',
      5,
      14.5780,
      120.9880,
      status: UnitStatus.enRoute,
      incident: 'INC-0142',
    ),
    _unit(
      'unit-r11',
      'R-11',
      UnitType.rescueTeam,
      'Sampaloc',
      6,
      14.6110,
      121.0000,
      status: UnitStatus.onScene,
      incident: 'INC-0139',
    ),
    _unit(
      'unit-r02',
      'R-02',
      UnitType.rescueBoat,
      'Tondo',
      4,
      14.6150,
      120.9650,
    ),
    _unit(
      'unit-r04',
      'R-04',
      UnitType.rescueTeam,
      'Port Area',
      5,
      14.5900,
      120.9720,
    ),
    _unit(
      'unit-r09',
      'R-09',
      UnitType.rescueTeam,
      'Paco',
      5,
      14.5800,
      121.0000,
    ),
    _unit(
      'unit-a01',
      'A-01',
      UnitType.ambulance,
      'Ermita',
      3,
      14.5840,
      120.9830,
    ),
    _unit(
      'unit-a03',
      'A-03',
      UnitType.ambulance,
      'Malate',
      3,
      14.5700,
      120.9920,
    ),
    _unit(
      'unit-r12',
      'R-12',
      UnitType.rescueBoat,
      'Santa Ana',
      4,
      14.5820,
      121.0120,
    ),
  ];

  ResponseUnit _unit(
    String id,
    String callSign,
    UnitType type,
    String station,
    int crew,
    double lat,
    double lng, {
    UnitStatus status = UnitStatus.available,
    String? incident,
  }) => ResponseUnit(
    id: id,
    callSign: callSign,
    type: type,
    station: '$station station',
    crewSize: crew,
    status: status,
    location: GeoPoint(lat, lng),
    lastLocationAt: ago(0, 20),
    currentIncidentId: incident,
  );

  List<CrowdReport> get crowdReports => [
    // Confirmed flood cluster, Barangay 105, Tondo (INC-0146).
    _report(
      'rep-201',
      'Baha na hanggang baywang sa Juan Luna St.',
      14.61970,
      120.96700,
      'Barangay 105',
      'Tondo',
      9,
      IncidentType.flood,
      0.93,
      incident: 'INC-0146',
    ),
    _report(
      'rep-202',
      'Flooded street, water entering houses',
      14.61985,
      120.96715,
      'Barangay 105',
      'Tondo',
      8,
      IncidentType.flood,
      0.90,
      incident: 'INC-0146',
    ),
    _report(
      'rep-203',
      'Hindi na makalabas, tumataas ang tubig',
      14.61958,
      120.96722,
      'Barangay 105',
      'Tondo',
      7,
      IncidentType.flood,
      0.81,
      incident: 'INC-0146',
      channel: ReportChannel.webForm,
    ),
    _report(
      'rep-204',
      'Mga bata stranded sa second floor',
      14.61975,
      120.96688,
      'Barangay 105',
      'Tondo',
      6,
      IncidentType.flood,
      0.74,
      incident: 'INC-0146',
    ),
    // Confirmed structural cluster, Barangay 560, Sampaloc (INC-0139).
    _report(
      'rep-190',
      'Wall collapsed onto the alley',
      14.61100,
      121.00000,
      'Barangay 560',
      'Sampaloc',
      21,
      IncidentType.structural,
      0.88,
      incident: 'INC-0139',
    ),
    _report(
      'rep-191',
      'Gumuho ang pader, may naipit',
      14.61118,
      121.00012,
      'Barangay 560',
      'Sampaloc',
      20,
      IncidentType.structural,
      0.79,
      incident: 'INC-0139',
    ),
    _report(
      'rep-192',
      'Debris blocking the road near the school',
      14.61090,
      121.00025,
      'Barangay 560',
      'Sampaloc',
      19,
      IncidentType.structural,
      0.71,
      incident: 'INC-0139',
    ),
    // Unverified singles.
    _report(
      'rep-210',
      'Baha na hanggang tuhod sa Dapitan St.',
      14.61180,
      120.98930,
      'Barangay 412',
      'Sampaloc',
      3,
      IncidentType.flood,
      0.91,
    ),
    _report(
      'rep-211',
      "Water rising fast near the church, we can't get the car out",
      14.61195,
      120.98950,
      'Barangay 412',
      'Sampaloc',
      1,
      IncidentType.flood,
      0.88,
      channel: ReportChannel.webForm,
    ),
    _report(
      'rep-205',
      'Smoke from a building on Recto Ave',
      14.59900,
      120.98400,
      'Barangay 306',
      'Quiapo',
      12,
      IncidentType.fire,
      0.84,
    ),
    _report(
      'rep-206',
      'Fallen tree blocking the road, no one hurt',
      14.57900,
      121.00100,
      'Barangay 670',
      'Paco',
      30,
      IncidentType.structural,
      0.72,
    ),
    _report(
      'rep-207',
      'Tubig sa loob ng bahay, hanggang binti',
      14.62550,
      120.97150,
      'Barangay 128',
      'Tondo',
      37,
      IncidentType.flood,
      0.86,
    ),
  ];

  /// The report the simulation adds to complete the Dapitan St cluster.
  CrowdReport dapitanThirdReport(DateTime now) => CrowdReport(
    id: 'rep-212',
    description: 'Lubog na yung kalsada, may mga bata dito',
    location: const GeoPoint(14.61170, 120.98955),
    barangay: 'Barangay 412',
    district: 'Sampaloc',
    channel: ReportChannel.app,
    submittedAt: now,
    suggestedType: IncidentType.flood,
    suggestionConfidence: 0.79,
  );

  CrowdReport _report(
    String id,
    String text,
    double lat,
    double lng,
    String barangay,
    String district,
    int minutesAgo,
    IncidentType type,
    double confidence, {
    String? incident,
    ReportChannel channel = ReportChannel.app,
  }) => CrowdReport(
    id: id,
    description: text,
    location: GeoPoint(lat, lng),
    barangay: barangay,
    district: district,
    channel: channel,
    submittedAt: ago(minutesAgo),
    suggestedType: type,
    suggestionConfidence: confidence,
    incidentId: incident,
  );

  List<Incident> get incidents => [
    Incident(
      id: 'INC-0147',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.app,
      status: IncidentStatus.pendingVerification,
      suggestedType: IncidentType.flood,
      location: const GeoPoint(14.6091, 120.9925),
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      address: '1482 Dapitan St',
      accuracyMeters: 8,
      capturedAt: ago(4, 12),
      receivedAt: ago(4, 11),
      residentId: 'res-001',
      peopleCount: 3,
      note: 'Water is waist-deep inside the house.',
      vulnerable: const [
        VulnerabilityType.seniorCitizen,
        VulnerabilityType.pwd,
      ],
      accountVerified: true,
      events: [IncidentEvent(kind: IncidentEventKind.received, at: ago(4, 11))],
    ),
    Incident(
      id: 'INC-0149',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.sms,
      status: IncidentStatus.pendingVerification,
      location: const GeoPoint(14.5869, 120.9690),
      barangay: 'Barangay 649',
      district: 'Port Area',
      accuracyMeters: 15,
      capturedAt: ago(1, 5),
      receivedAt: ago(1, 1),
      residentId: 'res-002',
      accountVerified: true,
      events: [IncidentEvent(kind: IncidentEventKind.received, at: ago(1, 1))],
    ),
    Incident(
      id: 'INC-0146',
      origin: IncidentOrigin.crowdCluster,
      channel: ReportChannel.app,
      status: IncidentStatus.confirmed,
      suggestedType: IncidentType.flood,
      location: const GeoPoint(14.61972, 120.96706),
      barangay: 'Barangay 105',
      district: 'Tondo',
      address: 'Juan Luna St',
      capturedAt: ago(9),
      receivedAt: ago(6, 40),
      crowdReportIds: const ['rep-201', 'rep-202', 'rep-203', 'rep-204'],
      events: [IncidentEvent(kind: IncidentEventKind.received, at: ago(6, 40))],
    ),
    Incident(
      id: 'INC-0144',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.app,
      status: IncidentStatus.assigned,
      suggestedType: IncidentType.fire,
      confirmedType: IncidentType.fire,
      location: const GeoPoint(14.6003, 120.9745),
      barangay: 'Barangay 287',
      district: 'Binondo',
      address: 'Ongpin St',
      accuracyMeters: 11,
      capturedAt: ago(9, 12),
      receivedAt: ago(9, 11),
      residentId: 'res-008',
      peopleCount: 2,
      vulnerable: const [
        VulnerabilityType.seniorCitizen,
        VulnerabilityType.pwd,
      ],
      accountVerified: true,
      verificationMethod: VerificationMethod.callback,
      assignedUnitId: 'unit-a02',
      events: [
        IncidentEvent(kind: IncidentEventKind.received, at: ago(9, 11)),
        IncidentEvent(
          kind: IncidentEventKind.verified,
          at: ago(7),
          actorName: 'R. Santos',
          detail: 'Callback',
        ),
        IncidentEvent(
          kind: IncidentEventKind.assigned,
          at: ago(0, 10),
          actorName: 'R. Santos',
          detail: 'A-02',
        ),
      ],
    ),
    Incident(
      id: 'INC-0142',
      origin: IncidentOrigin.sos,
      channel: ReportChannel.sms,
      status: IncidentStatus.enRoute,
      suggestedType: IncidentType.medical,
      confirmedType: IncidentType.medical,
      location: const GeoPoint(14.5712, 120.9888),
      barangay: 'Barangay 700',
      district: 'Malate',
      address: 'Remedios St',
      capturedAt: ago(12, 30),
      receivedAt: ago(12, 26),
      residentId: 'res-003',
      peopleCount: 1,
      vulnerable: const [VulnerabilityType.seniorCitizen],
      accountVerified: true,
      verificationMethod: VerificationMethod.callback,
      assignedUnitId: 'unit-r05',
      events: [
        IncidentEvent(kind: IncidentEventKind.received, at: ago(12, 26)),
        IncidentEvent(
          kind: IncidentEventKind.verified,
          at: ago(10),
          actorName: 'R. Santos',
          detail: 'Callback',
        ),
        IncidentEvent(
          kind: IncidentEventKind.assigned,
          at: ago(8),
          actorName: 'R. Santos',
          detail: 'R-05',
        ),
        IncidentEvent(
          kind: IncidentEventKind.enRoute,
          at: ago(7),
          actorName: 'R-05',
        ),
      ],
    ),
    Incident(
      id: 'INC-0139',
      origin: IncidentOrigin.crowdCluster,
      channel: ReportChannel.app,
      status: IncidentStatus.onScene,
      suggestedType: IncidentType.structural,
      confirmedType: IncidentType.structural,
      location: const GeoPoint(14.61103, 121.00012),
      barangay: 'Barangay 560',
      district: 'Sampaloc',
      capturedAt: ago(21),
      receivedAt: ago(18, 2),
      crowdReportIds: const ['rep-190', 'rep-191', 'rep-192'],
      assignedUnitId: 'unit-r11',
      events: [
        IncidentEvent(kind: IncidentEventKind.received, at: ago(18, 2)),
        IncidentEvent(
          kind: IncidentEventKind.assigned,
          at: ago(16),
          actorName: 'R. Santos',
          detail: 'R-11',
        ),
        IncidentEvent(
          kind: IncidentEventKind.onScene,
          at: ago(4),
          actorName: 'R-11',
        ),
      ],
    ),
  ];

  /// The SOS the simulation delivers after about 20 seconds. The phone
  /// reported a mock location, so it arrives flagged (FR8).
  Incident arrivingSos(DateTime now) => Incident(
    id: 'INC-0150',
    origin: IncidentOrigin.sos,
    channel: ReportChannel.app,
    status: IncidentStatus.pendingVerification,
    location: const GeoPoint(14.6258, 120.9718),
    barangay: 'Barangay 128',
    district: 'Tondo',
    accuracyMeters: 5,
    capturedAt: now.subtract(const Duration(seconds: 3)),
    receivedAt: now,
    residentId: 'res-004',
    vulnerable: const [VulnerabilityType.pregnant],
    accountVerified: true,
    mockLocationSuspected: true,
    events: [IncidentEvent(kind: IncidentEventKind.received, at: now)],
  );

  WeatherStatus get weather => WeatherStatus(
    signalLevel: 2,
    rainfallMmPerHour: 18,
    stormSurgeAdvisory: 'Storm surge up to 1 m possible along Manila Bay',
    issuedAt: ago(2),
    isSimulated: true,
  );

  /// The four sample alerts of the demo data with their deliveries: shown
  /// in the apps, never sent outside them (simulated).
  List<SentAlert> get sentAlerts {
    SentAlert sample(
      String id,
      AlertSource source,
      AlertLevel level,
      String title,
      String body,
      int minutesAgo, [
      List<String> barangays = const [],
    ]) => SentAlert(
      alert: PublicAlert(
        id: id,
        source: source,
        level: level,
        title: title,
        body: body,
        issuedAt: ago(minutesAgo),
        barangays: barangays,
        isSimulated: true,
      ),
      deliveries: [
        for (final c in AlertChannel.values)
          AlertDelivery(
            channel: c,
            status: c == AlertChannel.app
                ? AlertDeliveryStatus.sent
                : AlertDeliveryStatus.simulated,
          ),
      ],
    );

    return [
      sample(
        'alert-mdrrmd-1',
        AlertSource.mdrrmd,
        AlertLevel.warning,
        'Flooding on Dapitan St and España Blvd',
        'Rescue teams are responding to knee-deep flooding along Dapitan '
            'St. Avoid the area if you can.',
        25,
        const ['Barangay 412', 'Barangay 490'],
      ),
      sample(
        'alert-pagasa-rain',
        AlertSource.pagasa,
        AlertLevel.warning,
        'Orange rainfall warning for Metro Manila',
        'Heavy rain of 15 to 30 mm per hour is falling and may continue '
            'for the next 3 hours.',
        50,
      ),
      sample(
        'alert-pagasa-tc',
        AlertSource.pagasa,
        AlertLevel.warning,
        'Wind Signal No. 2 raised over Metro Manila',
        'A severe tropical storm may bring gale-force winds of 62 to 88 km '
            'per hour within 24 hours.',
        180,
      ),
      sample(
        'alert-phivolcs-1',
        AlertSource.phivolcs,
        AlertLevel.info,
        'Taal Volcano advisory: possible light ashfall',
        'PHIVOLCS reports steam and gas emission from Taal Volcano.',
        26 * 60,
      ),
    ];
  }

  List<AuditEntry> get audit => [
    AuditEntry(
      id: 'log-1001',
      at: ago(16),
      actorId: 'usr-disp-01',
      actorName: 'R. Santos',
      actorRole: UserRole.dispatcher,
      action: AuditAction.unitAssigned,
      targetTable: 'dispatch',
      targetId: 'INC-0139',
      detail: 'R-11',
    ),
    AuditEntry(
      id: 'log-1002',
      at: ago(10),
      actorId: 'usr-disp-01',
      actorName: 'R. Santos',
      actorRole: UserRole.dispatcher,
      action: AuditAction.verified,
      targetTable: 'incident_report',
      targetId: 'INC-0142',
      detail: 'Callback',
    ),
    AuditEntry(
      id: 'log-1003',
      at: ago(8),
      actorId: 'usr-disp-01',
      actorName: 'R. Santos',
      actorRole: UserRole.dispatcher,
      action: AuditAction.unitAssigned,
      targetTable: 'dispatch',
      targetId: 'INC-0142',
      detail: 'R-05',
    ),
    AuditEntry(
      id: 'log-1004',
      at: ago(7),
      actorId: 'usr-disp-01',
      actorName: 'R. Santos',
      actorRole: UserRole.dispatcher,
      action: AuditAction.verified,
      targetTable: 'incident_report',
      targetId: 'INC-0144',
      detail: 'Callback',
    ),
    AuditEntry(
      id: 'log-1005',
      at: ago(0, 10),
      actorId: 'usr-disp-01',
      actorName: 'R. Santos',
      actorRole: UserRole.dispatcher,
      action: AuditAction.unitAssigned,
      targetTable: 'dispatch',
      targetId: 'INC-0144',
      detail: 'A-02',
    ),
  ];
}
