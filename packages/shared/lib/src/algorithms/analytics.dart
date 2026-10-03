import '../models/analytics.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';

/// A4 analytics from incidents in memory (the mock backend), with the same
/// definitions as `public.analytics_report` in the database: incidents
/// received in [from, to), times from each incident's timeline.
AnalyticsReport buildAnalytics({
  required Iterable<Incident> incidents,
  required Map<String, ResponseUnit> units,
  required DateTime from,
  required DateTime to,
  Iterable<RoutingRun> runs = const [],
}) {
  final rows = [
    for (final i in incidents)
      if (!i.receivedAt.isBefore(from) && i.receivedAt.isBefore(to)) _Row(i),
  ];

  List<AnalyticsGroup> groups(
    String? Function(_Row r) keyOf,
    String Function(_Row r) labelOf, {
    int? limit,
    bool travel = false,
  }) {
    final byKey = <String, List<_Row>>{};
    for (final r in rows) {
      final k = keyOf(r);
      if (k != null) byKey.putIfAbsent(k, () => []).add(r);
    }
    final list =
        [
          for (final e in byKey.entries)
            AnalyticsGroup(
              key: e.key,
              label: labelOf(e.value.first),
              count: e.value.length,
              avgDispatchS: travel
                  ? null
                  : _avg(e.value.map((r) => r.dispatchS)),
              avgResponseS: _avg(e.value.map((r) => r.responseS)),
              avgTravelS: travel ? _avg(e.value.map((r) => r.travelS)) : null,
            ),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
    return limit == null ? list : list.take(limit).toList();
  }

  final days = <DateTime, List<_Row>>{};
  for (final r in rows) {
    days.putIfAbsent(manilaDate(r.i.receivedAt), () => []).add(r);
  }
  final sortedDays = days.keys.toList()..sort();

  final runsIn = [
    for (final r in runs)
      if (r.at != null && !r.at!.isBefore(from) && r.at!.isBefore(to)) r,
  ];

  return AnalyticsReport(
    from: from,
    to: to,
    incidents: rows.length,
    resolved: rows.where((r) => r.i.status == IncidentStatus.resolved).length,
    falseReports: rows.where((r) => r.i.falseReport).length,
    sos: rows.where((r) => r.i.origin == IncidentOrigin.sos).length,
    clusters: rows
        .where((r) => r.i.origin == IncidentOrigin.crowdCluster)
        .length,
    avgDispatchS: _avg(rows.map((r) => r.dispatchS)),
    medianDispatchS: median(rows.map((r) => r.dispatchS)),
    avgVerifyS: _avg(rows.map((r) => r.verifyS)),
    avgResponseS: _avg(rows.map((r) => r.responseS)),
    medianResponseS: median(rows.map((r) => r.responseS)),
    sosByChannel: {
      for (final c in ReportChannel.values)
        if (rows.any(
          (r) => r.i.origin == IncidentOrigin.sos && r.i.channel == c,
        ))
          c: rows
              .where(
                (r) => r.i.origin == IncidentOrigin.sos && r.i.channel == c,
              )
              .length,
    },
    byType: groups(
      (r) => r.i.type?.name ?? 'unknown',
      (r) => r.i.type?.name ?? 'unknown',
    ),
    byBarangay: groups(
      (r) => r.i.barangay,
      (r) => '${r.i.barangay}, ${r.i.district}',
      limit: 10,
    ),
    byUnit: groups(
      (r) => r.i.assignedUnitId,
      (r) => units[r.i.assignedUnitId]?.callSign ?? r.i.assignedUnitId!,
      travel: true,
    ),
    daily: [
      for (final d in sortedDays)
        AnalyticsDay(
          day: d,
          count: days[d]!.length,
          avgResponseS: _avg(days[d]!.map((r) => r.responseS)),
        ),
    ],
    routing: [
      for (final kind in RoutingRunKind.values)
        if (runsIn.where((r) => r.kind == kind).toList() case final ofKind
            when ofKind.isNotEmpty)
          RoutingStats(
            kind: kind,
            runs: ofKind.length,
            avgMs: _avg(ofKind.map((r) => r.computeMs))!,
            p95Ms: percentile(ofKind.map((r) => r.computeMs), 0.95)!,
          ),
    ],
    delivery: sosDelivery([for (final r in rows) r.i]),
  );
}

/// The Objective 3 figures from SOS already in the period, with the same
/// definitions as `sos_delivery_report`. The mock has no relay log.
SosDeliveryReport sosDelivery(Iterable<Incident> incidents) {
  final byChannel = <ReportChannel, List<double>>{};
  for (final i in incidents) {
    if (i.origin != IncidentOrigin.sos) continue;
    final s = i.receivedAt.difference(i.capturedAt).inMicroseconds / 1e6;
    byChannel.putIfAbsent(i.channel, () => []).add(s < 0 ? 0 : s);
  }
  return SosDeliveryReport(
    channels: [
      for (final c in ReportChannel.values)
        if (byChannel[c] case final delays?)
          SosDelivery(
            channel: c,
            count: delays.length,
            medianS: median(delays),
            p95S: percentile(delays, 0.95),
            maxS: delays.reduce((a, b) => a > b ? a : b),
            within60: delays.where((d) => d <= 60).length,
            within300: delays.where((d) => d <= 300).length,
            within900: delays.where((d) => d <= 900).length,
          ),
    ],
  );
}

class _Row {
  _Row(this.i)
    : verifiedAt = _first(i, IncidentEventKind.verified),
      assignedAt = _first(i, IncidentEventKind.assigned),
      onSceneAt = _first(i, IncidentEventKind.onScene);

  final Incident i;
  final DateTime? verifiedAt;
  final DateTime? assignedAt;
  final DateTime? onSceneAt;

  double? get dispatchS => _seconds(i.receivedAt, assignedAt);
  double? get verifyS => _seconds(i.receivedAt, verifiedAt);
  double? get responseS => _seconds(i.receivedAt, onSceneAt);
  double? get travelS =>
      assignedAt == null ? null : _seconds(assignedAt!, onSceneAt);

  static DateTime? _first(Incident i, IncidentEventKind kind) {
    DateTime? first;
    for (final e in i.events) {
      if (e.kind == kind && (first == null || e.at.isBefore(first))) {
        first = e.at;
      }
    }
    return first;
  }

  static double? _seconds(DateTime from, DateTime? to) =>
      to == null ? null : to.difference(from).inMicroseconds / 1e6;
}

double? _avg(Iterable<double?> values) {
  final v = values.whereType<double>().toList();
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

/// The median like Postgres `percentile_cont(0.5)`: nulls ignored, the two
/// middle values averaged.
double? median(Iterable<double?> values) => percentile(values, 0.5);

/// Postgres `percentile_cont`: linear interpolation between the closest
/// ranks.
double? percentile(Iterable<double?> values, double fraction) {
  final v = values.whereType<double>().toList()..sort();
  if (v.isEmpty) return null;
  final pos = fraction * (v.length - 1);
  final lo = pos.floor();
  final hi = pos.ceil();
  return v[lo] + (v[hi] - v[lo]) * (pos - lo);
}

/// The Manila calendar date of [t] (UTC+8, no daylight saving), as the
/// database groups days.
DateTime manilaDate(DateTime t) {
  final m = t.toUtc().add(const Duration(hours: 8));
  return DateTime(m.year, m.month, m.day);
}

/// The report as CSV for A4's export: one section per table.
String analyticsCsv(AnalyticsReport r) {
  String cell(Object? v) {
    final s = switch (v) {
      null => '',
      final double d => d.toStringAsFixed(1),
      _ => '$v',
    };
    return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final out = StringBuffer();
  void row(List<Object?> cells) => out.writeln(cells.map(cell).join(','));

  row(['metric', 'value']);
  row(['from', r.from.toUtc().toIso8601String()]);
  row(['to', r.to.toUtc().toIso8601String()]);
  row(['incidents', r.incidents]);
  row(['resolved', r.resolved]);
  row(['false_reports', r.falseReports]);
  row(['sos', r.sos]);
  row(['clusters', r.clusters]);
  row(['avg_dispatch_s', r.avgDispatchS]);
  row(['median_dispatch_s', r.medianDispatchS]);
  row(['avg_verify_s', r.avgVerifyS]);
  row(['avg_response_s', r.avgResponseS]);
  row(['median_response_s', r.medianResponseS]);
  for (final e in r.sosByChannel.entries) {
    row(['sos_${e.key.name}', e.value]);
  }
  for (final (name, groups) in [
    ('type', r.byType),
    ('barangay', r.byBarangay),
    ('unit', r.byUnit),
  ]) {
    out.writeln();
    row([
      name,
      'incidents',
      'avg_dispatch_s',
      'avg_response_s',
      'avg_travel_s',
    ]);
    for (final g in groups) {
      row([g.label, g.count, g.avgDispatchS, g.avgResponseS, g.avgTravelS]);
    }
  }
  out.writeln();
  row(['day', 'incidents', 'avg_response_s']);
  for (final d in r.daily) {
    row([dateOnly(d.day), d.count, d.avgResponseS]);
  }
  out.writeln();
  row(['dijkstra', 'runs', 'avg_ms', 'p95_ms']);
  for (final s in r.routing) {
    row([s.kind.name, s.runs, s.avgMs, s.p95Ms]);
  }
  out.writeln();
  row([
    'sos_first_channel',
    'delivered',
    'median_delay_s',
    'p95_delay_s',
    'max_delay_s',
    'within_60s',
    'within_300s',
    'within_900s',
  ]);
  for (final c in r.delivery.channels) {
    row([
      c.channel.name,
      c.count,
      c.medianS,
      c.p95S,
      c.maxS,
      c.within60,
      c.within300,
      c.within900,
    ]);
  }
  row(['relay_uploads', r.delivery.relayUploads]);
  row(['relayed_sos', r.delivery.relayedSos]);
  row(['relay_max_hops', r.delivery.relayMaxHops]);
  return out.toString();
}
