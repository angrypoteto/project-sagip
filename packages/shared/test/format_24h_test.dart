import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  // MDRRMD, 2026-11-10: times in 24-hour form ("army time").
  final now = DateTime(2026, 11, 10, 18);
  test('clock times are 24-hour', () {
    expect(formatTime(DateTime(2026, 11, 10, 14, 5), 'en_US'), '14:05');
    expect(formatClock(DateTime(2026, 11, 10, 9, 5, 7), 'en_US'), '09:05:07');
    expect(
      formatDateTime(DateTime(2026, 11, 10, 0, 30), 'en_US'),
      'Nov 10, 2026 00:30',
    );
  });
  test('a stamp is as short as it can be', () {
    expect(formatStamp(DateTime(2026, 11, 10, 14, 5), now, 'en_US'), '14:05');
    expect(
      formatStamp(DateTime(2026, 10, 21, 23, 40), now, 'en_US'),
      'Oct 21, 23:40',
    );
    expect(
      formatStamp(DateTime(2025, 12, 31, 8, 0), now, 'en_US'),
      'Dec 31, 2025, 08:00',
    );
  });
}
