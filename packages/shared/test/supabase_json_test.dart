import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

// Rows in the shape the Supabase views return (supabase/migrations).
void main() {
  test('feed_status rows parse (shape from the hosted project)', () {
    final ok = FeedStatus.fromJson({
      'source': 'pagasa_cyclone',
      'checked_at': '2026-10-03T03:27:12.641508+00:00',
      'ok': true,
      'last_success_at': '2026-10-03T03:27:12.641508+00:00',
      'last_error': null,
      'failures': 0,
      'seen': {'state': 'none'},
    });
    expect(ok.source, FeedSource.pagasaCyclone);
    expect(ok.ok, isTrue);
    expect(ok.seen['state'], 'none');
    final down = FeedStatus.fromJson({
      'source': 'pagasa_rainfall',
      'checked_at': '2026-10-03T03:37:00+00:00',
      'ok': false,
      'last_success_at': null,
      'last_error': 'HTTP 503',
      'failures': 2,
      'seen': <String, Object?>{},
    });
    expect(down.lastSuccessAt, isNull);
    expect(down.failures, 2);
    expect(
      () => FeedStatus.fromJson({
        ...{'source': 'efcos'},
        'ok': true,
        'checked_at': '2026-10-03T03:37:00Z',
      }),
      throwsFormatException,
    );
  });

  test('incident_notices rows parse: statuses, no app, and read time', () {
    final sent = ResidentNotice.fromJson({
      'confirmation_id': 41,
      'kind': 'assigned',
      'unit_call_sign': 'R-03',
      'created_at': '2026-10-03T06:00:00Z',
      'read_at': '2026-10-03T06:01:00Z',
      'sms_status': 'sending',
      'push_status': 'noDevice',
    });
    expect(sent.id, '41');
    expect(sent.kind, RescueConfirmationKind.assigned);
    expect(sent.sms, NoticeDelivery.waiting);
    expect(sent.push, NoticeDelivery.noDevice);
    expect(sent.readAt, DateTime.utc(2026, 10, 3, 6, 1).toLocal());
    final closed = ResidentNotice.fromJson({
      'confirmation_id': 42,
      'kind': 'resolved',
      'unit_call_sign': null,
      'created_at': '2026-10-03T07:00:00Z',
      'read_at': null,
      'sms_status': 'none',
      'push_status': null,
    });
    expect(closed.sms, NoticeDelivery.none);
    expect(closed.push, NoticeDelivery.noApp);
    expect(closed.readAt, isNull);
    for (final s in [
      'sent',
      'failed',
      'off',
      'simulated',
      'notSetUp',
      'expired',
    ]) {
      expect(NoticeDelivery.fromStatus(s).name, s);
    }
    expect(NoticeDelivery.fromStatus('queued'), NoticeDelivery.waiting);
  });

  test('an incident_board row parses, with UTC times made local', () {
    final incident = Incident.fromJson({
      'id': 'INC-0147',
      'origin': 'sos',
      'channel': 'app',
      'status': 'pendingVerification',
      'suggested_type': 'flood',
      'emergency_type': null,
      'latitude': 14.6042,
      'longitude': 120.9946,
      'barangay': 'Barangay 412',
      'district': 'Sampaloc',
      'address': null,
      'accuracy_m': 12,
      'captured_at': '2026-09-30T00:05:26.123456+00:00',
      'received_at': '2026-09-30T00:05:40+00:00',
      'manila_resident_id': 'res-101',
      'people_count': 3,
      'note': null,
      'vulnerable': ['seniorCitizen'],
      'account_verified': true,
      'mock_location': false,
      'verification_method': null,
      'assigned_unit_id': null,
      'suggestion_overridden': false,
      'override_reason': null,
      'false_report': false,
      'resolved_at': null,
      'crowd_report_ids': <String>[],
      'events': [
        {
          'kind': 'received',
          'at': '2026-09-30T00:05:40+00:00',
          'actor_name': null,
          'detail': null,
        },
      ],
    });

    expect(incident.capturedAt.isUtc, isFalse);
    expect(
      incident.capturedAt.toUtc(),
      DateTime.utc(2026, 9, 30, 0, 5, 26, 123, 456),
    );
    expect(incident.accuracyMeters, 12.0);
    expect(incident.vulnerable, [VulnerabilityType.seniorCitizen]);
    expect(incident.events.single.kind, IncidentEventKind.received);
  });

  test('audit rows with numeric ids and the system role parse', () {
    final entry = AuditEntry.fromJson({
      'log_id': 42,
      'timestamp': '2026-09-30T00:10:00+00:00',
      'account_id': 'system',
      'account_name': 'System',
      'account_role': 'system',
      'action_type': 'statusChanged',
      'target_table': 'incident_report',
      'target_id': 'INC-0147',
      'detail': 'enRoute',
    });

    expect(entry.id, '42');
    expect(entry.actorRole, UserRole.system);
  });

  test('a number the database already masked is shown as is', () {
    final resident = Resident.fromJson({
      'manila_resident_id': 'res-101',
      'fullname': 'Test Resident',
      'contact_number': '0917 ••• 4821',
      'barangay': 'Barangay 412',
      'district': 'Sampaloc',
      'household': <Object?>[],
      'consent_given_at': null,
      'updated_at': null,
    });

    expect(resident.maskedContact, '0917 ••• 4821');
  });

  test('revealing a contact returns the number and is audited', () async {
    final backend = MockBackend();
    await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
    final residentId = (await backend.watchVulnerable().first).first.id;

    final number = await backend.revealContact(residentId);

    expect(number, isNot(contains('•')));
    final audit = await backend.watchAudit(10).first;
    expect(audit.first.action, AuditAction.contactViewed);
    expect(audit.first.targetId, residentId);
  });

  test('app_setting rows parse (captured from the hosted project)', () {
    final s = AppSetting.fromJson({
      'key': 'priority.mock_location',
      'value': -20,
      'category': 'priority',
      'max_value': 0,
      'min_value': -200,
      'updated_at': '2026-09-30T21:30:44.481935+00:00',
      'updated_by': null,
      'description': 'Points for a suspected mock location (a penalty)',
    });
    expect(s.value, -20);
    expect((s.min, s.max), (-200, 0));
    expect(s.updatedAt!.isUtc, isFalse);
    expect(PriorityRules.fromSettings([s]).mockLocationPenalty, -20);
  });

  test('audit rows for setting changes parse', () {
    final e = AuditEntry.fromJson({
      'log_id': 2101,
      'timestamp': '2026-10-01T01:00:00+00:00',
      'account_id': '00000000-0000-4000-8000-00000000000a',
      'account_name': 'E. Navarro',
      'account_role': 'admin',
      'action_type': 'settingChanged',
      'target_table': 'app_setting',
      'target_id': 'priority.sos',
      'detail': '50 → 60',
    });
    expect(e.action, AuditAction.settingChanged);
  });
}
