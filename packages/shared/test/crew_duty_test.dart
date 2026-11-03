import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Crew duty safety nets (2026-11-03): a member starts their own duty, only
/// the head ends it, and an off-duty phone with the app in use is flagged.
void main() {
  final now = DateTime.utc(2026, 11, 3, 8);
  const quiet = Duration(minutes: 15);

  test('a crew row carries when the app was last open', () {
    final c = CrewMember.fromJson({
      'unit_id': 'unit-r03',
      'staff_id': 'a1',
      'display_name': 'L. Cruz',
      'personnel_id': null,
      'on_duty': false,
      'duty_since': null,
      'last_seen_at': null,
      'app_open_at': '2026-11-03T07:56:00+00:00',
    });
    expect(
      c.appOpenAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 3, 7, 56)),
      isTrue,
    );
    expect(c.isInUseOffDuty(now, quiet), isTrue);
    expect(c.isQuiet(now, quiet), isFalse);
  });

  test('in use off duty: only off duty, only recently', () {
    CrewMember m({required bool on, DateTime? open}) => CrewMember(
      unitId: 'u',
      staffId: 's',
      displayName: 'X',
      onDuty: on,
      appOpenAt: open,
    );
    final recent = now.subtract(const Duration(minutes: 5));
    final old = now.subtract(const Duration(minutes: 40));
    expect(m(on: false, open: recent).isInUseOffDuty(now, quiet), isTrue);
    expect(m(on: true, open: recent).isInUseOffDuty(now, quiet), isFalse);
    expect(m(on: false, open: old).isInUseOffDuty(now, quiet), isFalse);
    expect(m(on: false).isInUseOffDuty(now, quiet), isFalse);
    expect(
      CrewMember.fromJson(const {
        'unit_id': 'u',
        'staff_id': 's',
        'display_name': 'X',
      }).appOpenAt,
      isNull,
      reason: 'an older server sends no app_open_at',
    );
  });

  group('the dashboard mock follows set_crew_duty', () {
    late MockBackend backend;

    setUp(() {
      backend = MockBackend(clock: () => now, latency: Duration.zero);
    });

    Future<ActionRejection?> tryDuty(String id, bool on) async {
      try {
        await backend.setCrewDuty(id, onDuty: on);
        return null;
      } on ActionRejected catch (e) {
        return e.reason;
      }
    }

    test('a member starts their own duty but cannot end it', () async {
      await backend.signIn('l.cruz@sagip.test', MockSeed.demoPassword);
      final me = backend.currentUser!.id;
      expect(await tryDuty(me, true), isNull);
      expect(await tryDuty(me, false), ActionRejection.notAllowed);
      final head = (await backend.watchCrew().first).firstWhere(
        (c) => c.unitId == 'unit-r03' && c.staffId != me && c.onDuty,
      );
      expect(await tryDuty(head.staffId, false), ActionRejection.notAllowed);
      final mine = (await backend.watchCrew().first).firstWhere(
        (c) => c.staffId == me,
      );
      expect(mine.onDuty, isTrue);
      expect(mine.dutySince, now);
    });
  });
}
