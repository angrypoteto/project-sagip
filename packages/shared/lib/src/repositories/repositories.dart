import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/sos.dart';

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

// ---------------------------------------------------------------- mobile

/// What the phone can reach: internet, SMS only, or nothing (plan 7.6).
abstract interface class SignalMonitor {
  Stream<SignalState> watch();
}

/// GPS on or off, plus the last fix.
abstract interface class LocationService {
  Stream<LocationStatus> watch();

  /// Opens the phone's location settings so the resident can turn GPS on.
  Future<void> openSettings();
}

/// The resident's own SOS requests (R1, R2).
abstract interface class SosRepository {
  /// This resident's SOS requests, newest first.
  Stream<List<SosRequest>> watchMine();

  /// Saves a new SOS on the phone (Tier 1) and starts sending it by the best
  /// channel available. Completes as soon as the SOS is saved; it never
  /// waits for the network (NFR1). [fix] is the last known location, if any.
  Future<SosRequest> send({LocationFix? fix});

  /// Adds optional details to an SOS that was already sent (R2).
  Future<void> addDetails(String clientId, SosDetails details);
}

/// Records made on this phone that the server has not confirmed yet (S6).
/// They are sent in the order they were captured and keep their original
/// capture time (NFR1, FR13).
abstract interface class OfflineQueue {
  /// Pending records, oldest capture first.
  Stream<List<QueuedRecord>> watchPending();

  /// Emits each record once the server confirms it, so the app can say
  /// "Your SOS from 3:42 PM was delivered".
  Stream<QueuedRecord> deliveries();

  /// Tries to send everything pending now.
  Future<void> retryNow();

  /// Removes a record the server rejected.
  Future<void> remove(String id);
}
