import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

// MDRRMD validates the crew's report; fire stages as MDRRMD records them
// (2026-11-11).
void main() {
  final at = DateTime.utc(2026, 11, 11, 4);

  Map<String, Object?> board({List<Object?> events = const []}) => {
    'id': 'INC-0300',
    'origin': 'sos',
    'channel': 'app',
    'status': 'onScene',
    'emergency_type': 'fire',
    'latitude': 14.6,
    'longitude': 120.98,
    'barangay': 'Barangay 1',
    'district': 'Tondo',
    'captured_at': at.toIso8601String(),
    'received_at': at.toIso8601String(),
    'events': events,
    'done_reported_at': at.add(const Duration(minutes: 30)).toIso8601String(),
    'crew_reports': [
      {
        'report_id': 'r-1',
        'unit_id': 'unit-bfp-tondo',
        'call_sign': 'BFP-TONDO',
        'captured_at': at.toIso8601String(),
        'outcome': 'rescued',
        'persons_assisted': 2,
        'validated_at': null,
      },
    ],
  };

  test('the board row reads the crew report and the done time', () {
    final i = Incident.fromJson(board());
    expect(i.doneReported, isTrue);
    expect(i.reportsAwaitingValidation.single.unitLabel, 'BFP-TONDO');
    expect(Incident.fromJson(i.toJson()).crewReports.single.personsAssisted, 2);
  });

  test('an event kind this version does not know is skipped', () {
    final i = Incident.fromJson(
      board(
        events: [
          {'kind': 'received', 'at': at.toIso8601String()},
          {'kind': 'somethingNewer', 'at': at.toIso8601String()},
        ],
      ),
    );
    expect(i.events.map((e) => e.kind), [IncidentEventKind.received]);
  });

  test('fire stages: the newest time per stage, and the highest alarm', () {
    Map<String, Object?> stage(String s, int minutes) => {
      'kind': 'fireStage',
      'at': at.add(Duration(minutes: minutes)).toIso8601String(),
      'detail': s,
    };
    final i = Incident.fromJson(
      board(
        events: [
          stage('firstAlarm', 3),
          stage('secondAlarm', 6),
          stage('firstAlarm', 4),
          stage('fireOut', 18),
        ],
      ),
    );
    expect(
      i.fireStages[FireStage.firstAlarm],
      at.add(const Duration(minutes: 4)).toLocal(),
    );
    expect(i.highestAlarm, FireStage.secondAlarm);
  });

  test('validating marks a changed figure as corrected', () {
    final r = Incident.fromJson(board()).crewReports.single;
    final same = r.validate(at: at, byName: 'R. Santos');
    expect(same.validated, isTrue);
    expect(same.corrected, isFalse);
    final changed = r.validate(
      at: at,
      byName: 'R. Santos',
      correction: const CrewReportCorrection(injured: 1),
    );
    expect(changed.corrected, isTrue);
    expect(changed.injured, 1);
  });

  test('the report figures read the new counts', () {
    final s = ReportSource.fromJson({
      'from': at.toIso8601String(),
      'to': at.toIso8601String(),
      'reports_awaiting_validation': 2,
      'fires_by_highest_alarm': {'secondAlarm': 1, 'unknownStage': 4},
      'median_fire_out_s': 900,
    });
    expect(s.reportsAwaitingValidation, 2);
    expect(s.firesByHighestAlarm, {FireStage.secondAlarm: 1});
    expect(s.medianFireOutS, 900);
    expect(
      passedReportChecks(s, const []).contains(ReportCheck.allReportsValidated),
      isFalse,
    );
  });

  test('the draft names fire alarms and the reports still waiting', () {
    final s = ReportSource(
      from: at,
      to: at.add(const Duration(days: 1)),
      incidents: 2,
      resolved: 2,
      completionReports: 1,
      reportsAwaitingValidation: 1,
      firesByHighestAlarm: const {FireStage.secondAlarm: 1},
      medianFireOutS: 1080,
    );
    final text = draftReportSections(s).map((x) => x.body).join(' ');
    expect(text, contains('Fires by highest alarm: 2nd alarm 1.'));
    expect(text, contains('fire out took a median of 18 minutes.'));
    expect(
      text,
      contains('1 more report awaits validation by MDRRMD and is not counted'),
    );
  });
}
