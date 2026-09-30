import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';
import 'offline.dart';
import 'response_unit.dart';

/// F4 offers "Arrived" within this distance of the scene (plan: about 50 m).
const arrivalRadiusMeters = 50.0;

/// What happened at the scene (F6).
enum RescueOutcome { rescued, treated, transported, noOneFound, falseReport }

/// An incident assigned to this responder's unit, as the phone sees it
/// (F1 to F6). It is cached on the phone at dispatch time so the responder
/// can work without a signal (CLAUDE.md offline rules).
@immutable
class Assignment {
  const Assignment({
    required this.incidentId,
    required this.offeredAt,
    required this.location,
    required this.barangay,
    required this.district,
    required this.channel,
    this.type,
    this.address,
    this.peopleCount,
    this.residentNote,
    this.vulnerable = const [],
    this.status = IncidentStatus.assigned,
    this.acceptedAt,
    this.onSceneAt,
    this.mapSaved = 0,
    this.realEmergency,
    this.notRealReason,
    this.peopleFound,
    this.closedByDispatcher = false,
  });

  final String incidentId;
  final DateTime offeredAt;
  final GeoPoint location;
  final String barangay;
  final String district;
  final String? address;

  /// How the SOS or report reached MDRRMD.
  final ReportChannel channel;
  final IncidentType? type;
  final int? peopleCount;
  final String? residentNote;

  /// Vulnerability types only, never names or medical details (plan Q9).
  final List<VulnerabilityType> vulnerable;

  /// assigned (offered), enRoute, onScene, or resolved.
  final IncidentStatus status;
  final DateTime? acceptedAt;
  final DateTime? onSceneAt;

  /// How much of the map around the route is saved for offline use, 0 to 1.
  final double mapSaved;

  /// F5, the on-scene check (FR8): was it a real emergency?
  final bool? realEmergency;
  final String? notRealReason;
  final int? peopleFound;

  /// The dispatcher reassigned or closed it; F3 shows a banner.
  final bool closedByDispatcher;

  String get place => '$barangay, $district';

  Assignment copyWith({
    IncidentStatus? status,
    DateTime? acceptedAt,
    DateTime? onSceneAt,
    double? mapSaved,
    bool? realEmergency,
    String? notRealReason,
    int? peopleFound,
    bool? closedByDispatcher,
  }) => Assignment(
    incidentId: incidentId,
    offeredAt: offeredAt,
    location: location,
    barangay: barangay,
    district: district,
    channel: channel,
    type: type,
    address: address,
    peopleCount: peopleCount,
    residentNote: residentNote,
    vulnerable: vulnerable,
    status: status ?? this.status,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    onSceneAt: onSceneAt ?? this.onSceneAt,
    mapSaved: mapSaved ?? this.mapSaved,
    realEmergency: realEmergency ?? this.realEmergency,
    notRealReason: notRealReason ?? this.notRealReason,
    peopleFound: peopleFound ?? this.peopleFound,
    closedByDispatcher: closedByDispatcher ?? this.closedByDispatcher,
  );

