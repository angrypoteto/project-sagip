import 'package:intl/intl.dart';

import '../models/alerts.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/ndrrmc.dart';
import '../models/records.dart';
import 'analytics.dart';

// NDRRMC report drafts (A6, Objective 4): the figures for a period, and a
// first draft put together from them with fixed wording. No language model
// is involved; the RAG engine (plan 10.6) will later write the text from the
// same figures.

/// The sections of a report, in order.
///
/// A provisional outline: MDRRMD has not sent the NDRRMC template yet
/// (thesis Table 3.1 item 5). When it arrives, change the keys and titles
/// here and the wording in [draftReportSections].
abstract final class ReportSections {
  static const overview = 'overview';
  static const incidents = 'incidents';
  static const population = 'population';
  static const damage = 'damage';
  static const response = 'response';
  static const remarks = 'remarks';

  static const titles = {
    overview: 'Situation overview',
    incidents: 'Incidents reported',
    population: 'Affected population and casualties',
    damage: 'Damage to houses',
    response: 'Response actions',
    remarks: 'Remarks and recommendations',
  };

  /// What the database accepts (`save_ndrrmc_report`).
  static const maxSections = 12;
  static const maxTitle = 160;
  static const maxSectionTitle = 120;
  static const maxBody = 6000;
}

/// The figures for incidents received in [from, to), from records in
/// memory (the mock backend). The same definitions as `report_source` in
/// the database.
ReportSource buildReportSource({
  required Iterable<Incident> incidents,
  required Map<String, DamageRecord> completions,
  required Iterable<PublicAlert> alerts,
  required Iterable<WeatherStatus> readings,
  required DateTime from,
  required DateTime to,
}) {
  bool within(DateTime t) => !t.isBefore(from) && t.isBefore(to);
  final rows = [
    for (final i in incidents)
      if (within(i.receivedAt) && !i.isSimulated) i,
  ];
  final filed = [for (final i in rows) ?completions[i.id]];
  bool real(Incident i) =>
      i.status == IncidentStatus.resolved && !i.falseReport;

  DateTime? first(Incident i, IncidentEventKind kind) {
    DateTime? at;
    for (final e in i.events) {
      if (e.kind == kind && (at == null || e.at.isBefore(at))) at = e.at;
    }
    return at;
  }

  double? secondsTo(Incident i, IncidentEventKind kind) {
    final at = first(i, kind);
    return at == null
        ? null
        : at.difference(i.receivedAt).inMilliseconds / 1000;
  }

  final types = <IncidentType?, int>{};
  final places = <String, BarangayCount>{};
  for (final i in rows) {
    types[i.type] = (types[i.type] ?? 0) + 1;
    places[i.barangay] = BarangayCount(
      barangay: i.barangay,
      district: i.district,
      count: (places[i.barangay]?.count ?? 0) + 1,
    );
  }
  final outcomes = <RescueOutcome, int>{};
  for (final c in filed) {
    outcomes[c.outcome] = (outcomes[c.outcome] ?? 0) + 1;
  }
  final issued = [
    for (final a in alerts)
      if (within(a.issuedAt)) a,
  ];
  final weather = [
    for (final w in readings)
      if (within(w.issuedAt)) w,
  ];
  T? highest<T extends num>(Iterable<T?> values) {
    T? top;
    for (final v in values) {
      if (v != null && (top == null || v > top)) top = v;
    }
    return top;
  }

  int sum(int Function(DamageRecord c) of) =>
      filed.fold(0, (total, c) => total + of(c));

  return ReportSource(
    from: from,
    to: to,
    incidents: rows.length,
    sos: rows.where((i) => i.origin == IncidentOrigin.sos).length,
    clusters: rows.where((i) => i.origin == IncidentOrigin.crowdCluster).length,
    resolved: rows.where(real).length,
    open: rows.where((i) => i.status != IncidentStatus.resolved).length,
    falseReports: rows.where((i) => i.falseReport).length,
    vulnerableIncidents: rows.where((i) => i.vulnerable.isNotEmpty).length,
    byType: {
      for (final e
          in types.entries.toList()..sort((a, b) {
            final byCount = b.value.compareTo(a.value);
            if (byCount != 0) return byCount;
            // Untyped last, as `nulls last` in the database.
            if (a.key == null || b.key == null) return a.key == null ? 1 : -1;
            return a.key!.name.compareTo(b.key!.name);
          }))
        e.key: e.value,
    },
    byBarangay: places.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.barangay.compareTo(b.barangay);
      }),
    completionReports: filed.length,
    resolvedWithoutReport: rows
        .where((i) => real(i) && !completions.containsKey(i.id))
        .length,
    personsAssisted: sum((c) => c.personsAssisted),
    injured: sum((c) => c.injured),
    missing: sum((c) => c.missing),
    affectedFamilies: sum((c) => c.affectedFamilies),
    housesDamaged: sum((c) => c.housesDamaged),
    outcomes: outcomes,
    // The mock keeps one unit per incident, so a reassignment is not a
    // second dispatch here as it is in the database.
    dispatches: rows.where((i) => i.assignedUnitId != null).length,
    unitsDeployed: {
      for (final i in rows)
        if (i.assignedUnitId != null) i.assignedUnitId,
    }.length,
    medianDispatchS: median(
      rows.map((i) => secondsTo(i, IncidentEventKind.assigned)),
    ),
    medianResponseS: median(
      rows.map((i) => secondsTo(i, IncidentEventKind.onScene)),
    ),
    alertsIssued: issued.length,
    alertsSimulated: issued.where((a) => a.isSimulated).length,
    maxSignal: highest(weather.map((w) => w.signalLevel)),
    maxRainfall: highest(weather.map((w) => w.rainfallMmPerHour)),
    maxSurgeM: highest(weather.map((w) => w.stormSurgeMeters)),
    weatherSimulated: weather.any((w) => w.isSimulated),
  );
}

