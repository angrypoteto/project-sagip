import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'crew_report.dart';

/// The answers on a crew's report that MDRRMD's own forms ask for
/// (Joshua, 2026-11-17: EMR, Flood Monitoring/Roving and Fire Incident 2026
/// forms). Only the part for the incident's type is filled in; date, time,
/// place, district, barangay, month and quarter come from the incident and
/// the phone, and the injured, affected families and damage are on the
/// report itself ([CompletionReport]).

// ------------------------------------------------------------------ medical

/// TYPE OF EMR.
enum EmrType { roadAccident, medicalCall, medicalStandby, patientTransport }

/// CAUSE OF ROAD ACCIDENT.
enum AccidentCause {
  drunkDriving,
  lossOfControl,
  brakeFailure,
  overspeeding,
  driverNegligence,
  roadCondition,
  roadHazards,
  inclementWeather,
  roadTrafficCollision,
  other,
}

/// TYPE OF VEHICLE INVOLVED.
enum VehicleKind {
  pedestrian,
  bicycle,
  motorcycle,
  eBike,
  tricycle,
  eTrike,
  sedan,
  suv,
  van,
  taxi,
  puj,
  puv,
  truck,
  ambulance,
  fireTruck,
  other,
}

/// AGE, as the form's brackets.
enum AgeBracket {
  upTo17,
  from18To25,
  from26To30,
  from31To35,
  from36To40,
  from41To45,
  from46To50,
  from51To60,
  from61,
}

enum PatientGender { male, female, other }

/// RECEIVING HOSPITAL, in the form's order. The first two are not
/// hospitals: the patient refused to be taken, or the form's "Double two
/// upon arrival".
const receivingHospitals = [
  'Refused to transport',
  'Double two upon arrival',
  'Philippine Orthopedic Center (P.O.C.)',
  'Ospital ng Maynila (OSMA)',
  'Ospital ng Sampaloc (OSAM)',
  'Ospital ng Tondo',
  'Philippine General Hospital (PGH)',
  'Sta. Ana Hospital',
  'Gat Andres Bonifacio Hospital',
  'Tondo Medical Hospital',
  'Jose Reyes Hospital',
  'Chinese General Hospital',
  'Metropolitan Hospital',
  'Manila Medical Center',
  'St. Jude Hospital',
  'Infant Jesus Hospital',
  'UST Hospital',
  "Manila Doctor's Hospital",
  'Mary Johnston Hospital',
  'Justice Jose Abad Santos General Hospital (JJASGEN)',
  'UERM',
  'Other',
];

/// One patient on an EMR report. The name is optional (Joshua,
/// 2026-11-17); the server removes it when the incident is anonymized
/// (RA 10173).
@immutable
class PatientRecord {
  const PatientRecord({
    this.name,
    this.age,
    this.gender,
    this.hospital,
    this.chiefComplaint,
    this.remarks,
  });

  final String? name;
  final AgeBracket? age;
  final PatientGender? gender;
  final String? hospital;
  final String? chiefComplaint;
  final String? remarks;

  PatientRecord copyWith({
    String? name,
    AgeBracket? age,
    PatientGender? gender,
    String? hospital,
    String? chiefComplaint,
    String? remarks,
  }) => PatientRecord(
    name: name ?? this.name,
    age: age ?? this.age,
    gender: gender ?? this.gender,
    hospital: hospital ?? this.hospital,
    chiefComplaint: chiefComplaint ?? this.chiefComplaint,
    remarks: remarks ?? this.remarks,
  );

  Map<String, Object?> toJson() => {
    if (_text(name) != null) 'name': _text(name),
    if (age != null) 'age': age!.name,
    if (gender != null) 'gender': gender!.name,
    if (_text(hospital) != null) 'hospital': _text(hospital),
    if (_text(chiefComplaint) != null) 'chief_complaint': _text(chiefComplaint),
    if (_text(remarks) != null) 'remarks': _text(remarks),
  };

