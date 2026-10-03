import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'geo_point.dart';
import 'response_unit.dart';

/// How an ETA was estimated.
enum RoutingMethod {
  /// Dijkstra over the OSM road graph (plan 10.2).
  roadNetwork,

  /// Straight-line distance at an assumed city speed. Used until the road
  /// graph is ready, and as the fallback when routing fails.
  straightLine,
}

/// One ranked unit suggestion for an incident (FR3).
@immutable
class UnitSuggestion {
  const UnitSuggestion({
    required this.unit,
    required this.etaMinutes,
    required this.distanceKm,
    required this.method,
  });

  final ResponseUnit unit;
  final double etaMinutes;
  final double distanceKm;
  final RoutingMethod method;
}

/// The pages the feeds read: PAGASA's two (ingest-pagasa) and PHIVOLCS's
/// earthquake list (ingest-phivolcs).
enum FeedSource { pagasaRainfall, pagasaCyclone, phivolcs }

/// How the last check of one PAGASA source went (`feed_status`, D10).
@immutable
class FeedStatus {
  const FeedStatus({
    required this.source,
    required this.ok,
    required this.checkedAt,
    this.lastSuccessAt,
    this.lastError,
    this.failures = 0,
    this.seen = const {},
  });

  final FeedSource source;
  final bool ok;
  final DateTime checkedAt;
  final DateTime? lastSuccessAt;

  /// Why the last check failed; null after a success.
  final String? lastError;

  /// Failed checks in a row.
  final int failures;

  /// What the last successful check read: `state` (none, warning,
  /// bulletin), and `level` and `number` for a warning, `number`, `name`,
  /// `signal`, and `surgeM` for a bulletin.
  final Map<String, Object?> seen;

  factory FeedStatus.fromJson(Map<String, Object?> json) => FeedStatus(
    source: switch (json['source']) {
      'pagasa_rainfall' => FeedSource.pagasaRainfall,
      'pagasa_cyclone' => FeedSource.pagasaCyclone,
      'phivolcs' => FeedSource.phivolcs,
      final other => throw FormatException('Unknown feed source $other'),
    },
    ok: json['ok']! as bool,
    checkedAt: timeFromJson(json['checked_at']),
    lastSuccessAt: timeFromJsonOrNull(json['last_success_at']),
    lastError: json['last_error'] as String?,
    failures: (json['failures'] as int?) ?? 0,
    seen: (json['seen'] as Map?)?.cast<String, Object?>() ?? const {},
  );
}

/// A PHIVOLCS earthquake near Manila (`phivolcs_event`, D10). Relayed by
/// hand only (FR14): nothing reaches residents by itself.
@immutable
class Earthquake {
  const Earthquake({
    required this.key,
    required this.occurredAt,
    required this.location,
    required this.point,
    required this.depthKm,
    required this.magnitude,
    required this.distanceKm,
    this.bulletinUrl,
  });

  final String key;
  final DateTime occurredAt;

  /// As PHIVOLCS words it: "023 km S 66° E of Lobo (Batangas)".
  final String location;
  final GeoPoint point;
  final double depthKm;
  final double magnitude;

  /// From Manila City Hall.
  final double distanceKm;
  final String? bulletinUrl;

  /// The Weather page lists these (provisional): magnitude 3 and up within
  /// 200 km.
  static const minMagnitude = 3.0;
  static const withinKm = 200.0;

  bool get worthShowing => magnitude >= minMagnitude && distanceKm <= withinKm;

  factory Earthquake.fromJson(Map<String, Object?> json) => Earthquake(
    key: json['event_key']! as String,
    occurredAt: timeFromJson(json['occurred_at']),
    location: json['location']! as String,
    point: GeoPoint(
      (json['latitude']! as num).toDouble(),
      (json['longitude']! as num).toDouble(),
    ),
    depthKm: (json['depth_km']! as num).toDouble(),
    magnitude: (json['magnitude']! as num).toDouble(),
    distanceKm: (json['distance_km']! as num).toDouble(),
    bulletinUrl: json['bulletin_url'] as String?,
  );
}

/// Current PAGASA conditions for Manila (WEATHER_ALERT, Figure 3.6d).
@immutable
class WeatherStatus {
  const WeatherStatus({
    required this.signalLevel,
    required this.rainfallMmPerHour,
    required this.issuedAt,
    this.stormSurgeAdvisory,
    this.stormSurgeMeters,
    this.isSimulated = false,
  });

  /// Tropical cyclone wind signal, 0 when none is raised.
  final int signalLevel;
  final double rainfallMmPerHour;
  final String? stormSurgeAdvisory;

  /// Forecast storm surge height in metres; null when there is no
  /// advisory (or the reading predates the column).
  final double? stormSurgeMeters;
  final DateTime issuedAt;

  /// True while the prototype replays recorded data (thesis scope).
  final bool isSimulated;

  factory WeatherStatus.fromJson(Map<String, Object?> json) => WeatherStatus(
    signalLevel: json['signal_level']! as int,
    rainfallMmPerHour: (json['rainfall_intensity']! as num).toDouble(),
    stormSurgeAdvisory: json['storm_surge_advisory'] as String?,
    stormSurgeMeters: (json['storm_surge_m'] as num?)?.toDouble(),
    issuedAt: timeFromJson(json['issued_at']),
    isSimulated: json['is_simulated'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'signal_level': signalLevel,
    'rainfall_intensity': rainfallMmPerHour,
    'storm_surge_advisory': stormSurgeAdvisory,
    'storm_surge_m': stormSurgeMeters,
    'issued_at': issuedAt.toIso8601String(),
    'is_simulated': isSimulated,
  };
}

/// A time-stamped record of a dispatch action, status change, or
/// verification (AUDIT_LOG, FR11).
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.targetTable,
    required this.targetId,
    this.detail,
  });

  final String id;
  final DateTime at;
  final String actorId;
  final String actorName;
  final UserRole actorRole;
  final AuditAction action;
  final String targetTable;
  final String targetId;
  final String? detail;

  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
    id: '${json['log_id']}',
    at: timeFromJson(json['timestamp']),
    actorId: '${json['account_id']}',
    actorName: json['account_name']! as String,
    actorRole: enumFromJson(UserRole.values, json['account_role']),
    action: enumFromJson(AuditAction.values, json['action_type']),
    targetTable: json['target_table']! as String,
    targetId: json['target_id']! as String,
    detail: json['detail'] as String?,
  );

  Map<String, Object?> toJson() => {
    'log_id': id,
    'timestamp': at.toIso8601String(),
    'account_id': actorId,
    'account_name': actorName,
    'account_role': actorRole.name,
    'action_type': action.name,
    'target_table': targetTable,
    'target_id': targetId,
    'detail': detail,
  };
}
