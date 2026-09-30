import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';
import 'offline.dart';

/// What a resident can add after sending an SOS (R2 "Add details"). All of
/// it is optional and never holds up the SOS itself.
@immutable
class SosDetails {
  const SosDetails({
    this.type,
    this.peopleCount,
    this.needsExtraHelp = false,
    this.note,
  });

  final IncidentType? type;
  final int? peopleCount;

  /// "Someone here needs extra help" (a senior, a PWD, a pregnant woman).
  final bool needsExtraHelp;
  final String? note;

  bool get isEmpty =>
      type == null &&
      peopleCount == null &&
      !needsExtraHelp &&
      (note == null || note!.trim().isEmpty);

  factory SosDetails.fromJson(Map<String, Object?> json) => SosDetails(
    type: enumFromJsonOrNull(IncidentType.values, json['type']),
    peopleCount: json['people_count'] as int?,
    needsExtraHelp: json['needs_extra_help'] as bool? ?? false,
    note: json['note'] as String?,
  );

  Map<String, Object?> toJson() => {
    'type': type?.name,
    'people_count': peopleCount,
    'needs_extra_help': needsExtraHelp,
    'note': note,
  };
}

/// A resident's SOS as the phone sees it: the local record, plus the
/// server's progress once the SOS has arrived (R1, R2).
@immutable
class SosRequest {
  const SosRequest({
    required this.clientId,
    required this.capturedAt,
    required this.delivery,
    this.location,
    this.accuracyMeters,
    this.barangay,
    this.district,
    this.mockLocationSuspected = false,
    this.details = const SosDetails(),
    this.sentVia,
    this.sentAt,
    this.deliveredAt,
    this.incidentId,
    this.status,
    this.statusTimes = const {},
    this.unitCallSign,
    this.unitType,
    this.etaMinutes,
    this.responderLocation,
    this.responderLocationAt,
    this.rejectReason,
  });

  /// Generated on the phone ([newClientId]).
  final String clientId;

  /// When the resident finished the hold. Never replaced by upload time.
  final DateTime capturedAt;
  final DeliveryState delivery;

  /// The last known GPS position; null only if the phone never had a fix.
  final GeoPoint? location;
  final double? accuracyMeters;
  final String? barangay;
  final String? district;
  final bool mockLocationSuspected;
  final SosDetails details;

  /// The channel that got the SOS off the phone, and when. SMS replaces a
  /// Bluetooth relay, which may never reach anyone.
  final ReportChannel? sentVia;
  final DateTime? sentAt;

  /// When the server confirmed it.
  final DateTime? deliveredAt;

  /// Set once the server has it, for example "INC-0160".
  final String? incidentId;
  final IncidentStatus? status;

  /// When each status was reached, for the R2 timeline.
  final Map<IncidentStatus, DateTime> statusTimes;

  final String? unitCallSign;
  final UnitType? unitType;
  final int? etaMinutes;

  /// The assigned unit's last reported position and when it was sent
  /// (R3 Track responder).
  final GeoPoint? responderLocation;
  final DateTime? responderLocationAt;
  final String? rejectReason;

  bool get isDelivered => delivery == DeliveryState.delivered;

  /// Still needs the resident's attention: not rejected and not resolved.
  bool get isActive =>
      delivery != DeliveryState.rejected && status != IncidentStatus.resolved;

