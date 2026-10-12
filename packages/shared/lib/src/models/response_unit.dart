import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';

/// An ambulance, rescue boat, rescue team, or fire truck (RESPONSE_UNIT,
/// Figure 3.6b, plus station and crew size from Table 3.1 item 3):
/// MDRRMD's own, or another responder's in Manila ([agency]).
@immutable
class ResponseUnit {
  const ResponseUnit({
    required this.id,
    required this.callSign,
    required this.type,
    required this.station,
    this.crewSize,
    required this.status,
    this.agency = UnitAgency.mdrrmd,
    this.source,
    this.location,
    this.lastLocationAt,
    this.currentIncidentId,
    this.retiredAt,
  });

  final String id;

  /// For example "R-03".
  final String callSign;
  final UnitType type;
  final String station;

  /// Null when not known (units listed from public records).
  final int? crewSize;
  final UnitAgency agency;

  /// Where the record comes from when an admin did not enter it.
  final String? source;

  /// Self-reported by responders (FR9).
  final UnitStatus status;
  final GeoPoint? location;
  final DateTime? lastLocationAt;

  /// The incident this unit is handling, if any.
  final String? currentIncidentId;

  /// Set when an admin took the unit out of service (A2).
  final DateTime? retiredAt;

  bool get retired => retiredAt != null;

  /// Can take a new assignment: in service, marked Available, and not
  /// already assigned.
  bool get isDispatchable =>
      !retired && status == UnitStatus.available && currentIncidentId == null;

  ResponseUnit copyWith({
    UnitStatus? status,
    GeoPoint? location,
    DateTime? lastLocationAt,
    String? currentIncidentId,
    bool clearIncident = false,
    String? callSign,
    UnitType? type,
    String? station,
    int? crewSize,
    DateTime? retiredAt,
    bool clearRetired = false,
  }) => ResponseUnit(
    id: id,
    callSign: callSign ?? this.callSign,
    type: type ?? this.type,
    station: station ?? this.station,
    crewSize: crewSize ?? this.crewSize,
    status: status ?? this.status,
    agency: agency,
    source: source,
    location: location ?? this.location,
    lastLocationAt: lastLocationAt ?? this.lastLocationAt,
    currentIncidentId: clearIncident
        ? null
        : (currentIncidentId ?? this.currentIncidentId),
    retiredAt: clearRetired ? null : (retiredAt ?? this.retiredAt),
  );

  factory ResponseUnit.fromJson(Map<String, Object?> json) => ResponseUnit(
    id: json['unit_id']! as String,
    callSign: json['call_sign']! as String,
    type: enumFromJson(UnitType.values, json['unit_type']),
    station: json['station']! as String,
    crewSize: json['crew_size'] as int?,
    agency: enumFromJson(UnitAgency.values, json['agency'] ?? 'mdrrmd'),
    source: json['source'] as String?,
    status: enumFromJson(UnitStatus.values, json['status']),
    location: json['last_latitude'] == null
        ? null
        : GeoPoint(
            (json['last_latitude']! as num).toDouble(),
            (json['last_longitude']! as num).toDouble(),
          ),
    lastLocationAt: timeFromJsonOrNull(json['last_location_at']),
    currentIncidentId: json['current_incident_id'] as String?,
    retiredAt: timeFromJsonOrNull(json['retired_at']),
  );

  Map<String, Object?> toJson() => {
    'unit_id': id,
    'call_sign': callSign,
    'unit_type': type.name,
    'station': station,
    'crew_size': crewSize,
    'agency': agency.name,
    'source': source,
    'status': status.name,
    'last_latitude': location?.lat,
    'last_longitude': location?.lng,
    'last_location_at': lastLocationAt?.toIso8601String(),
    'current_incident_id': currentIncidentId,
    'retired_at': retiredAt?.toUtc().toIso8601String(),
  };
}

/// One supply of a unit as its crew last reported it (`unit_supply`).
@immutable
class UnitSupply {
  const UnitSupply({
    required this.unitId,
    required this.item,
    required this.quantity,
    required this.capacity,
    required this.updatedAt,
    required this.updatedByName,
  });

  final String unitId;
  final SupplyItem item;

  /// A percent for fuel and tank water; otherwise how many are on board.
  final double quantity;

  /// 100 for a percent; otherwise how many a full load is.
  final double capacity;
  final DateTime updatedAt;
  final String updatedByName;

  /// The level `inventory.low_percent` starts from (the database seeds the
  /// same).
  static const defaultLowPercent = 30.0;

  /// A report older than this is shown as old: nobody has confirmed the
  /// level since.
  static const staleAfter = Duration(hours: 24);

  /// 0 to 1.
  double get level => capacity <= 0 ? 0 : (quantity / capacity).clamp(0, 1);

  SupplyState stateAt(double lowPercent) => quantity <= 0
      ? SupplyState.out
      : level * 100 <= lowPercent
      ? SupplyState.low
      : SupplyState.ok;

  bool isStale(DateTime now) => now.difference(updatedAt) > staleAfter;

  factory UnitSupply.fromJson(Map<String, Object?> json) => UnitSupply(
    unitId: json['unit_id']! as String,
    item: enumFromJson(SupplyItem.values, json['item']),
    quantity: (json['quantity']! as num).toDouble(),
    capacity: (json['capacity']! as num).toDouble(),
    updatedAt: timeFromJson(json['updated_at']),
    updatedByName: json['updated_by_name'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'unit_id': unitId,
    'item': item.name,
    'quantity': quantity,
    'capacity': capacity,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'updated_by_name': updatedByName,
  };
}

/// A unit's supplies in the order of [SupplyItem], and the ones that are
/// low or out at [lowPercent].
List<UnitSupply> suppliesOf(String unitId, Iterable<UnitSupply> all) => [
  for (final s in all)
    if (s.unitId == unitId) s,
]..sort((a, b) => a.item.index.compareTo(b.item.index));

List<UnitSupply> shortSupplies(
  Iterable<UnitSupply> supplies,
  double lowPercent,
) => [
  for (final s in supplies)
    if (s.stateAt(lowPercent) != SupplyState.ok) s,
];
