import 'dart:convert';

import '../models/geo_point.dart';
import '../models/sos.dart';

/// The Tier 2 SOS text message (plan section 11, NFR1): short, versioned,
/// with a checksum, well under 160 characters, sent from the resident's own
/// number to the MDRRMD gateway SIM. The gateway forwards it to the
/// `sms-intake` Edge Function, which has the same codec in TypeScript
/// (`supabase/functions/_shared/sos_sms.ts`); keep the two in step.
///
///     SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>
///
/// - `id`: the SOS's client UUID without dashes (32 hex digits), so the
///   same SOS sent later over the internet is recognised, not doubled.
/// - `lat,lng`: 5 decimals (about 1 m), or `-` when the phone had no fix.
/// - `accuracy`: whole meters, or `-`.
/// - `time`: capture time in Unix seconds (never the send time).
/// - `flags`: `M` when the location may be mocked, else `-`.
/// - `crc`: CRC-16/CCITT-FALSE of everything before it, 4 hex digits.
///
/// The sender's number identifies the resident on the server; no name or
/// resident id is in the message.
abstract final class SosSms {
  static const prefix = 'SAGIP1';

  static String encode(SosRequest sos) {
    final id = sos.clientId.replaceAll('-', '').toLowerCase();
    final loc = sos.location;
    final body = [
      prefix,
      'SOS',
      id,
      loc == null
          ? '-'
          : '${loc.lat.toStringAsFixed(5)},${loc.lng.toStringAsFixed(5)}',
      loc == null || sos.accuracyMeters == null
          ? '-'
          : '${sos.accuracyMeters!.round()}',
      '${sos.capturedAt.toUtc().millisecondsSinceEpoch ~/ 1000}',
      sos.mockLocationSuspected ? 'M' : '-',
    ].join(' ');
    return '$body ${crc16Hex(body)}';
  }

  /// Reads a message; throws [FormatException] with a short reason
  /// (`not_sagip`, `bad_checksum`, `bad_field`).
  static SosSmsRecord decode(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length != 8 || parts[0] != prefix || parts[1] != 'SOS') {
      throw const FormatException('not_sagip');
    }
    final body = parts.take(7).join(' ');
    if (parts[7].toUpperCase() != crc16Hex(body)) {
      throw const FormatException('bad_checksum');
    }
    final id = parts[2].toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const FormatException('bad_field');
    }
    GeoPoint? location;
    if (parts[3] != '-') {
      final ll = parts[3].split(',');
      final lat = ll.length == 2 ? double.tryParse(ll[0]) : null;
      final lng = ll.length == 2 ? double.tryParse(ll[1]) : null;
      if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
        throw const FormatException('bad_field');
      }
      location = GeoPoint(lat, lng);
    }
    double? accuracy;
    if (parts[4] != '-') {
      final a = RegExp(r'^\d{1,6}$').hasMatch(parts[4])
          ? int.parse(parts[4])
          : null;
      if (a == null || a > 100000) {
        throw const FormatException('bad_field');
      }
      accuracy = a.toDouble();
    }
    final seconds = RegExp(r'^\d{1,12}$').hasMatch(parts[5])
        ? int.parse(parts[5])
        : null;
    if (seconds == null || seconds <= 0) {
      throw const FormatException('bad_field');
    }
    if (parts[6] != 'M' && parts[6] != '-') {
      throw const FormatException('bad_field');
    }
    return SosSmsRecord(
      clientId:
          '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}'
          '-${id.substring(16, 20)}-${id.substring(20)}',
      location: location,
      accuracyMeters: accuracy,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ),
      mockLocation: parts[6] == 'M',
    );
  }
}

/// What a Tier 2 message carries.
class SosSmsRecord {
  const SosSmsRecord({
    required this.clientId,
    required this.capturedAt,
    required this.mockLocation,
    this.location,
    this.accuracyMeters,
  });

  final String clientId;
  final GeoPoint? location;
  final double? accuracyMeters;
  final DateTime capturedAt;
  final bool mockLocation;
}

/// CRC-16/CCITT-FALSE (polynomial 0x1021, initial 0xFFFF) of [text]'s
/// UTF-8 bytes, as 4 uppercase hex digits. "123456789" gives "29B1".
String crc16Hex(String text) {
  var crc = 0xFFFF;
  for (final byte in utf8.encode(text)) {
    crc ^= byte << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}
