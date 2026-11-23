import '../models/assignment.dart';
import '../models/completion_details.dart';
import '../models/crew_report.dart';

/// The narrative MDRRMD gets when the crew wrote none and did not use Fill
/// from notes (Joshua, 2026-11-18: "the narrative for the mdrrmd should be
/// filled in automatically even though i didn't use the fill notes, base
/// on the inputted data").
///
/// Fixed sentences from the report's own answers, so nothing is invented;
/// an answer left blank is left out. No names (the RAG narrative's rule)
/// and no place (MDRRMD has it on the incident). It is report text for
/// MDRRMD, in English like their forms, not UI text. Not RAG: no language
/// model; Fill from notes stays the RAG.
///
/// [type] is the incident type's name (`medical`, `flood`, `fire`, ...);
/// the counts are the ones the report sends.
String composeCrewNarrative({
  required String? type,
  required RescueOutcome outcome,
  required CompletionDetails details,
  required int personsAssisted,
  int injured = 0,
  int missing = 0,
  int affectedFamilies = 0,
  int housesDamaged = 0,
}) {
  final x = details;
  final s = <String>[];

  if (outcome == RescueOutcome.falseReport) {
    return 'The crew found no emergency at the location; '
        'the report was false.';
  }
  if (outcome == RescueOutcome.noOneFound) {
    s.add('The crew found no one needing help at the location.');
  }

  switch (type) {
    case 'medical':
      final what = switch (x.emrType) {
        EmrType.roadAccident => 'A road accident',
        EmrType.medicalCall => 'A medical call',
        EmrType.medicalStandby => 'A medical standby',
        EmrType.patientTransport => 'A patient transport',
        null => null,
      };
      final road = x.emrType == EmrType.roadAccident;
      final cause = road ? _accidentCause(x.accidentCause) : null;
      final vehicles = road
          ? [
              for (final v in x.vehicles)
                if (v != VehicleKind.other) _vehicle(v),
            ]
          : const <String>[];
      if (what != null) {
        s.add(
          _sentence([
            what,
            if (cause != null) 'caused by $cause',
            if (vehicles.isNotEmpty) 'involving ${_list(vehicles)}',
          ], ', '),
        );
      }
      final patients = [for (final p in x.patients) _patient(p)];
      if (patients.isNotEmpty) {
        final n = patients.length;
        s.add('$n ${n == 1 ? 'patient' : 'patients'}: ${patients.join('; ')}.');
      }

    case 'flood':
      final level = _floodLevel(x.floodLevel);
      final cause = switch (x.floodCause) {
        FloodCause.heavyRainfall => 'heavy rainfall',
        FloodCause.cloggedWaterways => 'clogged waterways',
        FloodCause.stormSurge => 'a storm surge',
        FloodCause.tropicalCyclone => [
          'tropical cyclone',
          if ((x.cycloneName ?? '').trim().isNotEmpty) x.cycloneName!.trim(),
          if (x.windSignal != null) '(wind signal no. ${x.windSignal})',
        ].join(' '),
        null => null,
      };
      if (level != null || cause != null) {
        s.add(
          _sentence([
            level == null ? 'A flood' : 'A $level flood',
            if (cause != null) 'caused by $cause',
          ], ' '),
        );
      }
      final status = switch (x.floodStatus) {
        FloodStatus.patv => 'Passable to all vehicles.',
        FloodStatus.nplv => 'Not passable to light vehicles.',
        FloodStatus.npatv => 'Not passable to all vehicles.',
        null => null,
      };
      if (status != null) s.add(status);

    case 'fire':
      final kind = _fireKind(x.fireKind);
      final alarm = _alarm(x.highestAlarm);
      if (kind != null || alarm != null) {
        s.add(
          _sentence([
            kind == null ? 'A fire' : 'A $kind fire',
            if (alarm != null) 'that reached $alarm',
          ], ' '),
        );
      }
      final damage = x.estimatedDamage;
      if (damage != null && damage > 0) {
        s.add('Estimated damage: PHP ${_thousands(damage)}.');
      }
  }

  // The counts, each once.
  if (type != 'medical' && personsAssisted > 0) {
    s.add(
      '$personsAssisted ${personsAssisted == 1 ? 'person was' : 'persons were'} '
      '${type == 'fire' ? 'affected' : 'assisted'}.',
    );
  }
  if (type != 'medical') {
    final noOne = [
      if (injured == 0) 'injured',
      if (type == 'flood' && missing == 0) 'missing',
    ];
    if (injured > 0) {
      s.add(
        '$injured ${injured == 1 ? 'person was' : 'persons were'} injured.',
      );
    }
    if (type == 'flood' && missing > 0) {
      s.add('$missing ${missing == 1 ? 'person is' : 'persons are'} missing.');
    }
    if (noOne.isNotEmpty) s.add('No one was ${noOne.join(' or ')}.');
  }
  if (type != 'medical' && type != 'flood' && housesDamaged > 0) {
    s.add(
      '$housesDamaged ${housesDamaged == 1 ? 'house was' : 'houses were'} '
      'damaged.',
    );
  }
  if (type != 'medical' && affectedFamilies > 0) {
    s.add(
      '$affectedFamilies '
      '${affectedFamilies == 1 ? 'family was' : 'families were'} affected.',
    );
  }
  return s.join(' ');
}

