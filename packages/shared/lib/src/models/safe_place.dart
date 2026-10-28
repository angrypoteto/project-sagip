import 'package:flutter/foundation.dart' show immutable;

import '../algorithms/dijkstra/hazard_penalty.dart';
import 'enums.dart';
import 'geo_point.dart';

/// What a safe place is (Joshua, 2026-10-19). Only an admin adds an
/// [evacuationCenter] (MDRRMD's own); the rest come from OpenStreetMap.
enum SafePlaceKind {
  evacuationCenter,
  school,
  barangayHall,
  coveredCourt,
  basketballCourt,
  openSpace,
  hospital,
}

/// A place that can serve as a safe place in an emergency. No capacity or
/// occupancy: evacuation center management is out of scope (CLAUDE.md).
@immutable
class SafePlace {
  const SafePlace({
    required this.id,
    required this.kind,
    required this.location,
    this.name,
    this.barangay,
    this.district,
    this.official = false,
    this.hidden = false,
  });

  /// `osm-n123` (a point on OpenStreetMap), `osm-w123` (an outline), or
  /// `adm-…` (added by an admin).
  final String id;

  /// Many courts and parks have no name on the map.
  final String? name;
  final SafePlaceKind kind;
  final GeoPoint location;
  final String? barangay;
  final String? district;

  /// An evacuation center MDRRMD designated.
  final bool official;

  /// Hidden by an admin (a wrong place); never suggested.
  final bool hidden;

  bool get fromMap => id.startsWith('osm-');

  factory SafePlace.fromJson(Map<String, dynamic> json) => SafePlace(
    id: json['place_id'] as String,
    name: json['name'] as String?,
    kind:
        SafePlaceKind.values.asNameMap()[json['kind']] ??
        SafePlaceKind.openSpace,
    location: GeoPoint(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    ),
    barangay: json['barangay'] as String?,
    district: json['district'] as String?,
    official: json['official'] as bool? ?? false,
    hidden: json['hidden_at'] != null,
  );

  Map<String, dynamic> toJson() => {
    'place_id': id,
    'name': name,
    'kind': kind.name,
    'latitude': location.lat,
    'longitude': location.lng,
    'barangay': barangay,
    'district': district,
    'official': official,
  };

  SafePlace copyWith({bool? hidden}) => SafePlace(
    id: id,
    kind: kind,
    location: location,
    name: name,
    barangay: barangay,
    district: district,
    official: official,
    hidden: hidden ?? this.hidden,
  );

  @override
  bool operator ==(Object other) =>
      other is SafePlace &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.location == location &&
      other.barangay == barangay &&
      other.district == district &&
      other.official == official &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    location,
    barangay,
    district,
    official,
    hidden,
  );
}

/// A suggested place and how far it is in a straight line.
@immutable
class SafePlaceOption {
  const SafePlaceOption(this.place, this.meters);

  final SafePlace place;
  final double meters;

  factory SafePlaceOption.fromJson(Map<String, dynamic> json) =>
      SafePlaceOption(
        SafePlace.fromJson(json),
        (json['meters'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is SafePlaceOption &&
      other.place == place &&
      other.meters == meters;

  @override
  int get hashCode => Object.hash(place, meters);
}

/// The rules (provisional, for MDRRMD to confirm). The database's
/// `safe_places_near()` applies the same ones (migration `safe_places`).
abstract final class SafePlaceRules {
  /// The kinds of place that suit an emergency.
  static Set<SafePlaceKind> kindsFor(IncidentType need) => switch (need) {
    // Somewhere high; open ground floods first.
    IncidentType.flood => const {
      SafePlaceKind.evacuationCenter,
      SafePlaceKind.school,
      SafePlaceKind.barangayHall,
      SafePlaceKind.coveredCourt,
    },
    // Open ground, away from the fire.
    IncidentType.fire => const {
      SafePlaceKind.evacuationCenter,
      SafePlaceKind.basketballCourt,
      SafePlaceKind.coveredCourt,
      SafePlaceKind.openSpace,
      SafePlaceKind.school,
    },
    // Open ground away from buildings.
    IncidentType.structural => const {
      SafePlaceKind.evacuationCenter,
      SafePlaceKind.basketballCourt,
      SafePlaceKind.openSpace,
    },
    IncidentType.medical => const {SafePlaceKind.hospital},
  };

  /// How far a place must be from the emergency itself.
  static double minMetersFor(IncidentType need) => switch (need) {
    IncidentType.fire => 300,
    IncidentType.structural => 100,
    _ => 0,
  };

  /// How near a confirmed open flood or fire a place may not be.
  static double avoidMeters(IncidentType hazard) =>
      hazard == IncidentType.fire ? 300 : 150;

  static const defaultLimit = 3;
}

/// The nearest [places] that suit [need] from [from], nearest first, at
/// most [limit]. Places near one of [avoid] (confirmed open floods and
/// fires) are left out. The phone uses this offline on the bundled list;
/// online the server does the same with its own list.
List<SafePlaceOption> nearestSafePlaces(
  Iterable<SafePlace> places,
  GeoPoint from,
  IncidentType need, {
  Iterable<HazardZone> avoid = const [],
  int limit = SafePlaceRules.defaultLimit,
}) {
  final kinds = SafePlaceRules.kindsFor(need);
  final min = SafePlaceRules.minMetersFor(need);
  final zones = avoid.toList();
  final options =
      <SafePlaceOption>[
        for (final p in places)
          if (!p.hidden && kinds.contains(p.kind))
            SafePlaceOption(p, from.distanceTo(p.location)),
      ]..retainWhere(
        (o) =>
            o.meters >= min &&
            !zones.any(
              (z) =>
                  z.center.distanceTo(o.place.location) <
                  SafePlaceRules.avoidMeters(z.type),
            ),
      );
  options.sort((a, b) {
    final byDistance = a.meters.compareTo(b.meters);
    return byDistance != 0 ? byDistance : a.place.id.compareTo(b.place.id);
  });
  return options.take(limit).toList();
}
