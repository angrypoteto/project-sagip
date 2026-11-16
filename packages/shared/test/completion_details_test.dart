import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  test('an EMR report round-trips, with the patient name optional', () {
    const d = CompletionDetails(
      emrType: EmrType.roadAccident,
      accidentCause: AccidentCause.overspeeding,
      vehicles: [VehicleKind.motorcycle, VehicleKind.puj],
      patients: [
        PatientRecord(
          age: AgeBracket.from26To30,
          gender: PatientGender.male,
          hospital: 'Ospital ng Maynila (OSMA)',
          chiefComplaint: 'Leg pain',
        ),
        PatientRecord(name: '  ', age: AgeBracket.upTo17),
      ],
    );
    final json = d.toJson();
    expect(json['emr_type'], 'roadAccident');
    expect(json['vehicles'], ['motorcycle', 'puj']);
    final patients = json['patients']! as List;
    expect((patients.first as Map).containsKey('name'), isFalse);
    expect(
      (patients.last as Map).containsKey('name'),
      isFalse,
      reason: 'a blank name is not sent',
    );
    expect(
      CompletionDetails.fromJson(json),
      d.copyWith(
        patients: [
          d.patients.first,
          const PatientRecord(age: AgeBracket.upTo17),
        ],
      ),
    );
  });

  test('only what applies is sent', () {
    const medical = CompletionDetails(
      emrType: EmrType.medicalCall,
      accidentCause: AccidentCause.drunkDriving,
      vehicles: [VehicleKind.taxi],
    );
    expect(medical.toJson(), {
      'emr_type': 'medicalCall',
    }, reason: 'cause and vehicles only for a road accident');
    const flood = CompletionDetails(
      floodCause: FloodCause.heavyRainfall,
      cycloneName: 'Uwan',
      windSignal: 3,
      floodLevel: FloodLevel.knee,
      floodStatus: FloodStatus.nplv,
    );
    expect(flood.toJson(), {
      'flood_cause': 'heavyRainfall',
      'flood_level': 'knee',
      'flood_status': 'nplv',
    }, reason: 'the cyclone only when the cause is a cyclone');
    expect(const CompletionDetails().isEmpty, isTrue);
  });

  test('a fire report round-trips; unknown values are dropped', () {
    const fire = CompletionDetails(
      fireKind: FireKind.residential,
      highestAlarm: FireStage.secondAlarm,
      estimatedDamage: 150000,
      affectedIndividuals: 12,
    );
    expect(CompletionDetails.fromJson(fire.toJson()), fire);
    final odd = CompletionDetails.fromJson({
      'fire_kind': 'volcano',
      'vehicles': ['spaceship'],
      'emr_type': 'roadAccident',
    });
    expect(odd.fireKind, isNull);
    expect(odd.vehicles, isEmpty);
  });

  test('the report carries its details and the photo minimum by type', () {
    final r = CompletionReport(
      clientId: '3f2a9c1e-7b4d-4e0a-9c2f-1a2b3c4d5e6f',
      incidentId: 'INC-0001',
      capturedAt: DateTime.utc(2026, 11, 17),
      outcome: RescueOutcome.transported,
      personsAssisted: 1,
      timeOnScene: const Duration(minutes: 9),
      details: const CompletionDetails(emrType: EmrType.patientTransport),
    );
    expect(CompletionReport.fromJson(r.toJson()).details, r.details);
    expect(minimumCrewPhotos('medical'), 3);
    expect(minimumCrewPhotos('fire'), 2);
    expect(minimumCrewPhotos('flood'), 0);
  });

  group('the report starts filled in (2026-11-17)', () {
    Assignment job(
      IncidentType type, {
      int? people,
      int? found,
      String? name,
      List<VulnerabilityType> vulnerable = const [],
      FireStage? alarm,
    }) => Assignment(
      incidentId: 'INC-0001',
      offeredAt: DateTime.utc(2026, 11, 17),
      location: const GeoPoint(14.6, 120.98),
      barangay: 'Barangay 856',
      district: 'Pandacan',
      channel: ReportChannel.app,
      type: type,
      peopleCount: people,
      peopleFound: found,
      residentName: name,
      vulnerable: vulnerable,
      highestAlarm: alarm,
    );

    WeatherStatus weather({int signal = 0, double rain = 0, String? surge}) =>
        WeatherStatus(
          signalLevel: signal,
          rainfallMmPerHour: rain,
          stormSurgeAdvisory: surge,
          issuedAt: DateTime.utc(2026, 11, 17),
        );

    test('medical: the SOS sender is the first patient', () {
      final d = prefillCompletionDetails(
        job(
          IncidentType.medical,
          people: 3,
          found: 2,
          name: 'Juan Dela Cruz',
          vulnerable: const [VulnerabilityType.seniorCitizen],
        ),
      );
      expect(d.emrType, EmrType.medicalCall);
      expect(d.patients, hasLength(2), reason: 'people found on scene win');
      expect(d.patients.first.name, 'Juan Dela Cruz');
      expect(d.patients.first.age, AgeBracket.from61);
      expect(d.patients.last, const PatientRecord());
      expect(
        prefillCompletionDetails(job(IncidentType.medical)).patients,
        hasLength(1),
      );
    });

    test('flood: the cause from PAGASA now', () {
      final f = job(IncidentType.flood);
      final cyclone = prefillCompletionDetails(
        f,
        weather: weather(signal: 2, rain: 20),
      );
      expect(cyclone.floodCause, FloodCause.tropicalCyclone);
      expect(cyclone.windSignal, 2);
      expect(
        prefillCompletionDetails(
          f,
          weather: weather(surge: 'Up to 2 m'),
        ).floodCause,
        FloodCause.stormSurge,
      );
      expect(
        prefillCompletionDetails(f, weather: weather(rain: 8)).floodCause,
        FloodCause.heavyRainfall,
      );
      expect(
        prefillCompletionDetails(f, weather: weather(rain: 2)).isEmpty,
        isTrue,
      );
      expect(prefillCompletionDetails(f).isEmpty, isTrue);
    });

    test('fire: the highest alarm recorded; the name travels with the job', () {
      final a = job(IncidentType.fire, alarm: FireStage.secondAlarm);
      expect(prefillCompletionDetails(a).highestAlarm, FireStage.secondAlarm);
      final back = Assignment.fromJson(
        job(
          IncidentType.medical,
          name: 'Ana',
          alarm: FireStage.firstAlarm,
        ).toJson(),
      );
      expect(back.residentName, 'Ana');
      expect(back.highestAlarm, FireStage.firstAlarm);
    });
  });

  test(
    'a RAG fill: read from the server, merged keeping names (2026-11-17)',
    () {
      final fill = CrewReportFill.fromJson({
        'answers': {
          'emr_type': 'roadAccident',
          'accident_cause': 'overspeeding',
          'vehicles': ['motorcycle', 'pedestrian'],
          'patients': [
            {'age': 'from61', 'hospital': 'Ospital ng Maynila (OSMA)'},
            {'gender': 'male', 'hospital': 'Philippine General Hospital (PGH)'},
          ],
        },
        'figures': {'injured': 2, 'persons_assisted': 2},
        'narrative': 'A motorcycle hit a pedestrian.',
        'check': ['houses damaged 9 is not in the notes'],
        'references': [
          {'id': 1, 'title': 'EMR form: patients'},
        ],
        'model': 'openai/gpt-oss-120b',
        'retrieval': 'embedding',
        'ms': 2100,
      });
      expect(fill.figures, {'injured': 2, 'persons_assisted': 2});
      expect(fill.references, ['EMR form: patients']);
      expect(fill.ms, 2100);
      const current = CompletionDetails(
        emrType: EmrType.medicalCall,
        patients: [PatientRecord(name: 'Ana', gender: PatientGender.female)],
      );
      final merged = fill.mergeInto(current);
      expect(merged.emrType, EmrType.roadAccident, reason: 'the notes win');
      expect(merged.patients, hasLength(2));
      expect(merged.patients.first.name, 'Ana', reason: 'names are kept');
      expect(merged.patients.first.gender, PatientGender.female);
      expect(merged.patients.first.age, AgeBracket.from61);
      expect(merged.patients.last.name, isNull);
      expect(fill.filledCount, greaterThan(5));
      final empty = const CrewReportFill(details: CompletionDetails());
      expect(
        empty.mergeInto(current),
        current,
        reason: 'nothing said, nothing changed',
      );
    },
  );
}
