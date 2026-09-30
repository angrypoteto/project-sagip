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

enum UnitType { ambulance, rescueBoat, rescueTeam }

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
}

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
