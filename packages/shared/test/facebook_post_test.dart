import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The Facebook line in the incident panel (Joshua, 2026-10-16: a unit was
/// assigned and nothing was posted, because the SOS had no type).
void main() {
  final at = DateTime(2026, 10, 16, 1);
  Incident sos({
    IncidentType? type,
    VerificationMethod? verified,
    String? unit,
    bool simulated = false,
  }) => Incident(
    id: 'INC-0167',
    origin: IncidentOrigin.sos,
    channel: ReportChannel.app,
    status: unit == null
        ? IncidentStatus.pendingVerification
        : IncidentStatus.assigned,
    location: const GeoPoint(14.58, 121.0),
    barangay: 'Barangay 856',
    district: 'Pandacan',
    capturedAt: at,
    receivedAt: at,
    suggestedType: type,
    verificationMethod: verified,
    assignedUnitId: unit,
    isSimulated: simulated,
  );

  FacebookPostState state(Incident i, {IncidentPost? post, bool on = true}) =>
      facebookPostState(i, post, switchOn: on);

  test('why nothing is on the Page yet', () {
    expect(state(sos(unit: 'unit-r03')), FacebookPostState.needsType);
    expect(
      state(sos(type: IncidentType.medical, unit: 'unit-r03')),
      FacebookPostState.neverPosted,
    );
    expect(
      state(sos(type: IncidentType.flood)),
      FacebookPostState.waitingForUnit,
    );
    expect(
      state(sos(type: IncidentType.flood, unit: 'unit-r03'), on: false),
      FacebookPostState.switchedOff,
    );
    expect(
      state(sos(type: IncidentType.fire, unit: 'unit-r03', simulated: true)),
      FacebookPostState.simulated,
    );
    // Ready, and the post row not there yet.
    expect(
      state(sos(type: IncidentType.fire, unit: 'unit-r03')),
      FacebookPostState.posting,
    );
  });

  test('what the post row says', () {
    final i = sos(type: IncidentType.flood, unit: 'unit-r03');
    IncidentPost row(String stage, String status) =>
        IncidentPost(stage: stage, status: status);
    expect(
      state(i, post: row('unverified', 'sent')),
      FacebookPostState.postedUnverified,
    );
    expect(
      state(i, post: row('confirmed', 'sent')),
      FacebookPostState.postedConfirmed,
    );
    expect(
      state(i, post: row('falseAlarm', 'sent')),
      FacebookPostState.postedFalseAlarm,
    );
    expect(
      state(i, post: row('confirmed', 'queued')),
      FacebookPostState.posting,
    );
    expect(
      state(i, post: row('confirmed', 'failed')),
      FacebookPostState.failed,
    );
    expect(
      state(i, post: row('withdrawn', 'withdrawn')),
      FacebookPostState.notNeeded,
    );
    expect(state(i, post: row('confirmed', 'off')), FacebookPostState.heldBack);
    final parsed = IncidentPost.fromJson(const {
      'stage': 'unverified',
      'status': 'sent',
      'detail': 'post 1_2',
      'updated_at': '2026-10-16T01:00:00Z',
    });
    expect(parsed.stage, 'unverified');
    expect(parsed.detail, 'post 1_2');
    expect(parsed.updatedAt, isNotNull);
  });
}
