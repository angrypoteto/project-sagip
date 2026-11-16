import '../models/assignment.dart';
import '../models/completion_details.dart';
import '../models/enums.dart';
import '../models/records.dart';

/// PAGASA's heavy rainfall: 7.5 mm or more in an hour.
const heavyRainfallMmPerHour = 7.5;

/// What the crew's report can start with, from what the phone already
/// knows (Joshua, 2026-11-17: "make some of the information already have
/// details since we already have some details about the incidents and the
/// name of the person"). Every answer stays changeable.
///
/// - Medical: a medical call, with one patient per person counted (on
///   scene, else in the SOS; at least one), the first named after the SOS
///   sender, 61 and above if the household lists a senior citizen, female
///   if it lists a pregnancy.
/// - Flood: the cause from PAGASA's reading now: a raised wind signal (a
///   tropical cyclone, with the signal), else a storm surge advisory, else
///   heavy rain.
/// - Fire: the highest alarm the dispatcher recorded.
CompletionDetails prefillCompletionDetails(
  Assignment a, {
  WeatherStatus? weather,
}) {
  switch (a.type) {
    case IncidentType.medical:
      final count = (a.peopleFound ?? a.peopleCount ?? 1).clamp(1, 30);
      final senior = a.vulnerable.contains(VulnerabilityType.seniorCitizen);
      final pregnant = a.vulnerable.contains(VulnerabilityType.pregnant);
      return CompletionDetails(
        emrType: EmrType.medicalCall,
        patients: [
          for (var i = 0; i < count; i++)
            i == 0
                ? PatientRecord(
                    name: a.residentName,
                    age: senior ? AgeBracket.from61 : null,
                    gender: pregnant ? PatientGender.female : null,
                  )
                : const PatientRecord(),
        ],
      );
    case IncidentType.flood:
      final w = weather;
      if (w == null) return const CompletionDetails();
      if (w.signalLevel > 0) {
        return CompletionDetails(
          floodCause: FloodCause.tropicalCyclone,
          windSignal: w.signalLevel.clamp(1, 5),
        );
      }
      if (w.stormSurgeAdvisory != null) {
        return const CompletionDetails(floodCause: FloodCause.stormSurge);
      }
      if (w.rainfallMmPerHour >= heavyRainfallMmPerHour) {
        return const CompletionDetails(floodCause: FloodCause.heavyRainfall);
      }
      return const CompletionDetails();
    case IncidentType.fire:
      return CompletionDetails(highestAlarm: a.highestAlarm);
    case IncidentType.structural:
    case null:
      return const CompletionDetails();
  }
}
