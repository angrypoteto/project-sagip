import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// What TomTom reports on a road (2026-11-25, migration road_conditions).
enum RoadConditionKind { jam, closed, flooding }

/// A road TomTom reports as jammed, closed, or flooded inside Manila: road
/// names, a line, and how slow; no personal data. Outside data: it never
/// creates or confirms an incident (FR7).
@immutable
class RoadCondition {
  const RoadCondition({
    required this.id,
    required this.kind,
    required this.path,
    this.severity = 0,
    this.road,
    this.from,
    this.to,
    this.delaySeconds,
    this.lengthMeters,
    this.since,
  });

  final String id;
  final RoadConditionKind kind;

  /// TomTom's magnitude of delay: 0 unknown, 1 minor, 2 moderate, 3 major,
  /// 4 undefined (closures).
  final int severity;
  final String? road;
  final String? from;
  final String? to;
  final int? delaySeconds;
  final int? lengthMeters;
  final DateTime? since;

  /// The road's line, at least two points.
  final List<GeoPoint> path;

  /// A major jam (drawn red); minor and moderate ones are drawn orange.
  bool get isHeavy => kind == RoadConditionKind.jam && severity >= 3;

  /// PROVISIONAL until MDRRMD says how each slows its units: how many times
  /// longer a road takes. A closed road is as good as closed (like a fire's
  /// cordon), a flooded one as slow as a confirmed flood, a jam by how bad.
  double get factor => switch (kind) {
    RoadConditionKind.closed => 20,
    RoadConditionKind.flooding => 4,
    RoadConditionKind.jam => severity >= 3 ? 2.5 : 1.5,
  };

  /// A row of `road_conditions()`; null when it cannot be read.
  static RoadCondition? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = RoadConditionKind.values.asNameMap()[json['kind']];
    final raw = json['path'];
    if (id is! String || kind == null || raw is! List) return null;
    final path = <GeoPoint>[
      for (final p in raw)
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
          GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble()),
    ];
    if (path.length < 2) return null;
    final severity = json['severity'];
    final delay = json['delay'];
    final length = json['length'];
    final since = json['since'];
    return RoadCondition(
      id: id,
      kind: kind,
      path: path,
      severity: severity is num ? severity.toInt() : 0,
      road: json['road'] as String?,
      from: json['from'] as String?,
      to: json['to'] as String?,
      delaySeconds: delay is num ? delay.toInt() : null,
      lengthMeters: length is num ? length.toInt() : null,
      since: since is String ? DateTime.tryParse(since) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'severity': severity,
    'road': road,
    'from': from,
    'to': to,
    'delay': delaySeconds,
    'length': lengthMeters,
    'since': since?.toIso8601String(),
    'path': [
      for (final p in path) [p.lng, p.lat],
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is RoadCondition &&
      other.id == id &&
      other.kind == kind &&
      other.severity == severity &&
      other.path.length == path.length;

  @override
  int get hashCode => Object.hash(id, kind, severity, path.length);
}

/// The latest TomTom snapshot: the roads and when it was fetched.
@immutable
class RoadConditions {
  const RoadConditions({required this.items, this.fetchedAt, this.ok = true});

  static const none = RoadConditions(items: []);

  final List<RoadCondition> items;

  /// When TomTom was last asked; null before the first run.
  final DateTime? fetchedAt;

  /// False when the last run failed (the roads are the run before).
  final bool ok;

  /// Older than [maxAge] at [now]: the maps say so and routing ignores it.
  bool isStale(DateTime now, {Duration maxAge = const Duration(minutes: 15)}) =>
      fetchedAt == null || now.difference(fetchedAt!) > maxAge;

  /// The roads routing should slow at [now]: none once the snapshot is
  /// stale (a jam an hour old says nothing about the road now).
  List<RoadCondition> usable(DateTime now) =>
      isStale(now) ? const [] : items;

  static RoadConditions fromJson(Map<String, dynamic> json) {
    final at = json['fetched_at'];
    final items = json['items'];
    return RoadConditions(
      fetchedAt: at is String ? DateTime.tryParse(at) : null,
      ok: json['ok'] != false,
      items: [
        if (items is List)
          for (final r in items)
            if (r is Map) ?RoadCondition.fromJson(r.cast<String, dynamic>()),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'fetched_at': fetchedAt?.toIso8601String(),
    'ok': ok,
    'items': [for (final r in items) r.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RoadConditions &&
      other.fetchedAt == fetchedAt &&
      other.ok == ok &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(fetchedAt, ok, Object.hashAll(items));
}
