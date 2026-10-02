import 'package:flutter/foundation.dart';

import 'assignment.dart';
import 'enums.dart';

/// What a responder's completion report says happened (F6), without
/// anything personal: the part an NDRRMC report counts.
@immutable
class DamageRecord {
  const DamageRecord({
    required this.incidentId,
    required this.outcome,
    this.personsAssisted = 0,
    this.housesDamaged = 0,
    this.injured = 0,
    this.missing = 0,
    this.affectedFamilies = 0,
  });

  final String incidentId;
  final RescueOutcome outcome;
  final int personsAssisted;
  final int housesDamaged;
  final int injured;
  final int missing;
  final int affectedFamilies;
}

/// Incidents in one barangay during a report's period.
@immutable
class BarangayCount {
  const BarangayCount({
    required this.barangay,
    required this.district,
    required this.count,
  });

  final String barangay;
  final String district;
  final int count;

  String get place => '$barangay, $district';
}

/// The figures an NDRRMC report is drafted from (`report_source`), for
/// incidents received in [from, to). Counts only: no names, phone numbers,
/// addresses, or coordinates ever leave the records (RA 10173).
@immutable
class ReportSource {
  const ReportSource({
    required this.from,
    required this.to,
    this.incidents = 0,
    this.sos = 0,
    this.clusters = 0,
    this.resolved = 0,
    this.open = 0,
    this.falseReports = 0,
    this.vulnerableIncidents = 0,
    this.byType = const {},
    this.byBarangay = const [],
    this.completionReports = 0,
    this.resolvedWithoutReport = 0,
    this.personsAssisted = 0,
    this.injured = 0,
    this.missing = 0,
    this.affectedFamilies = 0,
    this.housesDamaged = 0,
    this.outcomes = const {},
    this.dispatches = 0,
    this.unitsDeployed = 0,
    this.medianDispatchS,
    this.medianResponseS,
    this.alertsIssued = 0,
    this.alertsSimulated = 0,
    this.maxSignal,
    this.maxRainfall,
    this.maxSurgeM,
    this.weatherSimulated = false,
  });

  final DateTime from;
  final DateTime to;

  /// Every incident received in the period: [resolved], [falseReports],
  /// and [open] add up to this.
  final int incidents;
  final int sos;
  final int clusters;

  /// Resolved as real emergencies.
  final int resolved;
  final int open;
  final int falseReports;

  /// Incidents from households on the Vulnerable Resident Priority List.
  final int vulnerableIncidents;

  /// By incident type; the null key holds incidents with no type yet.
  final Map<IncidentType?, int> byType;

  /// Most incidents first.
  final List<BarangayCount> byBarangay;

  final int completionReports;

  /// Resolved incidents with no completion report: the damage figures
  /// are incomplete while this is above zero.
  final int resolvedWithoutReport;
  final int personsAssisted;
  final int injured;
  final int missing;
  final int affectedFamilies;
  final int housesDamaged;
  final Map<RescueOutcome, int> outcomes;

  final int dispatches;
  final int unitsDeployed;

  /// Seconds from received to the first assignment, and to on scene.
  final double? medianDispatchS;
  final double? medianResponseS;

  final int alertsIssued;
  final int alertsSimulated;

  /// The highest PAGASA readings recorded in the period; null when no
  /// reading was recorded.
  final int? maxSignal;
  final double? maxRainfall;
  final double? maxSurgeM;

  /// True when any of those readings came from a simulated feed.
  final bool weatherSimulated;

  bool get isEmpty => incidents == 0;