  SosRequest copyWith({
    DeliveryState? delivery,
    SosDetails? details,
    ReportChannel? sentVia,
    DateTime? sentAt,
    DateTime? deliveredAt,
    String? incidentId,
    IncidentStatus? status,
    Map<IncidentStatus, DateTime>? statusTimes,
    String? unitCallSign,
    UnitType? unitType,
    int? etaMinutes,
    GeoPoint? responderLocation,
    DateTime? responderLocationAt,
    String? rejectReason,
  }) => SosRequest(
    clientId: clientId,
    capturedAt: capturedAt,
    delivery: delivery ?? this.delivery,
    location: location,
    accuracyMeters: accuracyMeters,
    barangay: barangay,
    district: district,
    mockLocationSuspected: mockLocationSuspected,
    details: details ?? this.details,
    sentVia: sentVia ?? this.sentVia,
    sentAt: sentAt ?? this.sentAt,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    incidentId: incidentId ?? this.incidentId,
    status: status ?? this.status,
    statusTimes: statusTimes ?? this.statusTimes,
    unitCallSign: unitCallSign ?? this.unitCallSign,
    unitType: unitType ?? this.unitType,
    etaMinutes: etaMinutes ?? this.etaMinutes,
    responderLocation: responderLocation ?? this.responderLocation,
    responderLocationAt: responderLocationAt ?? this.responderLocationAt,
    rejectReason: rejectReason ?? this.rejectReason,
  );

  /// Moves to [next] at [at], keeping the time for the timeline.
  SosRequest withStatus(IncidentStatus next, DateTime at) =>
      copyWith(status: next, statusTimes: {...statusTimes, next: at});

  factory SosRequest.fromJson(Map<String, Object?> json) => SosRequest(
    clientId: json['client_id']! as String,
    capturedAt: timeFromJson(json['captured_at']),
    delivery: enumFromJson(DeliveryState.values, json['delivery']),
    location: json['latitude'] == null
        ? null
        : GeoPoint(
            (json['latitude']! as num).toDouble(),
            (json['longitude']! as num).toDouble(),
          ),
    accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
    barangay: json['barangay'] as String?,
    district: json['district'] as String?,
    mockLocationSuspected: json['mock_location'] as bool? ?? false,
    details: json['details'] == null
        ? const SosDetails()
        : SosDetails.fromJson(json['details']! as Map<String, Object?>),
    sentVia: enumFromJsonOrNull(ReportChannel.values, json['sent_via']),
    sentAt: timeFromJsonOrNull(json['sent_at']),
    deliveredAt: timeFromJsonOrNull(json['delivered_at']),
    incidentId: json['incident_id'] as String?,
    status: enumFromJsonOrNull(IncidentStatus.values, json['status']),
    statusTimes: {
      for (final e
          in (json['status_times'] as Map<String, Object?>? ?? const {})
              .entries)
        IncidentStatus.values.byName(e.key): timeFromJson(e.value),
    },
    unitCallSign: json['unit_call_sign'] as String?,
    unitType: enumFromJsonOrNull(UnitType.values, json['unit_type']),
    etaMinutes: json['eta_minutes'] as int?,
    responderLocation: json['responder_latitude'] == null
        ? null
        : GeoPoint(
            (json['responder_latitude']! as num).toDouble(),
            (json['responder_longitude']! as num).toDouble(),
          ),
    responderLocationAt: timeFromJsonOrNull(json['responder_location_at']),
    rejectReason: json['reject_reason'] as String?,
  );

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'delivery': delivery.name,
    'latitude': location?.lat,
    'longitude': location?.lng,
    'accuracy_m': accuracyMeters,
    'barangay': barangay,
    'district': district,
    'mock_location': mockLocationSuspected,
    'details': details.toJson(),
    'sent_via': sentVia?.name,
    'sent_at': sentAt?.toUtc().toIso8601String(),
    'delivered_at': deliveredAt?.toUtc().toIso8601String(),
    'incident_id': incidentId,
    'status': status?.name,
    'status_times': {
      for (final e in statusTimes.entries)
        e.key.name: e.value.toUtc().toIso8601String(),
    },
    'unit_call_sign': unitCallSign,
    'unit_type': unitType?.name,
    'eta_minutes': etaMinutes,
    'responder_latitude': responderLocation?.lat,
    'responder_longitude': responderLocation?.lng,
    'responder_location_at': responderLocationAt?.toUtc().toIso8601String(),
    'reject_reason': rejectReason,
  };
}
