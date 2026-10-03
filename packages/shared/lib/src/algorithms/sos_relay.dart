import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/sos.dart';

/// The Tier 3 SOS packet (plan section 11, Q31, Q32): what a phone with no
/// internet and no cellular signal advertises over Bluetooth LE, and what
/// nearby phones running the app pass on and upload.
///
/// Classic (legacy) advertising leaves 24 bytes for service data, so the
/// packet is binary:
///
///     byte 0       version (high 4 bits, 1), hops (2 bits), mock (1 bit),
///                  has location (1 bit)
///     bytes 1-16   the SOS's client UUID, the same id as the app and SMS
///                  copies, so the server keeps one incident (Q31)
///     bytes 17-18  latitude  in 0.00001 degrees north of 14.4
///     bytes 19-20  longitude in 0.00001 degrees east of 120.9
///     bytes 21-23  capture time in Unix seconds, low 24 bits (about 194
///                  days; the receiver takes the most recent such time)
///
/// The location box (14.4 to 15.055 N, 120.9 to 121.555 E) covers Metro
/// Manila with a wide margin, to about 1 m. There is no name, number, or
/// resident id in the packet (RA 10173); the server files it as an SOS from
/// an unknown sender until the resident's own copy arrives.
@immutable
class SosRelayPacket {
  const SosRelayPacket({
    required this.clientId,
    required this.capturedAt,
    this.location,
    this.mockLocation = false,
    this.hops = 0,
  });

  /// The SOS's client UUID, lowercase with dashes.
  final String clientId;
  final DateTime capturedAt;
  final GeoPoint? location;
  final bool mockLocation;

  /// How many phones passed it on (0 = the sender's own advert).
  final int hops;

  static const version = 1;
  static const length = 24;

  /// Phones stop passing a packet on after this many hops.
  static const maxHops = 3;

  /// The 16-bit service UUID the packet travels under (unregistered; fine
  /// for a proof of concept; a deployment registers one with the Bluetooth
  /// SIG).
  static const serviceUuid16 = 0x5A61;

  static const _originLat = 14.4;
  static const _originLng = 120.9;
  static const _span = 65535;

  factory SosRelayPacket.of(SosRequest sos) => SosRelayPacket(
    clientId: sos.clientId,
    capturedAt: sos.capturedAt,
    location: sos.location,
    mockLocation: sos.mockLocationSuspected,
  );

  SosRelayPacket nextHop() => SosRelayPacket(
    clientId: clientId,
    capturedAt: capturedAt,
    location: location,
    mockLocation: mockLocation,
    hops: hops + 1,
  );

  bool get canHop => hops < maxHops;

  /// The 24 bytes. A location outside the box is sent as "no location".
  Uint8List encode() {
    final out = Uint8List(length);
    final hex = clientId.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
      throw const FormatException('bad_id');
    }
    final loc = location;
    final dLat = loc == null ? -1 : ((loc.lat - _originLat) * 1e5).round();
    final dLng = loc == null ? -1 : ((loc.lng - _originLng) * 1e5).round();
    final hasLoc = dLat >= 0 && dLat <= _span && dLng >= 0 && dLng <= _span;
    out[0] =
        (version << 4) |
        (hops.clamp(0, 3) << 2) |
        (mockLocation ? 2 : 0) |
        (hasLoc ? 1 : 0);
    for (var i = 0; i < 16; i++) {
      out[1 + i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (hasLoc) {
      out[17] = dLat >> 8;
      out[18] = dLat & 0xFF;
      out[19] = dLng >> 8;
      out[20] = dLng & 0xFF;
    }
    final seconds = capturedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    out[21] = (seconds >> 16) & 0xFF;
    out[22] = (seconds >> 8) & 0xFF;
    out[23] = seconds & 0xFF;
    return out;
  }

  /// Reads a packet heard at [now]. Throws [FormatException] (`bad_length`,
  /// `bad_version`) for anything else on the same service UUID.
  static SosRelayPacket decode(List<int> bytes, DateTime now) {
    if (bytes.length != length) throw const FormatException('bad_length');
    if (bytes[0] >> 4 != version) throw const FormatException('bad_version');
    final hex = [
      for (var i = 1; i <= 16; i++) bytes[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
    GeoPoint? location;
    if (bytes[0] & 1 == 1) {
      location = GeoPoint(
        _round5(_originLat + ((bytes[17] << 8) | bytes[18]) / 1e5),
        _round5(_originLng + ((bytes[19] << 8) | bytes[20]) / 1e5),
      );
    }
    // The newest time at or before now whose low 24 bits match.
    final low = (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    final nowSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    var seconds = nowSeconds - ((nowSeconds - low) % (1 << 24));
    if (seconds > nowSeconds) seconds -= 1 << 24;
    return SosRelayPacket(
      clientId: id,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ),
      location: location,
      mockLocation: bytes[0] & 2 == 2,
      hops: (bytes[0] >> 2) & 3,
    );
  }

  static double _round5(double v) => (v * 1e5).roundToDouble() / 1e5;

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'latitude': location?.lat,
    'longitude': location?.lng,
    'mock': mockLocation,
    'hops': hops,
  };

  factory SosRelayPacket.fromJson(Map<String, Object?> json) => SosRelayPacket(
    clientId: json['client_id']! as String,
    capturedAt: DateTime.parse(json['captured_at']! as String),
    location: json['latitude'] == null
        ? null
        : GeoPoint(
            (json['latitude']! as num).toDouble(),
            (json['longitude']! as num).toDouble(),
          ),
    mockLocation: json['mock'] as bool? ?? false,
    hops: json['hops'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is SosRelayPacket &&
      other.clientId == clientId &&
      other.capturedAt == capturedAt &&
      other.location == location &&
      other.mockLocation == mockLocation &&
      other.hops == hops;

  @override
  int get hashCode =>
      Object.hash(clientId, capturedAt, location, mockLocation, hops);
}