  factory ReportSource.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ReportSource(
      from: timeFromJson(json['from']),
      to: timeFromJson(json['to']),
      incidents: n('incidents'),
      sos: n('sos'),
      clusters: n('clusters'),
      resolved: n('resolved'),
      open: n('open'),
      falseReports: n('false_reports'),
      vulnerableIncidents: n('vulnerable_incidents'),
      byType: {
        for (final row
            in (json['by_type'] as List? ?? const [])
                .cast<Map<String, Object?>>())
          enumFromJsonOrNull(IncidentType.values, row['type']):
              (row['count']! as num).toInt(),
      },
      byBarangay: [
        for (final row
            in (json['by_barangay'] as List? ?? const [])
                .cast<Map<String, Object?>>())
          BarangayCount(
            barangay: row['barangay']! as String,
            district: row['district']! as String,
            count: (row['count']! as num).toInt(),
          ),
      ],
      completionReports: n('completion_reports'),
      resolvedWithoutReport: n('resolved_without_report'),
      personsAssisted: n('persons_assisted'),
      injured: n('injured'),
      missing: n('missing'),
      affectedFamilies: n('affected_families'),
      housesDamaged: n('houses_damaged'),
      outcomes: {
        for (final e
            in (json['outcomes'] as Map<String, Object?>? ?? const {}).entries)
          enumFromJson(RescueOutcome.values, e.key): (e.value! as num).toInt(),
      },
      dispatches: n('dispatches'),
      unitsDeployed: n('units_deployed'),
      medianDispatchS: (json['median_dispatch_s'] as num?)?.toDouble(),
      medianResponseS: (json['median_response_s'] as num?)?.toDouble(),
      alertsIssued: n('alerts_issued'),
      alertsSimulated: n('alerts_simulated'),
      maxSignal: (json['max_signal'] as num?)?.toInt(),
      maxRainfall: (json['max_rainfall'] as num?)?.toDouble(),
      maxSurgeM: (json['max_surge_m'] as num?)?.toDouble(),
      weatherSimulated: json['weather_simulated'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'from': from.toUtc().toIso8601String(),
    'to': to.toUtc().toIso8601String(),
    'incidents': incidents,
    'sos': sos,
    'clusters': clusters,
    'resolved': resolved,
    'open': open,
    'false_reports': falseReports,
    'vulnerable_incidents': vulnerableIncidents,
    'by_type': [
      for (final e in byType.entries) {'type': e.key?.name, 'count': e.value},
    ],
    'by_barangay': [
      for (final b in byBarangay)
        {'barangay': b.barangay, 'district': b.district, 'count': b.count},
    ],
    'completion_reports': completionReports,
    'resolved_without_report': resolvedWithoutReport,
    'persons_assisted': personsAssisted,
    'injured': injured,
    'missing': missing,
    'affected_families': affectedFamilies,
    'houses_damaged': housesDamaged,
    'outcomes': {for (final e in outcomes.entries) e.key.name: e.value},
    'dispatches': dispatches,
    'units_deployed': unitsDeployed,
    'median_dispatch_s': medianDispatchS,
    'median_response_s': medianResponseS,
    'alerts_issued': alertsIssued,
    'alerts_simulated': alertsSimulated,
    'max_signal': maxSignal,
    'max_rainfall': maxRainfall,
    'max_surge_m': maxSurgeM,
    'weather_simulated': weatherSimulated,
  };
}

/// One section of a report: a heading and the text under it.
@immutable
class ReportSection {
  const ReportSection({
    required this.key,
    required this.title,
    required this.body,
  });

  /// Stable name of the section (see `ReportSections`).
  final String key;
  final String title;
  final String body;

  ReportSection withBody(String body) =>
      ReportSection(key: key, title: title, body: body);

  factory ReportSection.fromJson(Map<String, Object?> json) => ReportSection(
    key: json['key']! as String,
    title: json['title']! as String,
    body: json['body'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {'key': key, 'title': title, 'body': body};
}

/// A draft can still be edited; a final report cannot.
enum ReportStatus { draft, finalized }

/// How the text of a report was first written.
enum ReportMethod {
  /// Put together from the figures with fixed wording, no language model.
  assembled,

  /// Drafted by the RAG engine (plan 10.6), once it exists.
  rag,
}

/// An NDRRMC report: a period, the figures it was drafted from (kept as
/// they were at that moment), and the text an administrator reviewed
/// (A5, A6; Objective 4).
@immutable
class NdrrmcReport {
  const NdrrmcReport({
    required this.id,
    required this.title,
    required this.status,
    required this.source,
    required this.sections,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.method = ReportMethod.assembled,
    this.generationMs,
    this.finalizedAt,
    this.finalizedByName,
  });

  final String id;
  final String title;
  final ReportStatus status;
  final ReportSource source;
  final List<ReportSection> sections;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ReportMethod method;

  /// How long collecting the records and drafting took, for the Objective
  /// 4 time comparison.
  final int? generationMs;
  final DateTime? finalizedAt;
  final String? finalizedByName;

  DateTime get periodStart => source.from;
  DateTime get periodEnd => source.to;
  bool get isFinal => status == ReportStatus.finalized;

  factory NdrrmcReport.fromJson(Map<String, Object?> json) => NdrrmcReport(
    id: json['report_id']! as String,
    title: json['title']! as String,
    status: json['status'] == 'final'
        ? ReportStatus.finalized
        : ReportStatus.draft,
    source: ReportSource.fromJson(json['source']! as Map<String, Object?>),
    sections: [
      for (final s in (json['sections']! as List).cast<Map<String, Object?>>())
        ReportSection.fromJson(s),
    ],
    createdByName: json['created_by_name']! as String,
    createdAt: timeFromJson(json['created_at']),
    updatedAt: timeFromJson(json['updated_at']),
    method: enumFromJson(ReportMethod.values, json['method'] ?? 'assembled'),
    generationMs: (json['generation_ms'] as num?)?.toInt(),
    finalizedAt: timeFromJsonOrNull(json['finalized_at']),
    finalizedByName: json['finalized_by_name'] as String?,
  );
}