// Reports are written in English; en_US needs no locale data loaded.
const _locale = 'en_US';

/// "1 incident", "3 incidents".
String _n(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : many ?? '${one}s'}';

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "4 min 26 s", "5 min", "58 s".
String _duration(double seconds) {
  final s = seconds.round();
  if (s < 60) return '$s s';
  return s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60} min ${s % 60} s';
}

String _outcome(RescueOutcome o) => switch (o) {
  RescueOutcome.rescued => 'rescued',
  RescueOutcome.treated => 'treated on scene',
  RescueOutcome.transported => 'transported',
  RescueOutcome.noOneFound => 'no one found',
  RescueOutcome.falseReport => 'false report',
};

/// The title a new report starts with: "Incident report, Sep 25 to Oct 2,
/// 2026" (Manila dates).
String defaultReportTitle(DateTime from, DateTime to) {
  final a = manilaDate(from);
  // A period that ends at midnight covers the day before.
  final b = manilaDate(to.subtract(const Duration(seconds: 1)));
  final day = DateFormat.MMMd(_locale);
  final full = DateFormat.yMMMd(_locale);
  return a == b
      ? 'Incident report, ${full.format(a)}'
      : a.year == b.year
      ? 'Incident report, ${day.format(a)} to ${full.format(b)}'
      : 'Incident report, ${full.format(a)} to ${full.format(b)}';
}

