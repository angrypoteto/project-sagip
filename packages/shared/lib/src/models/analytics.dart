import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'road_route.dart';

/// One row of a breakdown (by type, barangay, or unit).
@immutable
class AnalyticsGroup {
  const AnalyticsGroup({
    required this.key,
    required this.label,
    required this.count,
    this.avgDispatchS,
    this.avgResponseS,
    this.avgTravelS,
  });

  /// A type name (`flood`, or `unknown`), a barangay, or a unit id.
  final String key;

  /// "Barangay 412, Sampaloc" or "R-03"; the type name for types.
  final String label;
  final int count;
  final double? avgDispatchS;
  final double? avgResponseS;

  /// Units only: assignment to on scene.
  final double? avgTravelS;

  factory AnalyticsGroup.fromJson(Map<String, Object?> json) => AnalyticsGroup(
    key: json['key']! as String,
    label: json['label']! as String,
    count: (json['count']! as num).toInt(),
    avgDispatchS: (json['avg_dispatch_s'] as num?)?.toDouble(),
    avgResponseS: (json['avg_response_s'] as num?)?.toDouble(),
    avgTravelS: (json['avg_travel_s'] as num?)?.toDouble(),
  );
}

/// Incidents received on one Manila calendar day.
@immutable
class AnalyticsDay {
  const AnalyticsDay({
    required this.day,
    required this.count,
    this.avgResponseS,
  });

  /// Midnight of the Manila date (only the date matters).
  final DateTime day;
  final int count;
  final double? avgResponseS;

  factory AnalyticsDay.fromJson(Map<String, Object?> json) => AnalyticsDay(
    day: DateTime.parse(json['day']! as String),
    count: (json['count']! as num).toInt(),
    avgResponseS: (json['avg_response_s'] as num?)?.toDouble(),
  );
}

/// Dijkstra execution times of one kind in the period (Chapter 4).
@immutable
class RoutingStats {
  const RoutingStats({
    required this.kind,
    required this.runs,
    required this.avgMs,
    required this.p95Ms,
  });

  final RoutingRunKind kind;
  final int runs;
  final double avgMs;
  final double p95Ms;

  factory RoutingStats.fromJson(Map<String, Object?> json) => RoutingStats(
    kind: RoutingRunKind.values.byName(json['kind']! as String),
    runs: (json['runs']! as num).toInt(),
    avgMs: (json['avg_ms']! as num).toDouble(),
    p95Ms: (json['p95_ms']! as num).toDouble(),
  );
}

/// A4 Performance analytics for incidents received in [from, to)
/// (Objective 1). Times are in seconds from the incident timeline:
/// dispatch = received to first assignment, verify = received to verified,
/// response = received to on scene. Null when nothing in the period has
/// reached that step.
@immutable
class AnalyticsReport {
  const AnalyticsReport({
    required this.from,
    required this.to,
    required this.incidents,
    required this.resolved,
    required this.falseReports,
    required this.sos,
    required this.clusters,
    required this.sosByChannel,
    required this.byType,
    required this.byBarangay,
    required this.byUnit,
    required this.daily,
    required this.routing,
    this.avgDispatchS,
    this.medianDispatchS,
    this.avgVerifyS,
    this.avgResponseS,
    this.medianResponseS,
  });

  final DateTime from;
  final DateTime to;
  final int incidents;
  final int resolved;
  final int falseReports;
  final int sos;
  final int clusters;
  final double? avgDispatchS;
  final double? medianDispatchS;
  final double? avgVerifyS;
  final double? avgResponseS;
  final double? medianResponseS;
  final Map<ReportChannel, int> sosByChannel;
  final List<AnalyticsGroup> byType;

  /// The ten barangays with the most incidents.
  final List<AnalyticsGroup> byBarangay;
  final List<AnalyticsGroup> byUnit;
  final List<AnalyticsDay> daily;
  final List<RoutingStats> routing;

  factory AnalyticsReport.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) => [
      for (final e in (json[key] as List? ?? const []))
        (e as Map).cast<String, Object?>(),
    ];
    final channels = (json['sos_by_channel'] as Map? ?? const {})
        .cast<String, Object?>();
    return AnalyticsReport(
      from: timeFromJson(json['from']),
      to: timeFromJson(json['to']),
      incidents: (json['incidents']! as num).toInt(),
      resolved: (json['resolved']! as num).toInt(),
      falseReports: (json['false_reports']! as num).toInt(),
      sos: (json['sos']! as num).toInt(),
      clusters: (json['clusters']! as num).toInt(),
      avgDispatchS: (json['avg_dispatch_s'] as num?)?.toDouble(),
      medianDispatchS: (json['median_dispatch_s'] as num?)?.toDouble(),
      avgVerifyS: (json['avg_verify_s'] as num?)?.toDouble(),
      avgResponseS: (json['avg_response_s'] as num?)?.toDouble(),
      medianResponseS: (json['median_response_s'] as num?)?.toDouble(),
      sosByChannel: {
        for (final e in channels.entries)
          ReportChannel.values.byName(e.key): (e.value! as num).toInt(),
      },
      byType: [for (final g in list('by_type')) AnalyticsGroup.fromJson(g)],
      byBarangay: [
        for (final g in list('by_barangay')) AnalyticsGroup.fromJson(g),
      ],
      byUnit: [for (final g in list('by_unit')) AnalyticsGroup.fromJson(g)],
      daily: [for (final d in list('daily')) AnalyticsDay.fromJson(d)],
      routing: [for (final r in list('routing')) RoutingStats.fromJson(r)],
    );
  }
}