  factory PatientRecord.fromJson(Map<String, Object?> json) => PatientRecord(
    name: json['name'] as String?,
    age: _enum(AgeBracket.values, json['age']),
    gender: _enum(PatientGender.values, json['gender']),
    hospital: json['hospital'] as String?,
    chiefComplaint: json['chief_complaint'] as String?,
    remarks: json['remarks'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is PatientRecord &&
      other.name == name &&
      other.age == age &&
      other.gender == gender &&
      other.hospital == hospital &&
      other.chiefComplaint == chiefComplaint &&
      other.remarks == remarks;

  @override
  int get hashCode =>
      Object.hash(name, age, gender, hospital, chiefComplaint, remarks);
}

// ------------------------------------------------------------------ flood

/// CAUSE OF FLOOD.
enum FloodCause { cloggedWaterways, heavyRainfall, tropicalCyclone, stormSurge }

/// FLOOD LEVEL, shallow to deep (inches as on the form where it gives them).
enum FloodLevel {
  gutter, // 8"
  halfKnee, // 10"
  halfTire, // 13"
  knee, // 19"
  tire, // 28"
  waist, // 37"
  chest, // 45"
  aboveChest,
  head,
}

/// FLOOD STATUS: passable to all vehicles (PATV), not passable to light
/// vehicles (NPLV), not passable to all vehicles (NPATV).
enum FloodStatus { patv, nplv, npatv }

// ------------------------------------------------------------------ fire

/// TYPE OF FIRE INCIDENT.
enum FireKind {
  rubbish,
  electrical,
  commercial,
  residential,
  governmentOffice,
  vehicular,
  warehouse,
  residentialCommercial,
}

// ------------------------------------------------------------------ all

@immutable
class CompletionDetails {
  const CompletionDetails({
    this.emrType,
    this.accidentCause,
    this.vehicles = const [],
    this.patients = const [],
    this.floodCause,
    this.cycloneName,
    this.windSignal,
    this.floodLevel,
    this.floodStatus,
    this.fireKind,
    this.highestAlarm,
    this.estimatedDamage,
    this.affectedIndividuals,
  });

  // Medical (EMR form).
  final EmrType? emrType;
  final AccidentCause? accidentCause;
  final List<VehicleKind> vehicles;
  final List<PatientRecord> patients;

  // Flood (Flood Monitoring/Roving form).
  final FloodCause? floodCause;
  final String? cycloneName;

  /// Tropical cyclone wind signal 1 to 5.
  final int? windSignal;
  final FloodLevel? floodLevel;
  final FloodStatus? floodStatus;

  // Fire (Fire Incident form).
  final FireKind? fireKind;

  /// HIGHEST ALARM LEVEL: one of the alarm stages ([FireStage.isAlarm]).
  final FireStage? highestAlarm;

  /// Pesos.
  final int? estimatedDamage;
  final int? affectedIndividuals;

  bool get isEmpty => toJson().isEmpty;

  CompletionDetails copyWith({
    EmrType? emrType,
    AccidentCause? accidentCause,
    List<VehicleKind>? vehicles,
    List<PatientRecord>? patients,
    FloodCause? floodCause,
    String? cycloneName,
    int? windSignal,
    FloodLevel? floodLevel,
    FloodStatus? floodStatus,
    FireKind? fireKind,
    FireStage? highestAlarm,
    int? estimatedDamage,
    int? affectedIndividuals,
  }) => CompletionDetails(
    emrType: emrType ?? this.emrType,
    accidentCause: accidentCause ?? this.accidentCause,
    vehicles: vehicles ?? this.vehicles,
    patients: patients ?? this.patients,
    floodCause: floodCause ?? this.floodCause,
    cycloneName: cycloneName ?? this.cycloneName,
    windSignal: windSignal ?? this.windSignal,
    floodLevel: floodLevel ?? this.floodLevel,
    floodStatus: floodStatus ?? this.floodStatus,
    fireKind: fireKind ?? this.fireKind,
    highestAlarm: highestAlarm ?? this.highestAlarm,
    estimatedDamage: estimatedDamage ?? this.estimatedDamage,
    affectedIndividuals: affectedIndividuals ?? this.affectedIndividuals,
  );

  /// Only what applies: the cause of a road accident and the vehicles only
  /// for a road accident, the cyclone's name and signal only for a
  /// cyclone.
  Map<String, Object?> toJson() {
    final road = emrType == EmrType.roadAccident;
    final cyclone = floodCause == FloodCause.tropicalCyclone;
    return {
      if (emrType != null) 'emr_type': emrType!.name,
      if (road && accidentCause != null) 'accident_cause': accidentCause!.name,
      if (road && vehicles.isNotEmpty)
        'vehicles': [for (final v in vehicles) v.name],
      if (patients.isNotEmpty)
        'patients': [for (final p in patients) p.toJson()],
      if (floodCause != null) 'flood_cause': floodCause!.name,
      if (cyclone && _text(cycloneName) != null)
        'cyclone_name': _text(cycloneName),
      if (cyclone && windSignal != null) 'wind_signal': windSignal,
      if (floodLevel != null) 'flood_level': floodLevel!.name,
      if (floodStatus != null) 'flood_status': floodStatus!.name,
      if (fireKind != null) 'fire_kind': fireKind!.name,
      if (highestAlarm != null) 'highest_alarm': highestAlarm!.name,
      if (estimatedDamage != null) 'estimated_damage': estimatedDamage,
      if (affectedIndividuals != null)
        'affected_individuals': affectedIndividuals,
    };
  }

  factory CompletionDetails.fromJson(Object? raw) {
    if (raw is! Map) return const CompletionDetails();
    final json = raw.cast<String, Object?>();
    final vehicles = json['vehicles'];
    final patients = json['patients'];
    return CompletionDetails(
      emrType: _enum(EmrType.values, json['emr_type']),
      accidentCause: _enum(AccidentCause.values, json['accident_cause']),
      vehicles: [
        if (vehicles is List)
          for (final v in vehicles) ?_enum(VehicleKind.values, v),
      ],
      patients: [
        if (patients is List)
          for (final p in patients)
            if (p is Map) PatientRecord.fromJson(p.cast<String, Object?>()),
      ],
      floodCause: _enum(FloodCause.values, json['flood_cause']),
      cycloneName: json['cyclone_name'] as String?,
      windSignal: (json['wind_signal'] as num?)?.toInt(),
      floodLevel: _enum(FloodLevel.values, json['flood_level']),
      floodStatus: _enum(FloodStatus.values, json['flood_status']),
      fireKind: _enum(FireKind.values, json['fire_kind']),
      highestAlarm: _enum(FireStage.values, json['highest_alarm']),
      estimatedDamage: (json['estimated_damage'] as num?)?.toInt(),
      affectedIndividuals: (json['affected_individuals'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompletionDetails &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The fewest photos MDRRMD's form asks for, by incident type: EMR at
/// least 3 (the PCR front and back and incident photos), fire at least 2.
/// The flood form asks for none.
int minimumCrewPhotos(String? incidentType) => switch (incidentType) {
  'medical' => 3,
  'fire' => 2,
  _ => 0,
};

/// At most this many photos on one crew report (the fire form allows 15).
const maxCrewPhotos = 15;

String? _text(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// The enum value named [raw], or null when it is missing or unknown (an
/// older or newer app's value is dropped, not an error).
T? _enum<T extends Enum>(List<T> values, Object? raw) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

/// What "Fill from notes" (RAG, fill-crew-report) answered (2026-11-17):
/// the form's answers, the report's figures, and a short narrative, all for
/// the responder to check before submitting.
@immutable
class CrewReportFill {
  const CrewReportFill({
    required this.details,
    this.figures = const {},
    this.narrative = '',
    this.check = const [],
    this.references = const [],
    this.model,
    this.retrieval,
    this.ms,
  });

  final CompletionDetails details;

  /// Any of persons_assisted, injured, missing, affected_families,
  /// houses_damaged the notes gave.
  final Map<String, int> figures;
  final String narrative;

  /// What the server dropped or wants checked.
  final List<String> check;

  /// The form guidance passages it retrieved, by title.
  final List<String> references;
  final String? model;
  final String? retrieval;
  final int? ms;

  factory CrewReportFill.fromJson(Map<String, Object?> json) {
    final figures = json['figures'];
    final check = json['check'];
    final refs = json['references'];
    return CrewReportFill(
      details: CompletionDetails.fromJson(json['answers']),
      figures: {
        if (figures is Map)
          for (final e in figures.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      narrative: (json['narrative'] as String? ?? '').trim(),
      check: [
        if (check is List)
          for (final c in check) '$c',
      ],
      references: [
        if (refs is List)
          for (final r in refs)
            if (r is Map && r['title'] is String) r['title']! as String,
      ],
      model: json['model'] as String?,
      retrieval: json['retrieval'] as String?,
      ms: (json['ms'] as num?)?.toInt(),
    );
  }

  /// [current] with these answers on top: an answer the notes gave replaces
  /// the one there; one they did not give stays. Patients' names already
  /// typed or pre-filled are kept (the server never sends names).
  CompletionDetails mergeInto(CompletionDetails current) {
    final x = details;
    final patients = x.patients.isEmpty
        ? current.patients
        : [
            for (var i = 0; i < x.patients.length; i++)
              PatientRecord(
                name: i < current.patients.length
                    ? current.patients[i].name
                    : null,
                age:
                    x.patients[i].age ??
                    (i < current.patients.length
                        ? current.patients[i].age
                        : null),
                gender:
                    x.patients[i].gender ??
                    (i < current.patients.length
                        ? current.patients[i].gender
                        : null),
                hospital: x.patients[i].hospital,
                chiefComplaint: x.patients[i].chiefComplaint,
                remarks: x.patients[i].remarks,
              ),
          ];
    return CompletionDetails(
      emrType: x.emrType ?? current.emrType,
      accidentCause: x.accidentCause ?? current.accidentCause,
      vehicles: x.vehicles.isEmpty ? current.vehicles : x.vehicles,
      patients: patients,
      floodCause: x.floodCause ?? current.floodCause,
      cycloneName: x.cycloneName ?? current.cycloneName,
      windSignal: x.windSignal ?? current.windSignal,
      floodLevel: x.floodLevel ?? current.floodLevel,
      floodStatus: x.floodStatus ?? current.floodStatus,
      fireKind: x.fireKind ?? current.fireKind,
      highestAlarm: x.highestAlarm ?? current.highestAlarm,
      estimatedDamage: x.estimatedDamage ?? current.estimatedDamage,
      affectedIndividuals: x.affectedIndividuals ?? current.affectedIndividuals,
    );
  }

  /// How many answers and figures it filled in.
  int get filledCount =>
      details.toJson().length +
      details.patients.fold<int>(0, (n, p) => n + p.toJson().length) -
      (details.patients.isEmpty ? 0 : 1) +
      figures.length;
}
