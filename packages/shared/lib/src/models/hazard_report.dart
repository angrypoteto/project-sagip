import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';
import 'offline.dart';

/// A hazard report as the resident's phone sees it (R4). Reports never
/// become incidents on their own: only a DBSCAN cluster of them does
/// (FR7, FR15). The server-side record is [CrowdReport].
@immutable
class HazardReport {
  const HazardReport({
    required this.clientId,
    required this.capturedAt,
    required this.description,
    required this.delivery,
    this.type,
    this.location,
    this.accuracyMeters,
    this.barangay,
    this.district,
    this.deliveredAt,
    this.serverId,
    this.rejectReason,
  });

  /// Generated on the phone ([newClientId]).
  final String clientId;

  /// When the resident pressed Send. Never replaced by upload time (NFR1).
  final DateTime capturedAt;
  final String description;

  /// The resident's optional choice; the classifier suggests one on the
  /// server either way (FR12).
  final IncidentType? type;
  final GeoPoint? location;
  final double? accuracyMeters;
  final String? barangay;
  final String? district;
  final DeliveryState delivery;
  final DateTime? deliveredAt;

  /// The server's id once delivered, for example "rep-301".
  final String? serverId;
  final String? rejectReason;

  HazardReport copyWith({
    DeliveryState? delivery,
    DateTime? deliveredAt,
    String? serverId,
    String? rejectReason,
  }) => HazardReport(
    clientId: clientId,
    capturedAt: capturedAt,
    description: description,
    type: type,
    location: location,
    accuracyMeters: accuracyMeters,
    barangay: barangay,
    district: district,
    delivery: delivery ?? this.delivery,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    serverId: serverId ?? this.serverId,
    rejectReason: rejectReason ?? this.rejectReason,
  );

  factory HazardReport.fromJson(Map<String, Object?> json) => HazardReport(
    clientId: json['client_id']! as String,
    capturedAt: timeFromJson(json['captured_at']),
    description: json['description']! as String,
    type: enumFromJsonOrNull(IncidentType.values, json['type']),
    location: json['latitude'] == null
        ? null
        : GeoPoint(
            (json['latitude']! as num).toDouble(),
            (json['longitude']! as num).toDouble(),
          ),
    accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
    barangay: json['barangay'] as String?,
    district: json['district'] as String?,
    delivery: enumFromJson(DeliveryState.values, json['delivery']),
    deliveredAt: timeFromJsonOrNull(json['delivered_at']),
    serverId: json['server_id'] as String?,
    rejectReason: json['reject_reason'] as String?,
  );

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'description': description,
    'type': type?.name,
    'latitude': location?.lat,
    'longitude': location?.lng,
    'accuracy_m': accuracyMeters,
    'barangay': barangay,
    'district': district,
    'delivery': delivery.name,
    'delivered_at': deliveredAt?.toUtc().toIso8601String(),
    'server_id': serverId,
    'reject_reason': rejectReason,
  };
}

/// Why the phone refused to save a report (R4 errors).
enum ReportRejection {
  emptyDescription,

  /// FR15: S.A.G.I.P. covers Manila City only.
  outsideManila,

  /// FR15, NFR7: too many reports from one account in a short time.
  rateLimited,

  /// The phone has never had a GPS fix.
  noLocation,
}

class ReportRejected implements Exception {
  const ReportRejected(this.reason);

  final ReportRejection reason;

  @override
  String toString() => 'ReportRejected($reason)';
}

/// A rough box around Manila City. Stands in for the bundled barangay
/// boundaries (plan R4) until those are added; the server checks again.
bool roughlyInsideManila(GeoPoint p) =>
    p.lat >= 14.550 && p.lat <= 14.640 && p.lng >= 120.940 && p.lng <= 121.030;
