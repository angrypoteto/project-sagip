import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';

/// A resident's hazard report (CROWD_REPORT, Figure 3.6a). It only reaches
/// the Triage Queue as part of a DBSCAN cluster (FR7, FR15).
@immutable
class CrowdReport {
  const CrowdReport({
    required this.id,
    required this.description,
    required this.location,
    required this.barangay,
    required this.district,
    required this.channel,
    required this.submittedAt,
    this.residentId,
    this.suggestedType,
    this.suggestionConfidence,
    this.incidentId,
  });

  final String id;
  final String? residentId;
  final String description;
  final GeoPoint location;
  final String barangay;
  final String district;

  /// [ReportChannel.app] or [ReportChannel.webForm].
  final ReportChannel channel;
  final DateTime submittedAt;

  /// Output of the TF-IDF classifier (FR12) and its confidence, 0 to 1.
  final IncidentType? suggestedType;
  final double? suggestionConfidence;

  /// Set when the report belongs to a confirmed cluster.
  final String? incidentId;

  bool get isClustered => incidentId != null;

  String get place => '$barangay, $district';

  CrowdReport copyWith({String? incidentId}) => CrowdReport(
    id: id,
    residentId: residentId,
    description: description,
    location: location,
    barangay: barangay,
    district: district,
    channel: channel,
    submittedAt: submittedAt,
    suggestedType: suggestedType,
    suggestionConfidence: suggestionConfidence,
    incidentId: incidentId ?? this.incidentId,
  );

  factory CrowdReport.fromJson(Map<String, Object?> json) => CrowdReport(
    id: json['report_id']! as String,
    residentId: json['manila_resident_id'] as String?,
    description: json['description']! as String,
    location: GeoPoint(
      (json['latitude']! as num).toDouble(),
      (json['longitude']! as num).toDouble(),
    ),
    barangay: json['barangay']! as String,
    district: json['district']! as String,
    channel: enumFromJson(ReportChannel.values, json['source']),
    submittedAt: DateTime.parse(json['submitted_at']! as String),
    suggestedType: enumFromJsonOrNull(IncidentType.values, json['category']),
    suggestionConfidence: (json['category_confidence'] as num?)?.toDouble(),
    incidentId: json['incident_id'] as String?,
  );

  Map<String, Object?> toJson() => {
    'report_id': id,
    'manila_resident_id': residentId,
    'description': description,
    'latitude': location.lat,
    'longitude': location.lng,
    'barangay': barangay,
    'district': district,
    'source': channel.name,
    'submitted_at': submittedAt.toIso8601String(),
    'category': suggestedType?.name,
    'category_confidence': suggestionConfidence,
    'incident_id': incidentId,
  };
}
