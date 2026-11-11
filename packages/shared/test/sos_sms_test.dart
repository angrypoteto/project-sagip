import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/sos_sms_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final messages = [
    for (final m in vectors['messages']! as List) m as Map<String, Object?>,
  ];

  test('CRC-16/CCITT-FALSE matches the standard check value', () {
    final check = vectors['crc_check']! as Map<String, Object?>;
    expect(crc16Hex(check['text']! as String), check['crc']);
  });

  test('messages encode exactly as the shared vectors (TypeScript too)', () {
    for (final m in messages) {
      final lat = m['lat'] as num?;
      final sos = SosRequest(
        clientId: m['client_id']! as String,
        capturedAt: DateTime.parse(m['captured_at']! as String),
        delivery: DeliveryState.savedOnPhone,
        location: lat == null
            ? null
            : GeoPoint(lat.toDouble(), (m['lng']! as num).toDouble()),
        accuracyMeters: (m['accuracy_m'] as num?)?.toDouble(),
        mockLocationSuspected: m['mock']! as bool,
      );
      final text = SosSms.encode(sos);
      expect(text, m['text']);
      expect(text.length, lessThanOrEqualTo(160));
    }
  });

  test('messages decode to what was sent', () {
    for (final m in messages) {
      final r = SosSms.decode(m['text']! as String);
      expect(r.clientId, m['client_id']);
      expect(r.capturedAt, DateTime.parse(m['captured_at']! as String));
      expect(r.mockLocation, m['mock']);
      expect(r.location?.lat, (m['lat'] as num?)?.toDouble());
      expect(r.location?.lng, (m['lng'] as num?)?.toDouble());
      expect(r.accuracyMeters, (m['accuracy_m'] as num?)?.toDouble());
    }
  });

  test('a changed or foreign message is refused with a reason', () {
    final good = messages.first['text']! as String;
    Matcher refused(String reason) => throwsA(
      isA<FormatException>().having((e) => e.message, 'message', reason),
    );
    expect(() => SosSms.decode('Tulong! Baha dito'), refused('not_sagip'));
    expect(
      () => SosSms.decode(good.replaceFirst('14.60912', '14.60913')),
      refused('bad_checksum'),
    );
    // A well-formed checksum over a bad field is still refused.
    const body = 'SAGIP1 SOS 1234 14.6,121.0 8 1790754133 -';
    expect(
      () => SosSms.decode('$body ${crc16Hex(body)}'),
      refused('bad_field'),
    );
    const far = 'SAGIP1 SOS 3f2a9c1e7b4d4e0a9c2f1a2b3c4d5e6f 95.0,121.0 8 1 -';
    expect(() => SosSms.decode('$far ${crc16Hex(far)}'), refused('bad_field'));
    // Extra spaces and a lowercase checksum are fine.
    expect(
      SosSms.decode(
        '  ${good.toLowerCase().replaceFirst('sagip1 sos', 'SAGIP1 SOS')}  ',
      ).clientId,
      messages.first['client_id'],
    );
  });

  // The rescue texts exactly as send-alerts words them
  // (confirmationSmsText), so the app can follow its SOS with no data.
  test('reads the rescue texts the gateway sends', () {
    final sent = SosSms.parseRescue(
      'S.A.G.I.P.: Rescue team BFP-STAANA has been sent to your location. '
      'Stay where you are if it is safe and keep your phone on. Ref INC-0223.',
    )!;
    expect(sent.incidentId, 'INC-0223');
    expect(sent.status, IncidentStatus.assigned);
    expect(sent.unit, 'BFP-STAANA');

    final anyTeam = SosSms.parseRescue(
      'S.A.G.I.P.: A rescue team has been sent to your location. Stay where '
      'you are if it is safe and keep your phone on. Ref INC-0007.',
    )!;
    expect(anyTeam.unit, isNull);
    expect(anyTeam.status, IncidentStatus.assigned);

    final arrived = SosSms.parseRescue(
      'S.A.G.I.P.: Rescue team R-03 has arrived at your location. Ref INC-0010.',
    )!;
    expect(arrived.status, IncidentStatus.onScene);

    final closed = SosSms.parseRescue(
      'S.A.G.I.P.: Your SOS INC-0010 has been closed. If you still need '
      'help, send a new SOS or call MDRRMD.',
    )!;
    expect(closed.status, IncidentStatus.resolved);
    expect(closed.incidentId, 'INC-0010');

    expect(
      SosSms.parseRescue(
        'S.A.G.I.P.: Your SOS was received (INC-1, ref 12345678).',
      ),
      isNull,
    );
    expect(
      SosSms.parseRescue('Rescue team X has been sent. Ref INC-1.'),
      isNull,
    );
  });
}
