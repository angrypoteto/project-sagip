import 'package:flutter/foundation.dart';

import 'assignment.dart';
import 'enums.dart';

/// A crew's completion report as MDRRMD sees it on the board (2026-11-11).
///
/// MDRRMD's way: the responders send their report, and MDRRMD validates it
/// (Joshua: "they will just throw it to the mdrrmd and then the mdrrmd will
/// just validate it"). Until a dispatcher or admin validates it, the
/// incident stays open and the report does not count in the MDRRMD report.
@immutable
class CrewReport {
  const CrewReport({
    required this.id,
    required this.unitId,
    required this.capturedAt,
    required this.outcome,
    this.callSign,
    this.personsAssisted = 0,
    this.timeOnSceneSeconds = 0,
    this.injured = 0,
    this.missing = 0,
    this.affectedFamilies = 0,
    this.housesDamaged = 0,
    this.notes,
    this.validatedAt,
    this.validatedByName,
    this.corrected = false,
  });

  final String id;
  final String unitId;
  final String? callSign;

  /// When the crew filed it (the phone's time).
  final DateTime capturedAt;
  final RescueOutcome outcome;
  final int personsAssisted;
  final int timeOnSceneSeconds;
  final int injured;
  final int missing;
  final int affectedFamilies;
  final int housesDamaged;
  final String? notes;

  /// Null while the report waits for MDRRMD.
  final DateTime? validatedAt;
  final String? validatedByName;

  /// MDRRMD changed a figure when validating.
  final bool corrected;

  bool get validated => validatedAt != null;

  String get unitLabel => callSign ?? unitId;

  CrewReport validate({
    required DateTime at,
    required String byName,
    CrewReportCorrection? correction,
  }) {
    final c = correction ?? const CrewReportCorrection();
    final next = CrewReport(
      id: id,
      unitId: unitId,
      callSign: callSign,
      capturedAt: capturedAt,
      outcome: c.outcome ?? outcome,
      personsAssisted: c.personsAssisted ?? personsAssisted,
      timeOnSceneSeconds: timeOnSceneSeconds,
      injured: c.injured ?? injured,
      missing: c.missing ?? missing,
      affectedFamilies: c.affectedFamilies ?? affectedFamilies,
      housesDamaged: c.housesDamaged ?? housesDamaged,
      notes: notes,
      validatedAt: at,
      validatedByName: byName,
    );
    return next._withCorrected(!listEquals(next._figures, _figures));
  }

  List<Object> get _figures => [
    outcome,
    personsAssisted,
    injured,
    missing,
    affectedFamilies,
    housesDamaged,
  ];

  CrewReport _withCorrected(bool value) => CrewReport(
    id: id,
    unitId: unitId,
    callSign: callSign,
    capturedAt: capturedAt,
    outcome: outcome,
    personsAssisted: personsAssisted,
    timeOnSceneSeconds: timeOnSceneSeconds,
    injured: injured,
    missing: missing,
    affectedFamilies: affectedFamilies,
    housesDamaged: housesDamaged,
    notes: notes,
    validatedAt: validatedAt,
    validatedByName: validatedByName,
    corrected: value,
  );

  factory CrewReport.fromJson(Map<String, Object?> json) => CrewReport(
    id: json['report_id']! as String,
    unitId: json['unit_id']! as String,
    callSign: json['call_sign'] as String?,
    capturedAt: timeFromJson(json['captured_at']),
    outcome: enumFromJson(RescueOutcome.values, json['outcome']),
    personsAssisted: json['persons_assisted'] as int? ?? 0,
    timeOnSceneSeconds: json['time_on_scene_s'] as int? ?? 0,
    injured: json['injured'] as int? ?? 0,
    missing: json['missing'] as int? ?? 0,
    affectedFamilies: json['affected_families'] as int? ?? 0,
    housesDamaged: json['houses_damaged'] as int? ?? 0,
    notes: json['notes'] as String?,
    validatedAt: timeFromJsonOrNull(json['validated_at']),
    validatedByName: json['validated_by_name'] as String?,
    corrected: json['corrected'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {
    'report_id': id,
    'unit_id': unitId,
    'call_sign': callSign,
    'captured_at': capturedAt.toIso8601String(),
    'outcome': outcome.name,
    'persons_assisted': personsAssisted,
    'time_on_scene_s': timeOnSceneSeconds,
    'injured': injured,
    'missing': missing,
    'affected_families': affectedFamilies,
    'houses_damaged': housesDamaged,
    'notes': notes,
    'validated_at': validatedAt?.toIso8601String(),
    'validated_by_name': validatedByName,
    'corrected': corrected,
  };
}

/// The figures MDRRMD changes when validating; null keeps the crew's value.
@immutable
class CrewReportCorrection {
  const CrewReportCorrection({
    this.outcome,
    this.personsAssisted,
    this.injured,
    this.missing,
    this.affectedFamilies,
    this.housesDamaged,
  });

  final RescueOutcome? outcome;
  final int? personsAssisted;
  final int? injured;
  final int? missing;
  final int? affectedFamilies;
  final int? housesDamaged;
}

/// The stages of a fire as MDRRMD records them (its fire sheet's "Alarm
/// Details": Verification, Positive Alarm, 1st and 2nd Alarm, Fire Under
/// Control, Fire Out). Verification is the incident's own "verified" event.
/// In escalating order; the alarms end at [generalAlarm].
enum FireStage {
  positiveAlarm,
  firstAlarm,
  secondAlarm,
  thirdAlarm,
  fourthAlarm,
  fifthAlarm,
  taskForceAlpha,
  taskForceBravo,
  taskForceCharlie,
  taskForceDelta,
  taskForceEcho,
  generalAlarm,
  fireUnderControl,
  fireOut;

  /// An alarm level (not "under control" or "out").
  bool get isAlarm => index <= generalAlarm.index;
}
