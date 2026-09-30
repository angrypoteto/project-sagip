import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Rows returned by the mobile database functions on the hosted project
/// (captured 2026-09-30 in a rolled-back transaction), parsed by the app's
/// models. If a function's output changes shape, this test fails.
void main() {
  Map<String, Object?> row(String json) =>
      (jsonDecode(json) as Map).cast<String, Object?>();

  test('my_sos() rows become SOS requests with status times and the unit', () {
    final sos = SosRequest.fromJson(
      row(
        '''{"status": "assigned", "details": {"note": "Water is waist-deep inside the house.", "type": "flood", "people_count": 3, "needs_extra_help": false}, "sent_at": "2026-09-30T10:58:25.996829+00:00", "barangay": "Barangay 412", "delivery": "delivered", "district": "Sampaloc", "latitude": 14.6091, "sent_via": "app", "client_id": "INC-0147", "longitude": 120.9925, "unit_type": "rescueBoat", "accuracy_m": 8, "captured_at": "2026-09-30T10:58:24.996829+00:00", "incident_id": "INC-0147", "delivered_at": "2026-09-30T10:58:25.996829+00:00", "status_times": {"assigned": "2026-09-30T11:02:36.996829+00:00", "pendingVerification": "2026-09-30T10:58:25.996829+00:00"}, "unit_call_sign": "R-03", "responder_latitude": 14.6045, "responder_longitude": 121.001, "responder_location_at": "2026-09-30T11:02:16.996829+00:00"}''',
      ),
    );
    expect(sos.status, IncidentStatus.assigned);
    expect(sos.delivery, DeliveryState.delivered);
    expect(sos.details.type, IncidentType.flood);
    expect(sos.details.peopleCount, 3);
    expect(sos.accuracyMeters, 8);
    expect(sos.sentVia, ReportChannel.app);
    expect(sos.unitCallSign, 'R-03');
    expect(sos.unitType, UnitType.rescueBoat);
    expect(sos.responderLocation, const GeoPoint(14.6045, 121.001));
    expect(sos.statusTimes.keys, {
      IncidentStatus.assigned,
      IncidentStatus.pendingVerification,
    });
    expect(sos.capturedAt.isBefore(sos.deliveredAt!), isTrue);
    expect(sos.capturedAt.isUtc, isFalse, reason: 'shown in local time');
  });

  test('my_crowd_reports() rows become reports with a stage', () {
    final report = HazardReport.fromJson(
      row(
        '''{"type": "flood", "stage": "resolved", "barangay": "Barangay 412", "delivery": "delivered", "district": "Sampaloc", "latitude": 14.6112, "client_id": "rep-190001", "longitude": 120.9901, "server_id": "rep-190001", "accuracy_m": null, "captured_at": "2026-09-27T10:32:36.996829+00:00", "description": "Knee-deep flood on Dapitan St near the market", "incident_id": "INC-0141", "delivered_at": "2026-09-27T10:32:36.996829+00:00"}''',
      ),
    );
    expect(report.stage, ReportStage.resolved);
    expect(report.incidentId, 'INC-0141');
    expect(report.type, IncidentType.flood);
    expect(report.accuracyMeters, isNull);
    expect(report.serverId, 'rep-190001');
  });

  test('resident_profile rows carry household member ids', () {
    final resident = Resident.fromJson(
      row(
        '''{"barangay": "Barangay 412", "district": "Sampaloc", "fullname": "Maria Dela Cruz", "household": [{"label": "Lolo Andres", "notes": "Uses a wheelchair", "member_id": 37, "vulnerability_types": ["seniorCitizen", "pwd"]}], "updated_at": "2026-09-30T11:02:36.996829+00:00", "contact_number": "0917 ••• 4821", "consent_given_at": "2026-08-21T11:02:36.996829+00:00", "manila_resident_id": "res-001"}''',
      ),
    );
    expect(resident.household.single.id, '37');
    expect(resident.maskedContact, '0917 ••• 4821');
    expect(resident.isVulnerable, isTrue);
  });

  test('my_alerts rows and forecast rows', () {
    final alert = PublicAlert.fromJson(
      row(
        '''{"body": "Rescue teams are responding to knee-deep flooding along Dapitan St.", "read": false, "level": "warning", "title": "Flooding on Dapitan St and España Blvd", "source": "mdrrmd", "alert_id": "alert-mdrrmd-1", "guidance": ["Do not walk or drive through floodwater."], "barangays": ["Barangay 412", "Barangay 490"], "issued_at": "2026-09-30T10:37:36.996829+00:00", "is_simulated": true}''',
      ),
    );
    expect(alert.source, AlertSource.mdrrmd);
    expect(alert.level, AlertLevel.warning);
    expect(alert.read, isFalse);
    expect(alert.barangays, hasLength(2));

    final forecast = BarangayForecast.fromRow(
      row(
        '''{"barangay": "Barangay 412", "district": "Sampaloc", "fire_risk": "low", "issued_at": "2026-09-29T22:00:00+00:00", "flood_risk": "high", "surge_risk": "low", "forecast_id": 12, "valid_until": "2026-10-02T22:00:00+00:00", "is_simulated": true, "model_version": "sample"}''',
      ),
    );
    expect(forecast.risks[ForecastHazard.flood], RiskLevel.high);
    expect(forecast.topHazard, ForecastHazard.flood);
    expect(forecast.validUntil.difference(forecast.issuedAt).inHours, 72);
    expect(forecast.isSimulated, isTrue);
  });

  test('my_assignments() and my_unit_history() rows', () {
    final a = Assignment.fromJson(
      row(
        '''{"type": "flood", "status": "assigned", "address": "1482 Dapitan St", "channel": "app", "barangay": "Barangay 412", "district": "Sampaloc", "latitude": 14.6091, "longitude": 120.9925, "offered_at": "2026-09-30T11:02:36.996829+00:00", "vulnerable": ["seniorCitizen", "pwd"], "accepted_at": null, "incident_id": "INC-0147", "on_scene_at": null, "people_count": 3, "people_found": null, "resident_note": "Water is waist-deep inside the house.", "real_emergency": null, "not_real_reason": null}''',
      ),
    );
    expect(a.status, IncidentStatus.assigned);
    expect(a.vulnerable, [
      VulnerabilityType.seniorCitizen,
      VulnerabilityType.pwd,
    ]);
    expect(a.residentNote, isNotNull);
    expect(a.mapSaved, 0);

    final done = CompletedAssignment.fromJson(
      row(
        '''{"type": "medical", "outcome": "transported", "barangay": "Barangay 490", "district": "Sampaloc", "incident_id": "INC-0131", "completed_at": "2026-09-26T09:42:36.996829+00:00", "report_delivery": "delivered", "persons_assisted": 1}''',
      ),
    );
    expect(done.outcome, RescueOutcome.transported);
    expect(done.reportDelivery, DeliveryState.delivered);
  });

  test('database refusal codes become the app exceptions', () {
    expect(
      databaseRefusal('outside_manila'),
      isA<ReportRejected>().having(
        (e) => e.reason,
        'reason',
        ReportRejection.outsideManila,
      ),
    );
    expect(
      databaseRefusal('rate_limited'),
      isA<ReportRejected>().having(
        (e) => e.reason,
        'reason',
        ReportRejection.rateLimited,
      ),
    );
    expect(
      databaseRefusal('finish_report_first'),
      isA<StatusRejected>().having(
        (e) => e.reason,
        'reason',
        StatusRejection.finishReportFirst,
      ),
    );
    expect(
      databaseRefusal('no_assignment'),
      isA<StatusRejected>().having(
        (e) => e.reason,
        'reason',
        StatusRejection.noAssignment,
      ),
    );
    expect(
      databaseRefusal('incident_closed'),
      isA<ActionRejected>().having(
        (e) => e.reason,
        'reason',
        ActionRejection.incidentClosed,
      ),
    );
    expect(
      databaseRefusal('something_new'),
      isA<ActionRejected>().having(
        (e) => e.reason,
        'reason',
        ActionRejection.notAllowed,
      ),
    );
  });
}
