import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';

/// What happened to an incident, shown as its timeline.
enum IncidentEventKind {
  received,
  smsCheckSent,
  smsReplyReceived,
  verified,
  typeConfirmed,
  assigned,
  enRoute,
  onScene,
  resolved,
  markedFalseReport,
}

@immutable
class IncidentEvent {
  const IncidentEvent({
    required this.kind,
    required this.at,
    this.actorName,
    this.detail,
  });

  final IncidentEventKind kind;
  final DateTime at;

  /// Who did it (dispatcher, responder) or null for the system.
  final String? actorName;

  /// Short extra text such as a unit call sign or a type name.
  final String? detail;

  factory IncidentEvent.fromJson(Map<String, Object?> json) => IncidentEvent(
    kind: enumFromJson(IncidentEventKind.values, json['kind']),
    at: DateTime.parse(json['at']! as String),
    actorName: json['actor_name'] as String?,
    detail: json['detail'] as String?,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'at': at.toIso8601String(),
    'actor_name': actorName,
    'detail': detail,
  };
}

/// An SOS or a confirmed crowd-report cluster on the Triage Queue
/// (INCIDENT_REPORT in Figure 3.6a, plus fields the plan adds in Q15-Q17).
@immutable
class Incident {
  const Incident({
    required this.id,
    required this.origin,
    required this.channel,
    required this.status,
    required this.location,
    required this.barangay,
    required this.district,
    required this.capturedAt,
    required this.receivedAt,
    this.suggestedType,
    this.confirmedType,
    this.address,
    this.accuracyMeters,
    this.residentId,
    this.peopleCount,
    this.note,
    this.vulnerable = const [],
    this.accountVerified = false,
    this.mockLocationSuspected = false,
    this.verificationMethod,
    this.crowdReportIds = const [],
    this.assignedUnitId,
    this.suggestionOverridden = false,
    this.overrideReason,
    this.falseReport = false,
    this.resolvedAt,
    this.events = const [],
  });

  final String id;
  final IncidentOrigin origin;
  final ReportChannel channel;
  final IncidentStatus status;

  /// Classifier or resident suggestion, confirmed or overridden by the
  /// dispatcher (FR12).
  final IncidentType? suggestedType;
  final IncidentType? confirmedType;

  final GeoPoint location;

  /// For example "Barangay 412".
  final String barangay;

  /// For example "Sampaloc".
  final String district;
  final String? address;
  final double? accuracyMeters;

  /// When the phone captured the SOS. Never replaced by upload time (NFR1).
  final DateTime capturedAt;
  final DateTime receivedAt;

  /// The resident who sent the SOS. Null for crowd-report clusters.
  final String? residentId;
  final int? peopleCount;

  /// Free text from the resident's "Add details".
  final String? note;

  /// Vulnerability types in the sender's household, from the Vulnerable
  /// Resident Priority List.
  final List<VulnerabilityType> vulnerable;

  /// Registered account with a verified mobile number (FR8).
  final bool accountVerified;

  /// The phone reported a mock-location provider (FR8).
  final bool mockLocationSuspected;

  /// Set once the dispatcher or a responder confirms the SOS.
  final VerificationMethod? verificationMethod;

  /// Member reports when [origin] is [IncidentOrigin.crowdCluster].
  final List<String> crowdReportIds;

  final String? assignedUnitId;

  /// True when the dispatcher chose a unit other than the top suggestion.
  final bool suggestionOverridden;
  final String? overrideReason;

  final bool falseReport;
  final DateTime? resolvedAt;
  final List<IncidentEvent> events;

  /// The type to display: the confirmed one if set, else the suggestion.
  IncidentType? get type => confirmedType ?? suggestedType;

  bool get typeConfirmed => confirmedType != null;

  bool get isVerified =>
      verificationMethod != null || origin == IncidentOrigin.crowdCluster;

  String get place => '$barangay, $district';

