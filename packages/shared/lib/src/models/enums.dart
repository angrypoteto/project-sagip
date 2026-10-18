/// Incident lifecycle (CLAUDE.md domain vocabulary).
enum IncidentStatus {
  /// An SOS that has not been confirmed by callback, SMS, or responders (FR8).
  pendingVerification,

  /// A single crowd report with no cluster yet (FR7). Shown on the map only.
  unverified,

  /// A verified SOS or a DBSCAN cluster of crowd reports.
  confirmed,

  /// A unit has been assigned but has not started moving.
  assigned,
  enRoute,
  onScene,
  resolved;

  /// Waiting for a dispatcher decision (no unit yet).
  bool get needsDispatch => this == pendingVerification || this == confirmed;

  /// A unit is attached and working on it.
  bool get isInProgress =>
      this == assigned || this == enRoute || this == onScene;
}

/// The four incident types the classifier and dispatcher use (FR12).
enum IncidentType { flood, fire, medical, structural }

/// How an incident came to exist.
enum IncidentOrigin {
  /// Single-person rescue request from the app.
  sos,

  /// A confirmed DBSCAN cluster of crowd reports.
  crowdCluster,
}

/// The path a record took to reach MDRRMD.
enum ReportChannel { app, sms, bleRelay, webForm }

/// Unit status as reported by responders (FR9).
enum UnitStatus { available, enRoute, onScene }

enum UnitType { ambulance, rescueBoat, rescueTeam, fireTruck }

/// Whose unit it is: MDRRMD's own, the Bureau of Fire Protection's, a
/// volunteer fire and rescue brigade's, or an emergency medical service's.
enum UnitAgency { mdrrmd, bfp, volunteer, ems }

/// What a unit carries and reports (unit inventory). Fuel and tank water
/// are a percent of full; the rest are counted against a full load.
enum SupplyItem {
  fuel,
  tankWater,
  drinkingWater,
  medicalKits,
  lifeVests,
  rescueGear;

  /// Reported as a percent of full, not as a count.
  bool get isPercent => this == fuel || this == tankWater;
}

/// How a supply stands against a full load.
enum SupplyState { ok, low, out }

/// Severity band derived from the priority score (provisional until the
/// MDRRMD SOP arrives, see plan Q15).
enum Severity { critical, high, normal }

enum UserRole {
  resident,
  responder,
  dispatcher,
  admin,

  /// Changes made outside the app (SQL editor, scheduled jobs). Appears
  /// only in the audit log; nobody signs in as system.
  system,
}

enum VulnerabilityType { seniorCitizen, pwd, pregnant, other }

/// How a dispatcher confirmed an SOS (FR8).
enum VerificationMethod { callback, smsReply, onScene }

/// Actions written to the audit log (FR11).
enum AuditAction {
  verified,
  markedFalseReport,
  typeConfirmed,
  unitAssigned,
  unitReassigned,
  statusChanged,
  resolved,
  smsCheckSent,
  contactViewed,
  settingChanged,
  unitAdded,
  unitEdited,
  unitRetired,
  unitRestored,
  rosterChanged,
  accountCreated,
  accountUpdated,
  accountDeactivated,
  accountReactivated,
  passwordReset,
  residentSuspended,
  residentRestored,

  /// A simulated PAGASA reading in simulation mode (A3).
  weatherSimulated,

  /// An advisory issued or ended from the dashboard (D10).
  alertIssued,
  alertEnded,

  /// An NDRRMC report drafted or marked final (A6).
  reportDrafted,
  reportFinalized,

  /// A simulated SOS or simulated crowd reports (simulation mode, A3).
  sosSimulated,
  reportsSimulated,

  /// An SOS closed because the resident asked to cancel it (D4).
  sosCancelled,

  /// The nightly job removed personal details older than the retention
  /// period (A3).
  retentionApplied,

  /// A crew reported one of its unit's supplies.
  supplyUpdated,

  /// An admin added or changed a safe place, hid one, or showed it again
  /// (A2).
  safePlaceSaved,
  safePlaceHidden,
  safePlaceRestored,
}

/// Why a resident asks to cancel their SOS (R2). A dispatcher decides.
enum SosCancelReason { safeNow, mistake, other }

/// Reads a timestamp from JSON and converts it to local time (the database
/// returns UTC), so the UI shows Manila time.
DateTime timeFromJson(Object? raw) => DateTime.parse(raw! as String).toLocal();

DateTime? timeFromJsonOrNull(Object? raw) =>
    raw == null ? null : timeFromJson(raw);

/// Reads an enum stored by its `name` in JSON.
T enumFromJson<T extends Enum>(List<T> values, Object? raw) =>
    values.byName(raw! as String);

/// Like [enumFromJson] but allows null.
T? enumFromJsonOrNull<T extends Enum>(List<T> values, Object? raw) =>
    raw == null ? null : values.byName(raw as String);