String _patient(PatientRecord p) {
  final who = [
    switch (p.gender) {
      PatientGender.male => 'a male',
      PatientGender.female => 'a female',
      PatientGender.other || null => 'a patient',
    },
    if (_age(p.age) case final a?) 'aged $a',
  ].join(' ');
  final complaint = (p.chiefComplaint ?? '').trim();
  final hospital = (p.hospital ?? '').trim();
  final described = complaint.isEmpty ? who : '$who with $complaint';
  return [
    described,
    if (hospital.isNotEmpty)
      switch (hospital) {
        'Refused to transport' => 'refused to be taken to a hospital',
        'Double two upon arrival' => 'double two upon arrival',
        _ => 'taken to $hospital',
      },
  ].join(', ');
}

String? _age(AgeBracket? a) => switch (a) {
  AgeBracket.upTo17 => '17 or below',
  AgeBracket.from18To25 => '18-25',
  AgeBracket.from26To30 => '26-30',
  AgeBracket.from31To35 => '31-35',
  AgeBracket.from36To40 => '36-40',
  AgeBracket.from41To45 => '41-45',
  AgeBracket.from46To50 => '46-50',
  AgeBracket.from51To60 => '51-60',
  AgeBracket.from61 => '61 and above',
  null => null,
};

String? _accidentCause(AccidentCause? c) => switch (c) {
  AccidentCause.drunkDriving => 'drunk driving',
  AccidentCause.lossOfControl => 'loss of control',
  AccidentCause.brakeFailure => 'brake failure',
  AccidentCause.overspeeding => 'overspeeding',
  AccidentCause.driverNegligence => 'driver negligence',
  AccidentCause.roadCondition => 'the road condition',
  AccidentCause.roadHazards => 'road hazards',
  AccidentCause.inclementWeather => 'inclement weather',
  AccidentCause.roadTrafficCollision => 'a road traffic collision',
  AccidentCause.other || null => null,
};

String _vehicle(VehicleKind v) => switch (v) {
  VehicleKind.pedestrian => 'a pedestrian',
  VehicleKind.bicycle => 'a bicycle',
  VehicleKind.motorcycle => 'a motorcycle',
  VehicleKind.eBike => 'an e-bike',
  VehicleKind.tricycle => 'a tricycle',
  VehicleKind.eTrike => 'an e-trike',
  VehicleKind.sedan => 'a sedan',
  VehicleKind.suv => 'an SUV',
  VehicleKind.van => 'a van',
  VehicleKind.taxi => 'a taxi',
  VehicleKind.puj => 'a PUJ',
  VehicleKind.puv => 'a PUV',
  VehicleKind.truck => 'a truck',
  VehicleKind.ambulance => 'an ambulance',
  VehicleKind.fireTruck => 'a fire truck',
  VehicleKind.other => 'another vehicle',
};

String? _floodLevel(FloodLevel? l) => switch (l) {
  FloodLevel.gutter => 'gutter-deep (8 in.)',
  FloodLevel.halfKnee => 'half-knee-deep (10 in.)',
  FloodLevel.halfTire => 'half-tire-deep (13 in.)',
  FloodLevel.knee => 'knee-deep (19 in.)',
  FloodLevel.tire => 'tire-deep (28 in.)',
  FloodLevel.waist => 'waist-deep (37 in.)',
  FloodLevel.chest => 'chest-deep (45 in.)',
  FloodLevel.aboveChest => 'above-chest-deep',
  FloodLevel.head => 'head-deep',
  null => null,
};

String? _fireKind(FireKind? k) => switch (k) {
  FireKind.rubbish => 'rubbish',
  FireKind.electrical => 'electrical',
  FireKind.commercial => 'commercial',
  FireKind.residential => 'residential',
  FireKind.governmentOffice => 'government office',
  FireKind.vehicular => 'vehicular',
  FireKind.warehouse => 'warehouse',
  FireKind.residentialCommercial => 'residential and commercial',
  null => null,
};

String? _alarm(FireStage? a) => switch (a) {
  FireStage.firstAlarm => 'the 1st alarm',
  FireStage.secondAlarm => 'the 2nd alarm',
  FireStage.thirdAlarm => 'the 3rd alarm',
  FireStage.fourthAlarm => 'the 4th alarm',
  FireStage.fifthAlarm => 'the 5th alarm',
  FireStage.taskForceAlpha => 'Task Force Alpha',
  FireStage.taskForceBravo => 'Task Force Bravo',
  FireStage.taskForceCharlie => 'Task Force Charlie',
  FireStage.taskForceDelta => 'Task Force Delta',
  FireStage.taskForceEcho => 'Task Force Echo',
  FireStage.generalAlarm => 'the general alarm',
  _ => null,
};

String _sentence(List<String> parts, String sep) => '${parts.join(sep)}.';

String _list(List<String> xs) => switch (xs.length) {
  1 => xs.first,
  2 => '${xs[0]} and ${xs[1]}',
  _ => '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}',
};

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
