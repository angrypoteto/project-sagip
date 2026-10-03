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

/// SOS that one channel delivered first, and how long they took from the
/// phone's capture time to the server (Objective 3). A capture time after
/// the receipt counts as no delay.
@immutable
class SosDelivery {
  const SosDelivery({
    required this.channel,
    required this.count,
    required this.within60,
    required this.within300,
    required this.within900,
    this.medianS,
    this.p95S,
    this.maxS,
  });

  final ReportChannel channel;
  final int count;
  final double? medianS;
  final double? p95S;
  final double? maxS;

  /// Delivered within 1, 5, and 15 minutes of capture.
  final int within60;
  final int within300;
  final int within900;

  /// How many arrived within [seconds] (60, 300, or 900).
  int within(int seconds) => switch (seconds) {
    60 => within60,
    300 => within300,
    900 => within900,
    _ => throw ArgumentError.value(seconds, 'seconds'),
  };

  factory SosDelivery.fromJson(Map<String, Object?> json) => SosDelivery(
    channel: ReportChannel.values.byName(json['channel']! as String),
    count: (json['count']! as num).toInt(),
    medianS: (json['median_s'] as num?)?.toDouble(),
    p95S: (json['p95_s'] as num?)?.toDouble(),
    maxS: (json['max_s'] as num?)?.toDouble(),
    within60: (json['within_60']! as num).toInt(),
    within300: (json['within_300']! as num).toInt(),
    within900: (json['within_900']! as num).toInt(),
  );
}

/// The Objective 3 harness (`sos_delivery_report`): SOS received in the
/// period by the tier that delivered them first, and the Tier 3 relay log.
/// The trial team counts attempts on the phones; A4 divides.
@immutable
class SosDeliveryReport {
  const SosDeliveryReport({
    this.channels = const [],
    this.relayUploads = 0,
    this.relayedSos = 0,
    this.relayMaxHops,
  });

  final List<SosDelivery> channels;

  /// Relayed packets uploaded, and for how many distinct SOS.
  final int relayUploads;
  final int relayedSos;
  final int? relayMaxHops;

  /// The windows A4 shows; which one counts as success is Q44.
  static const windows = [60, 300, 900];

  int get delivered => channels.fold(0, (n, c) => n + c.count);

  int deliveredWithin(int seconds) =>
      channels.fold(0, (n, c) => n + c.within(seconds));

  factory SosDeliveryReport.fromJson(Map<String, Object?> json) =>
      SosDeliveryReport(
        channels: [
          for (final c in (json['channels'] as List? ?? const []))
            SosDelivery.fromJson((c as Map).cast<String, Object?>()),
        ],
        relayUploads: (json['relay_uploads'] as num?)?.toInt() ?? 0,
        relayedSos: (json['relayed_sos'] as num?)?.toInt() ?? 0,
        relayMaxHops: (json['relay_max_hops'] as num?)?.toInt(),
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
    this.delivery = const SosDeliveryReport(),
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

  /// Objective 3; from `sos_delivery_report` (key `sos_delivery`).
  final SosDeliveryReport delivery;

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
      delivery: switch (json['sos_delivery']) {
        final Map<Object?, Object?> d => SosDeliveryReport.fromJson(
          d.cast<String, Object?>(),
        ),
        _ => const SosDeliveryReport(),
      },
    );
  }
}
