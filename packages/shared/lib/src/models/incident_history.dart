import 'package:flutter/foundation.dart';

import 'assignment.dart';
import 'enums.dart';
import 'incident.dart';
import 'road_route.dart';

/// How a closed incident ended.
enum IncidentEnding {
  /// The unit finished, or a dispatcher closed it.
  resolved,

  /// Marked a false report.
  falseReport,

  /// The resident who sent the SOS cancelled it.
  cancelled,
}

/// A closed incident on the history page (Joshua, 2026-10-16), with what its
/// unit reported when it finished, if it filed a report.
@immutable
class ClosedIncident {
  const ClosedIncident({
    required this.incident,
    this.outcome,
    this.personsAssisted,
    this.housesDamaged,
    this.injured,
    this.missing,
    this.affectedFamilies,
  });

  final Incident incident;
  final RescueOutcome? outcome;
  final int? personsAssisted;
  final int? housesDamaged;
  final int? injured;
  final int? missing;
  final int? affectedFamilies;

  bool get hasReport => outcome != null;

  IncidentEnding get ending => incident.falseReport
      ? IncidentEnding.falseReport
      : incident.cancelled
      ? IncidentEnding.cancelled
      : IncidentEnding.resolved;

  /// When a unit reached the scene, if one did.
  DateTime? get onSceneAt {
    for (final e in incident.events) {
      if (e.kind == IncidentEventKind.onScene) return e.at;
    }
    return null;
  }

  /// From the report reaching MDRRMD to a unit on scene.
  Duration? get responseTime {
    final at = onSceneAt;
    if (at == null) return null;
    final d = at.difference(incident.receivedAt);
    return d.isNegative ? null : d;
  }

  ClosedIncident withReport(Map<String, dynamic>? row) => row == null
      ? this
      : ClosedIncident(
          incident: incident,
          outcome: RescueOutcome.values.asNameMap()[row['outcome']],
          personsAssisted: row['persons_assisted'] as int?,
          housesDamaged: row['houses_damaged'] as int?,
          injured: row['injured'] as int?,
          missing: row['missing'] as int?,
          affectedFamilies: row['affected_families'] as int?,
        );
}

/// The incidents that match the history page's filters: [type], [ending],
/// and [query] (part of the incident ID, barangay, or district, any case).
List<ClosedIncident> filterHistory(
  List<ClosedIncident> all, {
  IncidentType? type,
  IncidentEnding? ending,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final c in all)
      if ((type == null || c.incident.type == type) &&
          (ending == null || c.ending == ending) &&
          (q.isEmpty ||
              c.incident.id.toLowerCase().contains(q) ||
              c.incident.barangay.toLowerCase().contains(q) ||
              c.incident.district.toLowerCase().contains(q)))
        c,
  ];
}

/// The history as CSV, one row per incident. Only what a report needs:
/// no resident name, number, address, exact position, or notes (RA 10173),
/// since the file leaves the system. [unitCallSign] names the unit.
String historyCsv(
  List<ClosedIncident> rows, {
  required String? Function(String unitId) unitCallSign,
}) {
  String cell(Object? v) {
    final s = switch (v) {
      null => '',
      final DateTime t => t.toUtc().toIso8601String(),
      _ => '$v',
    };
    return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final out = StringBuffer();
  void row(List<Object?> cells) => out.writeln(cells.map(cell).join(','));
  row([
    'incident_id',
    'origin',
    'type',
    'type_confirmed',
    'barangay',
    'district',
    'received_at',
    'verified_by',
    'unit',
    'on_scene_at',
    'closed_at',
    'response_min',
    'ending',
    'outcome',
    'persons_assisted',
    'houses_damaged',
    'injured',
    'missing',
    'affected_families',
    'simulated',
  ]);
  for (final c in rows) {
    final i = c.incident;
    row([
      i.id,
      i.origin.name,
      i.type?.name,
      i.typeConfirmed,
      i.barangay,
      i.district,
      i.receivedAt,
      i.verificationMethod?.name,
      i.assignedUnitId == null ? null : unitCallSign(i.assignedUnitId!),
      c.onSceneAt,
      i.resolvedAt,
      c.responseTime == null
          ? null
          : (c.responseTime!.inSeconds / 60).toStringAsFixed(1),
      c.ending.name,
      c.outcome?.name,
      c.personsAssisted,
      c.housesDamaged,
      c.injured,
      c.missing,
      c.affectedFamilies,
      i.isSimulated,
    ]);
  }
  return out.toString();
}

/// The file name for a CSV of [from] to [to].
String historyCsvName(DateTime from, DateTime to) =>
    'sagip-incident-history-${dateOnly(from)}-to-${dateOnly(to)}.csv';
