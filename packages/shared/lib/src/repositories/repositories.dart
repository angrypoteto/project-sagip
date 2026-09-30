import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';

// Repository interfaces. The UI depends only on these. Phase 1 uses the Mock*
// implementations; Phase 3 adds Supabase ones behind the same interfaces.
//
// Every `watch*` stream emits the current value immediately on listen and
// again on every change (realtime).

/// Thrown when a sign-in fails. [reason] is shown to the user through l10n.
class AuthException implements Exception {
  const AuthException(this.reason);

  final AuthFailure reason;

  @override
  String toString() => 'AuthException($reason)';
}

enum AuthFailure { wrongCredentials, accountDisabled, notStaff, offline }

/// Thrown when an action is refused, for example assigning a unit that
/// another dispatcher just took.
class ActionRejected implements Exception {
  const ActionRejected(this.reason);

  final ActionRejection reason;

  @override
  String toString() => 'ActionRejected($reason)';
}

enum ActionRejection {
  unitNotAvailable,
  alreadyAssigned,
  incidentClosed,
  notAllowed,
  offline,
}

abstract interface class AuthRepository {
  Stream<AppUser?> watchUser();
  AppUser? get currentUser;
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signOut();
}

abstract interface class IncidentRepository {
  /// Incidents on the Triage Queue: everything not yet resolved.
  Stream<List<Incident>> watchActive();

  /// Incidents resolved within [since] (for the timeline and analytics).
  Stream<List<Incident>> watchResolved({Duration since});

  Future<void> verify(String incidentId, VerificationMethod method);
  Future<void> sendSmsCheck(String incidentId);
  Future<void> markFalseReport(String incidentId, {String? reason});
  Future<void> confirmType(String incidentId, IncidentType type);

  /// Assigns [unitId]. Pass [overrideReason] when it is not the top
  /// suggestion (FR3 manual override).
  Future<void> assignUnit(
    String incidentId,
    String unitId, {
    String? overrideReason,
  });
  Future<void> resolve(String incidentId);
}

abstract interface class UnitRepository {
  Stream<List<ResponseUnit>> watchAll();
}

abstract interface class CrowdReportRepository {
  /// Reports submitted within [window] (DBSCAN looks at 60 minutes).
  Stream<List<CrowdReport>> watchRecent({Duration window});
}

abstract interface class ResidentRepository {
  Stream<Resident?> watchResident(String residentId);

  /// The Vulnerable Resident Priority List (admins and dispatchers only).
  Stream<List<Resident>> watchVulnerable();

  /// Returns the resident's full contact number and records the reveal in
  /// the audit log. Lists only carry masked numbers (NFR4).
  Future<String> revealContact(String residentId);
}

abstract interface class WeatherRepository {
  Stream<WeatherStatus> watchCurrent();
}

abstract interface class AuditRepository {
  Stream<List<AuditEntry>> watchRecent({int limit});
}

enum LinkState { live, reconnecting, offline }

/// Whether the dashboard can reach the backend and realtime is flowing.
abstract interface class ConnectionMonitor {
  Stream<LinkState> watch();
}
