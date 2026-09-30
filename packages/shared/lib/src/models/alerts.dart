import 'package:flutter/foundation.dart';

import 'enums.dart';

/// Who issued an alert (R7). PHIVOLCS advisories are relayed only; the
/// system does not forecast earthquakes or volcanoes (scope guardrail).
enum AlertSource { pagasa, phivolcs, efcos, mdrrmd }

/// How urgent an alert is. Drives the icon and tone, never color alone.
enum AlertLevel { info, warning, critical }

/// A public alert shown to residents (R7, R8, FR14): weather warnings,
/// relayed advisories, and MDRRMD notices.
@immutable
class PublicAlert {
  const PublicAlert({
    required this.id,
    required this.source,
    required this.level,
    required this.title,
    required this.body,
    required this.issuedAt,
    this.guidance = const [],
    this.barangays = const [],
    this.read = false,
  });

  final String id;
  final AlertSource source;
  final AlertLevel level;

  /// Title and text come from the issuing agency, so they are content,
  /// not UI strings.
  final String title;
  final String body;
  final DateTime issuedAt;

  /// What to do, one step per entry (for example, wear a face mask during
  /// ashfall, FR14).
  final List<String> guidance;

  /// Affected barangays. Empty means all of Manila.
  final List<String> barangays;

  /// Whether this resident has opened it.
  final bool read;

  PublicAlert copyWith({bool? read}) => PublicAlert(
    id: id,
    source: source,
    level: level,
    title: title,
    body: body,
    issuedAt: issuedAt,
    guidance: guidance,
    barangays: barangays,
    read: read ?? this.read,
  );

  factory PublicAlert.fromJson(Map<String, Object?> json) => PublicAlert(
    id: '${json['alert_id']}',
    source: enumFromJson(AlertSource.values, json['source']),
    level: enumFromJson(AlertLevel.values, json['level']),
    title: json['title']! as String,
    body: json['body']! as String,
    issuedAt: timeFromJson(json['issued_at']),
    guidance: [
      for (final g in (json['guidance'] as List<Object?>? ?? const []))
        g! as String,
    ],
    barangays: [
      for (final b in (json['barangays'] as List<Object?>? ?? const []))
        b! as String,
    ],
    read: json['read'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'alert_id': id,
    'source': source.name,
    'level': level.name,
    'title': title,
    'body': body,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'guidance': guidance,
    'barangays': barangays,
    'read': read,
  };
}

/// Hazards the 72-hour forecast covers (LSTM + KDE, plan 10.5).
enum ForecastHazard { flood, fire, stormSurge }

enum RiskLevel { low, moderate, high }

/// The 72-hour risk forecast for one barangay (R7 Forecast tab, FR4).
@immutable
class BarangayForecast {
  const BarangayForecast({
    required this.barangay,
    required this.district,
    required this.issuedAt,
    required this.validUntil,
    required this.risks,
    this.isSimulated = false,
  });

  final String barangay;
  final String district;
  final DateTime issuedAt;
  final DateTime validUntil;
  final Map<ForecastHazard, RiskLevel> risks;

  /// True while the model runs on a simulated live feed (thesis scope).
  final bool isSimulated;

  /// The hazard with the highest risk, for the preparation tips.
  ForecastHazard? get topHazard {
    ForecastHazard? top;
    for (final h in ForecastHazard.values) {
      final r = risks[h] ?? RiskLevel.low;
      if (r == RiskLevel.low) continue;
      if (top == null || r.index > risks[top]!.index) top = h;
    }
    return top;
  }

  factory BarangayForecast.fromJson(Map<String, Object?> json) =>
      BarangayForecast(
        barangay: json['barangay']! as String,
        district: json['district']! as String,
        issuedAt: timeFromJson(json['issued_at']),
        validUntil: timeFromJson(json['valid_until']),
        risks: {
          for (final e in (json['risks']! as Map<String, Object?>).entries)
            enumFromJson(ForecastHazard.values, e.key): enumFromJson(
              RiskLevel.values,
              e.value,
            ),
        },
        isSimulated: json['is_simulated'] as bool? ?? false,
      );

  /// A row of the `barangay_forecast` table: one column per hazard.
  factory BarangayForecast.fromRow(Map<String, Object?> row) =>
      BarangayForecast(
        barangay: row['barangay']! as String,
        district: row['district']! as String,
        issuedAt: timeFromJson(row['issued_at']),
        validUntil: timeFromJson(row['valid_until']),
        risks: {
          ForecastHazard.flood: enumFromJson(
            RiskLevel.values,
            row['flood_risk'],
          ),
          ForecastHazard.fire: enumFromJson(RiskLevel.values, row['fire_risk']),
          ForecastHazard.stormSurge: enumFromJson(
            RiskLevel.values,
            row['surge_risk'],
          ),
        },
        isSimulated: row['is_simulated'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {
    'barangay': barangay,
    'district': district,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'valid_until': validUntil.toUtc().toIso8601String(),
    'risks': {for (final e in risks.entries) e.key.name: e.value.name},
    'is_simulated': isSimulated,
  };
}

/// Everything the Alerts tab shows, plus when the phone last received it,
/// so the offline state can say "Last updated 2:15 PM".
@immutable
class AlertFeed {
  const AlertFeed({
    required this.alerts,
    required this.updatedAt,
    this.forecast,
  });

  /// Newest first.
  final List<PublicAlert> alerts;

  /// Null when no forecast exists yet for the resident's barangay.
  final BarangayForecast? forecast;
  final DateTime updatedAt;

  int get unread => alerts.where((a) => !a.read).length;
}