  factory Assignment.fromJson(Map<String, Object?> json) => Assignment(
    incidentId: json['incident_id']! as String,
    offeredAt: timeFromJson(json['offered_at']),
    location: GeoPoint(
      (json['latitude']! as num).toDouble(),
      (json['longitude']! as num).toDouble(),
    ),
    barangay: json['barangay']! as String,
    district: json['district']! as String,
    address: json['address'] as String?,
    channel: enumFromJson(ReportChannel.values, json['channel']),
    type: enumFromJsonOrNull(IncidentType.values, json['type']),
    peopleCount: json['people_count'] as int?,
    residentNote: json['resident_note'] as String?,
    vulnerable: [
      for (final v in (json['vulnerable'] as List<Object?>? ?? const []))
        enumFromJson(VulnerabilityType.values, v),
    ],
    status: enumFromJson(IncidentStatus.values, json['status']),
    acceptedAt: timeFromJsonOrNull(json['accepted_at']),
    onSceneAt: timeFromJsonOrNull(json['on_scene_at']),
    mapSaved: (json['map_saved'] as num?)?.toDouble() ?? 0,
    realEmergency: json['real_emergency'] as bool?,
    notRealReason: json['not_real_reason'] as String?,
    peopleFound: json['people_found'] as int?,
    closedByDispatcher: json['closed_by_dispatcher'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'incident_id': incidentId,
    'offered_at': offeredAt.toUtc().toIso8601String(),
    'latitude': location.lat,
    'longitude': location.lng,
    'barangay': barangay,
    'district': district,
    'address': address,
    'channel': channel.name,
    'type': type?.name,
    'people_count': peopleCount,
    'resident_note': residentNote,
    'vulnerable': [for (final v in vulnerable) v.name],
    'status': status.name,
    'accepted_at': acceptedAt?.toUtc().toIso8601String(),
    'on_scene_at': onSceneAt?.toUtc().toIso8601String(),
    'map_saved': mapSaved,
    'real_emergency': realEmergency,
    'not_real_reason': notRealReason,
    'people_found': peopleFound,
    'closed_by_dispatcher': closedByDispatcher,
  };
}

/// The completion and damage report (F6). Saved on the phone first.
@immutable
class CompletionReport {
  const CompletionReport({
    required this.clientId,
    required this.incidentId,
    required this.capturedAt,
    required this.outcome,
    required this.personsAssisted,
    required this.timeOnScene,
    this.housesDamaged = 0,
    this.injured = 0,
    this.missing = 0,
    this.affectedFamilies = 0,
    this.notes,
    this.delivery = DeliveryState.savedOnPhone,
  });

  final String clientId;
  final String incidentId;
  final DateTime capturedAt;
  final RescueOutcome outcome;
  final int personsAssisted;

  /// Filled in from the on-scene time; not typed by the responder.
  final Duration timeOnScene;

  // Damage assessment, following the NDRRMC template once MDRRMD sends it.
  final int housesDamaged;
  final int injured;
  final int missing;
  final int affectedFamilies;
  final String? notes;
  final DeliveryState delivery;

  CompletionReport withDelivery(DeliveryState next) => CompletionReport(
    clientId: clientId,
    incidentId: incidentId,
    capturedAt: capturedAt,
    outcome: outcome,
    personsAssisted: personsAssisted,
    timeOnScene: timeOnScene,
    housesDamaged: housesDamaged,
    injured: injured,
    missing: missing,
    affectedFamilies: affectedFamilies,
    notes: notes,
    delivery: next,
  );

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'incident_id': incidentId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'outcome': outcome.name,
    'persons_assisted': personsAssisted,
    'time_on_scene_s': timeOnScene.inSeconds,
    'houses_damaged': housesDamaged,
    'injured': injured,
    'missing': missing,
    'affected_families': affectedFamilies,
    'notes': notes,
    'delivery': delivery.name,
  };

  factory CompletionReport.fromJson(Map<String, Object?> json) =>
      CompletionReport(
        clientId: json['client_id']! as String,
        incidentId: json['incident_id']! as String,
        capturedAt: timeFromJson(json['captured_at']),
        outcome: enumFromJson(RescueOutcome.values, json['outcome']),
        personsAssisted: json['persons_assisted']! as int,
        timeOnScene: Duration(seconds: json['time_on_scene_s']! as int),
        housesDamaged: json['houses_damaged'] as int? ?? 0,
        injured: json['injured'] as int? ?? 0,
        missing: json['missing'] as int? ?? 0,
        affectedFamilies: json['affected_families'] as int? ?? 0,
        notes: json['notes'] as String?,
        delivery: enumFromJson(DeliveryState.values, json['delivery']),
      );
}

/// Everything the responder home screen needs (F1).
@immutable
class ResponderState {
  const ResponderState({
    required this.unit,
    this.current,
    this.offer,
    this.locationSentAt,
    this.gpsOn = true,
  });

  final ResponseUnit unit;

  /// The accepted assignment, if any.
  final Assignment? current;

  /// A new assignment waiting for "Accept and start" (F2).
  final Assignment? offer;

  /// When the unit's position last reached the server (location sharing).
  final DateTime? locationSentAt;
  final bool gpsOn;
}

/// Why a status change was refused on the phone (F1).
enum StatusRejection {
  /// On scene or en route with nothing assigned.
  noAssignment,

  /// Back to Available before the completion report is filed.
  finishReportFirst,

  /// En route again after arriving.
  alreadyOnScene,
}

class StatusRejected implements Exception {
  const StatusRejected(this.reason);

  final StatusRejection reason;

  @override
  String toString() => 'StatusRejected($reason)';
}
