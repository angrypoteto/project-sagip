import 'package:flutter/foundation.dart';

import 'enums.dart';
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

/// Current PAGASA conditions for Manila (WEATHER_ALERT, Figure 3.6d).
@immutable
class WeatherStatus {
  const WeatherStatus({
    required this.signalLevel,
    required this.rainfallMmPerHour,
    required this.issuedAt,
    this.stormSurgeAdvisory,
    this.isSimulated = false,
  });

  /// Tropical cyclone wind signal, 0 when none is raised.
  final int signalLevel;
  final double rainfallMmPerHour;
  final String? stormSurgeAdvisory;
  final DateTime issuedAt;

  /// True while the prototype replays recorded data (thesis scope).
  final bool isSimulated;

  factory WeatherStatus.fromJson(Map<String, Object?> json) => WeatherStatus(
    signalLevel: json['signal_level']! as int,
    rainfallMmPerHour: (json['rainfall_intensity']! as num).toDouble(),
    stormSurgeAdvisory: json['storm_surge_advisory'] as String?,
    issuedAt: DateTime.parse(json['issued_at']! as String),
    isSimulated: json['is_simulated'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'signal_level': signalLevel,
    'rainfall_intensity': rainfallMmPerHour,
    'storm_surge_advisory': stormSurgeAdvisory,
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
    id: json['log_id']! as String,
    at: DateTime.parse(json['timestamp']! as String),
    actorId: json['account_id']! as String,
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