  Incident copyWith({
    IncidentStatus? status,
    IncidentType? confirmedType,
    VerificationMethod? verificationMethod,
    String? assignedUnitId,
    bool clearAssignedUnit = false,
    bool? suggestionOverridden,
    String? overrideReason,
    bool? falseReport,
    DateTime? resolvedAt,
    List<String>? crowdReportIds,
    List<IncidentEvent>? events,
  }) {
    return Incident(
      id: id,
      origin: origin,
      channel: channel,
      status: status ?? this.status,
      location: location,
      barangay: barangay,
      district: district,
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      suggestedType: suggestedType,
      confirmedType: confirmedType ?? this.confirmedType,
      address: address,
      accuracyMeters: accuracyMeters,
      residentId: residentId,
      peopleCount: peopleCount,
      note: note,
      vulnerable: vulnerable,
      accountVerified: accountVerified,
      mockLocationSuspected: mockLocationSuspected,
      verificationMethod: verificationMethod ?? this.verificationMethod,
      crowdReportIds: crowdReportIds ?? this.crowdReportIds,
      assignedUnitId: clearAssignedUnit
          ? null
          : (assignedUnitId ?? this.assignedUnitId),
      suggestionOverridden: suggestionOverridden ?? this.suggestionOverridden,
      overrideReason: overrideReason ?? this.overrideReason,
      falseReport: falseReport ?? this.falseReport,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      events: events ?? this.events,
    );
  }

  Incident withEvent(IncidentEvent event) =>
      copyWith(events: [...events, event]);

  factory Incident.fromJson(Map<String, Object?> json) => Incident(
    id: json['id']! as String,
    origin: enumFromJson(IncidentOrigin.values, json['origin']),
    channel: enumFromJson(ReportChannel.values, json['channel']),
    status: enumFromJson(IncidentStatus.values, json['status']),
    suggestedType: enumFromJsonOrNull(
      IncidentType.values,
      json['suggested_type'],
    ),
    confirmedType: enumFromJsonOrNull(
      IncidentType.values,
      json['emergency_type'],
    ),
    location: GeoPoint(
      (json['latitude']! as num).toDouble(),
      (json['longitude']! as num).toDouble(),
    ),
    barangay: json['barangay']! as String,
    district: json['district']! as String,
    address: json['address'] as String?,
    accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
    capturedAt: DateTime.parse(json['captured_at']! as String),
    receivedAt: DateTime.parse(json['received_at']! as String),
    residentId: json['manila_resident_id'] as String?,
    peopleCount: json['people_count'] as int?,
    note: json['note'] as String?,
    vulnerable: [
      for (final v in (json['vulnerable'] as List<Object?>? ?? const []))
        enumFromJson(VulnerabilityType.values, v),
    ],
    accountVerified: json['account_verified'] as bool? ?? false,
    mockLocationSuspected: json['mock_location'] as bool? ?? false,
    verificationMethod: enumFromJsonOrNull(
      VerificationMethod.values,
      json['verification_method'],
    ),
    crowdReportIds: [
      for (final id in (json['crowd_report_ids'] as List<Object?>? ?? const []))
        id! as String,
    ],
    assignedUnitId: json['assigned_unit_id'] as String?,
    suggestionOverridden: json['suggestion_overridden'] as bool? ?? false,
    overrideReason: json['override_reason'] as String?,
    falseReport: json['false_report'] as bool? ?? false,
    resolvedAt: json['resolved_at'] == null
        ? null
        : DateTime.parse(json['resolved_at']! as String),
    events: [
      for (final e in (json['events'] as List<Object?>? ?? const []))
        IncidentEvent.fromJson(e! as Map<String, Object?>),
    ],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'origin': origin.name,
    'channel': channel.name,
    'status': status.name,
    'suggested_type': suggestedType?.name,
    'emergency_type': confirmedType?.name,
    'latitude': location.lat,
    'longitude': location.lng,
    'barangay': barangay,
    'district': district,
    'address': address,
    'accuracy_m': accuracyMeters,
    'captured_at': capturedAt.toIso8601String(),
    'received_at': receivedAt.toIso8601String(),
    'manila_resident_id': residentId,
    'people_count': peopleCount,
    'note': note,
    'vulnerable': [for (final v in vulnerable) v.name],
    'account_verified': accountVerified,
    'mock_location': mockLocationSuspected,
    'verification_method': verificationMethod?.name,
    'crowd_report_ids': crowdReportIds,
    'assigned_unit_id': assignedUnitId,
    'suggestion_overridden': suggestionOverridden,
    'override_reason': overrideReason,
    'false_report': falseReport,
    'resolved_at': resolvedAt?.toIso8601String(),
    'events': [for (final e in events) e.toJson()],
  };
}
