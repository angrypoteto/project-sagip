import 'dart:math';

import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// What the phone can reach right now (plan 7.6). It decides how an SOS is
/// sent: internet first, then SMS to the MDRRMD gateway, then nearby phones.
enum SignalState {
  /// The backend answers (not just "Wi-Fi is on").
  internet,

  /// No internet, but the phone can send SMS (Tier 2).
  smsOnly,

  /// Neither internet nor cellular (Tier 3: relay through nearby phones).
  noSignal,
}

/// How far a record made on the phone has got (plan 7.6 delivery badges).
/// Every SOS, crowd report, and responder update is saved on the phone first
/// and only counts as delivered once the server confirms it (NFR1).
enum DeliveryState {
  /// Tier 1: in the offline queue, not sent yet.
  savedOnPhone,

  /// Going out over the internet right now.
  sending,

  /// Tier 2: sent as an SMS to the MDRRMD gateway; the phone is still
  /// waiting for the server to confirm it.
  sentBySms,

  /// Tier 3: handed to nearby phones over Bluetooth.
  relaying,

  /// The server confirmed it.
  delivered,

  /// The server refused it (for example, a location outside Manila).
  rejected;

  bool get isPending => this != delivered && this != rejected;
}

/// The kinds of records the offline queue holds.
enum QueuedKind { sos, crowdReport, statusUpdate, completionReport }

/// One entry in the offline queue (S6).
@immutable
class QueuedRecord {
  const QueuedRecord({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.delivery,
    this.rejectReason,
    this.waitedOffline = false,
  });

  /// The client id generated on the phone.
  final String id;
  final QueuedKind kind;

  /// When the phone captured it. Never replaced by the upload time (NFR1).
  final DateTime capturedAt;
  final DeliveryState delivery;
  final String? rejectReason;

  /// On a delivery event: the record could not go out right away and waited
  /// in the queue. Only these get the "was delivered" notice (NFR1); a
  /// record sent at once already shows its status on screen.
  final bool waitedOffline;
}

/// A GPS reading.
@immutable
class LocationFix {
  const LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.at,
    this.barangay,
    this.district,
    this.mockProvider = false,
    this.manual = false,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final DateTime at;

  /// Looked up on the phone from bundled boundaries, so it works offline.
  final String? barangay;
  final String? district;

  /// The phone reported a mock-location provider. Sent with the SOS for the
  /// dispatcher (FR8); never shown to the resident (plan R1).
  final bool mockProvider;

  /// Chosen by the resident on the map or from the barangay list (R5),
  /// not measured by GPS, so [accuracyMeters] means nothing.
  final bool manual;
}

/// Whether GPS is on, plus the last fix the phone has.
@immutable
class LocationStatus {
  const LocationStatus({required this.gpsOn, this.lastFix});

  final bool gpsOn;

  /// The last known fix. When GPS is off, an SOS still sends this and the
  /// barangay (plan R1).
  final LocationFix? lastFix;
}

/// A random version 4 UUID. Records get one on the phone so the server can
/// store an SOS once even if it arrives by internet, SMS, and Bluetooth
/// (plan Q31).
String newClientId([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}
