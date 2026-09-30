import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';

/// An MDRRMD ambulance, rescue boat, or rescue team (RESPONSE_UNIT,
/// Figure 3.6b, plus station and crew size from Table 3.1 item 3).
@immutable
class ResponseUnit {
  const ResponseUnit({
    required this.id,
    required this.callSign,
    required this.type,
    required this.station,
    required this.crewSize,
    required this.status,
    this.location,
    this.lastLocationAt,
    this.currentIncidentId,
  });

  final String id;

  /// For example "R-03".
  final String callSign;
  final UnitType type;
  final String station;
  final int crewSize;

  /// Self-reported by responders (FR9).
  final UnitStatus status;
  final GeoPoint? location;
  final DateTime? lastLocationAt;

  /// The incident this unit is handling, if any.
  final String? currentIncidentId;

  /// Can take a new assignment: marked Available and not already assigned.
  bool get isDispatchable =>
      status == UnitStatus.available && currentIncidentId == null;

  ResponseUnit copyWith({
    UnitStatus? status,
    GeoPoint? location,
    DateTime? lastLocationAt,
    String? currentIncidentId,
    bool clearIncident = false,
  }) => ResponseUnit(
    id: id,
    callSign: callSign,
    type: type,
    station: station,
    crewSize: crewSize,
    status: status ?? this.status,
    location: location ?? this.location,
    lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    currentIncidentId: clearIncident
        ? null
        : (currentIncidentId ?? this.currentIncidentId),
  );

  factory ResponseUnit.fromJson(Map<String, Object?> json) => ResponseUnit(
    id: json['unit_id']! as String,
    callSign: json['call_sign']! as String,
    type: enumFromJson(UnitType.values, json['unit_type']),
    station: json['station']! as String,
    crewSize: json['crew_size']! as int,
    status: enumFromJson(UnitStatus.values, json['status']),
    location: json['last_latitude'] == null
        ? null
        : GeoPoint(
            (json['last_latitude']! as num).toDouble(),
            (json['last_longitude']! as num).toDouble(),
          ),
    lastLocationAt: timeFromJsonOrNull(json['last_location_at']),
    currentIncidentId: json['current_incident_id'] as String?,
  );

  Map<String, Object?> toJson() => {
    'unit_id': id,
    'call_sign': callSign,
    'unit_type': type.name,
    'station': station,
    'crew_size': crewSize,
    'status': status.name,
    'last_latitude': location?.lat,
    'last_longitude': location?.lng,
    'last_location_at': lastLocationAt?.toIso8601String(),
    'current_incident_id': currentIncidentId,
  };
}
