import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The narrative written from the report's own answers (2026-11-18), on
/// the Objective 4 trial cards.
void main() {
  test('Card A: a road accident with 2 patients, no names', () {
    final n = composeCrewNarrative(
      type: 'medical',
      outcome: RescueOutcome.transported,
      personsAssisted: 2,
      injured: 2,
      details: const CompletionDetails(
        emrType: EmrType.roadAccident,
        accidentCause: AccidentCause.overspeeding,
        vehicles: [VehicleKind.motorcycle, VehicleKind.pedestrian],
        patients: [
          PatientRecord(
            name: 'Lourdes Ramos',
            age: AgeBracket.from61,
            gender: PatientGender.female,
            hospital: 'Ospital ng Maynila (OSMA)',
            chiefComplaint: 'knee injury',
          ),
          PatientRecord(
            name: 'Paolo Cruz',
            age: AgeBracket.from26To30,
            gender: PatientGender.male,
            hospital: 'Philippine General Hospital (PGH)',
            chiefComplaint: 'shoulder injury',
          ),
        ],
      ),
    );
    expect(
      n,
      'A road accident, caused by overspeeding, involving a motorcycle and '
      'a pedestrian. 2 patients: a female aged 61 and above with knee '
      'injury, taken to Ospital ng Maynila (OSMA); a male aged 26-30 with '
      'shoulder injury, taken to Philippine General Hospital (PGH).',
    );
    expect(n, isNot(contains('Ramos')));
    expect(n, isNot(contains('Cruz')));
  });

  test('Card B: a knee-deep flood', () {
    expect(
      composeCrewNarrative(
        type: 'flood',
        outcome: RescueOutcome.rescued,
        personsAssisted: 12,
        affectedFamilies: 3,
        details: const CompletionDetails(
          floodCause: FloodCause.heavyRainfall,
          floodLevel: FloodLevel.knee,
          floodStatus: FloodStatus.nplv,
        ),
      ),
      'A knee-deep (19 in.) flood caused by heavy rainfall. Not passable to '
      'light vehicles. 12 persons were assisted. No one was injured or '
      'missing. 3 families were affected.',
    );
  });

  test('Card C: a residential fire at 2nd alarm', () {
    expect(
      composeCrewNarrative(
        type: 'fire',
        outcome: RescueOutcome.rescued,
        personsAssisted: 15,
        injured: 1,
        housesDamaged: 2,
        affectedFamilies: 4,
        details: const CompletionDetails(
          fireKind: FireKind.residential,
          highestAlarm: FireStage.secondAlarm,
          estimatedDamage: 150000,
          affectedIndividuals: 15,
        ),
      ),
      'A residential fire that reached the 2nd alarm. Estimated damage: '
      'PHP 150,000. 15 persons were affected. 1 person was injured. 2 houses '
      'were damaged. 4 families were affected.',
    );
  });

  test('blank answers are left out, nothing is made up', () {
    expect(
      composeCrewNarrative(
        type: 'flood',
        outcome: RescueOutcome.rescued,
        personsAssisted: 0,
        details: const CompletionDetails(),
      ),
      'No one was injured or missing.',
    );
  });

  test('a false report says so and nothing else', () {
    expect(
      composeCrewNarrative(
        type: 'fire',
        outcome: RescueOutcome.falseReport,
        personsAssisted: 0,
        details: const CompletionDetails(fireKind: FireKind.rubbish),
      ),
      'The crew found no emergency at the location; the report was false.',
    );
  });
}