/// A first draft of every section, written from [s] alone. Each sentence
/// states a figure; nothing is inferred. Remarks are left for the
/// administrator.
List<ReportSection> draftReportSections(ReportSource s) {
  final when = DateFormat.yMMMd(_locale).add_jm();
  String at(DateTime t) => when
      .format(t.toUtc().add(const Duration(hours: 8)))
      .replaceAll('\u202F', ' ');

  final overview = StringBuffer(
    'From ${at(s.from)} to ${at(s.to)} (Manila time), the Manila Disaster '
    'Risk Reduction and Management Department recorded '
    '${_n(s.incidents, 'incident')} through Project S.A.G.I.P.: '
    '${_n(s.sos, 'SOS request')} and '
    '${_n(s.clusters, 'confirmed cluster')} of crowd reports.',
  );
  if (s.maxSignal == null && s.maxRainfall == null) {
    overview.write(' No PAGASA reading was recorded in the period.');
  } else {
    overview.write(
      (s.maxSignal ?? 0) > 0
          ? ' The highest tropical cyclone wind signal recorded was '
                'No. ${s.maxSignal}.'
          : ' No tropical cyclone wind signal was recorded.',
    );
    if (s.maxRainfall != null) {
      overview.write(
        ' Peak rainfall recorded was ${_plain(s.maxRainfall!)} mm per hour.',
      );
    }
    if (s.maxSurgeM != null) {
      overview.write(
        ' The highest storm surge forecast was ${_plain(s.maxSurgeM!)} m.',
      );
    }
    if (s.weatherSimulated) {
      overview.write(' These readings include data from a simulated feed.');
    }
  }
  overview.write(
    ' ${_n(s.alertsIssued, 'public alert')} '
    '${s.alertsIssued == 1 ? 'was' : 'were'} issued to residents'
    '${s.alertsSimulated > 0 ? ', ${s.alertsSimulated} of them simulated' : ''}.',
  );

  final incidents = StringBuffer();
  if (s.isEmpty) {
    incidents.write('No incidents were recorded in the period.');
  } else {
    incidents.write(
      'By type: ${[for (final e in s.byType.entries) '${e.key?.name ?? 'not yet classified'} ${e.value}'].join(', ')}.',
    );
    incidents.write(
      ' By barangay: ${[for (final b in s.byBarangay) '${b.place} (${b.count})'].join('; ')}.',
    );
    incidents.write(
      ' ${_n(s.resolved, 'incident')} '
      '${s.resolved == 1 ? 'was' : 'were'} resolved, '
      '${s.open} ${s.open == 1 ? 'remains' : 'remain'} open, and '
      '${_n(s.falseReports, 'report')} '
      '${s.falseReports == 1 ? 'was' : 'were'} found to be false.',
    );
    incidents.write(
      ' ${_n(s.vulnerableIncidents, 'incident')} involved a household on '
      'the Vulnerable Resident Priority List.',
    );
  }

  final population = StringBuffer(
    'Responders filed ${_n(s.completionReports, 'completion report')}.',
  );
  if (s.completionReports > 0) {
    population.write(
      ' Persons assisted: ${s.personsAssisted}. Injured: ${s.injured}. '
      'Missing: ${s.missing}. Affected families: ${s.affectedFamilies}.',
    );
    population.write(
      ' Outcomes: ${[for (final o in RescueOutcome.values)
        if (s.outcomes[o] case final count?) '${_outcome(o)} $count'].join(', ')}.',
    );
  }
  if (s.resolvedWithoutReport > 0) {
    population.write(
      ' ${_n(s.resolvedWithoutReport, 'resolved incident')} '
      '${s.resolvedWithoutReport == 1 ? 'has' : 'have'} no completion '
      'report, so these figures are incomplete.',
    );
  }

  final damage = s.completionReports == 0
      ? 'No damage figures were reported in the period.'
      : 'Houses reported damaged: ${s.housesDamaged}, as recorded by '
            'responders in their completion reports.';

  final response = StringBuffer(
    '${_n(s.dispatches, 'dispatch', 'dispatches')} '
    '${s.dispatches == 1 ? 'was' : 'were'} made, using '
    '${_n(s.unitsDeployed, 'response unit')}.',
  );
  if (s.medianDispatchS != null) {
    response.write(
      ' Median time from a report being received to a unit being assigned: '
      '${_duration(s.medianDispatchS!)}.',
    );
  }
  if (s.medianResponseS != null) {
    response.write(
      ' Median time from a report being received to a unit arriving on '
      'scene: ${_duration(s.medianResponseS!)}.',
    );
  }

  ReportSection section(String key, Object body) => ReportSection(
    key: key,
    title: ReportSections.titles[key]!,
    body: '$body',
  );
  return [
    section(ReportSections.overview, overview),
    section(ReportSections.incidents, incidents),
    section(ReportSections.population, population),
    section(ReportSections.damage, damage),
    section(ReportSections.response, response),
    section(ReportSections.remarks, ''),
  ];
}

/// What an administrator should look at before calling a report final.
enum ReportCheck {
  /// There is something to report.
  hasIncidents,

  /// No incident of the period is still open.
  noneOpen,

  /// Every resolved incident has its completion report.
  allReportsFiled,

  /// None of the figures come from simulated alerts or readings.
  noSimulatedData,

  /// Every section has text, including the remarks.
  noEmptySection,
}

/// The checks that pass for [source] and [sections].
Set<ReportCheck> passedReportChecks(
  ReportSource source,
  List<ReportSection> sections,
) => {
  if (!source.isEmpty) ReportCheck.hasIncidents,
  if (source.open == 0) ReportCheck.noneOpen,
  if (source.resolvedWithoutReport == 0) ReportCheck.allReportsFiled,
  if (source.alertsSimulated == 0 && !source.weatherSimulated)
    ReportCheck.noSimulatedData,
  if (sections.every((s) => s.body.trim().isNotEmpty))
    ReportCheck.noEmptySection,
};

/// Whether the database would accept this text (`save_ndrrmc_report`).
bool reportTextAccepted(String title, List<ReportSection> sections) =>
    title.trim().isNotEmpty &&
    title.trim().length <= ReportSections.maxTitle &&
    sections.isNotEmpty &&
    sections.length <= ReportSections.maxSections &&
    sections.every(
      (s) =>
          s.key.isNotEmpty &&
          s.title.trim().isNotEmpty &&
          s.title.length <= ReportSections.maxSectionTitle &&
          s.body.length <= ReportSections.maxBody,
    );
