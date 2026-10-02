import '../models/account.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/assignment.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
import '../models/incident.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/settings.dart';
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

  /// A value outside what the rule allows (for example a setting's range).
  invalidValue,

  /// The thing to change does not exist (for example an unknown setting).
  notFound,

  /// Another record already uses that name (for example a call sign).
  alreadyExists,

  /// An admin cannot deactivate, demote, or reset their own account here.
  ownAccount,

  /// The last active admin cannot be deactivated or demoted.
  lastAdmin,
}

abstract interface class AuthRepository {
  Stream<AppUser?> watchUser();
  AppUser? get currentUser;
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signOut();
}

/// D11 and G2: a staff member's own password and session (dashboard).
abstract interface class StaffSessionRepository {
  /// Minimum length for a new password.
  static const minPasswordLength = 8;

  /// Checks [current], then sets [next]. Throws [AuthException] with
  /// `wrongCredentials` for a wrong current password, [ActionRejected] with
  /// `invalidValue` for a new password that is too short.
  Future<void> changePassword({required String current, required String next});

  /// Emits when the session ends without the person signing out (G2), for
  /// example when it could not be refreshed.
  Stream<void> watchExpired();
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
  /// suggestion (FR3 manual override), and the unit's road [route] when
  /// Dijkstra found one (kept on the dispatch record for the responder).
  Future<void> assignUnit(
    String incidentId,
    String unitId, {
    String? overrideReason,
    RoadRoute? route,
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

/// A1 Accounts (admins only). Every change is audited.
abstract interface class AccountRepository {
  /// Every staff account: admins, dispatchers, and responders.
  Stream<List<StaffAccount>> watchStaff();

  /// Every resident account (numbers masked).
  Stream<List<Resident>> watchResidents();

  /// Creates a login; the temporary password is shown to the admin once.
  Future<({String id, String temporaryPassword})> createStaff({
    required String email,
    required String displayName,
    required UserRole role,
    String? unitId,
  });

  Future<void> updateStaff(
    String id, {
    required String displayName,
    required UserRole role,
  });

  Future<void> setStaffActive(String id, {required bool active});

  /// Returns the new temporary password.
  Future<String> resetPassword(String id);

  Future<void> setResidentSuspended(
    String residentId, {
    required bool suspended,
  });
}

/// A2 Resources (admins only): units, including retired ones, and the
/// responder roster. Every change is audited.
abstract interface class ResourceRepository {
  Stream<List<ResponseUnit>> watchUnits();
  Stream<List<StaffAccount>> watchResponders();

  /// Adds a unit ([id] null) or edits one; returns the unit id.
  Future<String> saveUnit({
    String? id,
    required String callSign,
    required UnitType type,
    required String station,
    required int crewSize,
  });

  /// Only a free unit (no job, Available); its responders come off it.
  Future<void> retireUnit(String id);
  Future<void> restoreUnit(String id);

  /// Puts a responder on a unit, or takes them off ([unitId] null).
  Future<void> setResponderUnit(String staffId, String? unitId);
}

/// A4 Performance analytics (admins only).
abstract interface class AnalyticsRepository {
  /// Incidents received in [from, to). Throws [ActionRejected].
  Future<AnalyticsReport> report(DateTime from, DateTime to);
}

/// A3 Configuration: values an administrator can change (`app_setting`).
abstract interface class SettingsRepository {
  /// Every setting, sorted by key, live.
  Stream<List<AppSetting>> watch();

  /// Admins only; each change is audited. [value] is a number, a switch
  /// (`bool`), or text, the same type the setting already has. Throws
  /// [ActionRejected] with `invalidValue` for a value the setting's rule
  /// refuses.
  Future<void> set(String key, Object value);
}

/// D10: alerts with what happened to them on each channel (dispatchers and
/// admins).
abstract interface class AlertLogRepository {
  /// Newest first.
  Stream<List<SentAlert>> watchRecent({int limit});
}

/// Simulation mode (A3, plan section 12): a simulated PAGASA reading for
/// demos and UAT. Admins only, only while simulation mode is on, audited.
/// The threshold engine treats it like any reading; the alerts it raises
/// are marked simulated and are never texted or posted.
abstract interface class SimulationRepository {
  Future<void> simulateWeather({
    required int signal,
    required double rainfallMmPerHour,
    double? surgeMeters,
  });
}

/// The hotline and the SMS gateway number an administrator set on A3,
/// readable before sign-in.
abstract interface class ClientConfigRepository {
  /// Throws when the server cannot be reached; callers keep what they had.
  Future<ClientConfig> fetch();
}

/// A fixed [ClientConfig]: sample data, tests, and builds with no server.
class StaticClientConfigRepository implements ClientConfigRepository {
  const StaticClientConfigRepository([this.config = const ClientConfig()]);

  final ClientConfig config;

  @override
  Future<ClientConfig> fetch() async => config;
}

/// The Dijkstra timing log for Chapter 4 (plan 10.2). Logging never throws
/// and never delays the caller: a lost timing row must not block dispatch.
abstract interface class RoutingLogRepository {
  void log(RoutingRun run);
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

/// Hazard reports the resident sends (R4). Saved on the phone first and
/// sent over the internet only; SMS is kept for SOS.
abstract interface class HazardReportRepository {
  /// This resident's reports, newest first.
  Stream<List<HazardReport>> watchMine();

  /// Checks the report on the phone (not empty, has a location, inside
  /// Manila, under the rate limit), saves it, and starts sending it.
  /// Throws [ReportRejected] when a check fails.
  Future<HazardReport> submit({
    required String description,
    IncidentType? type,
    LocationFix? fix,
  });
}

/// Hazard reports from the resident web form (W2, W3; FR15). Online only:
/// nothing is queued, so the page keeps the draft and the id to send again.
/// The web form never sends an SOS.
abstract interface class WebReportRepository {
  /// This account's reports from the app and the web form, newest first.
  Stream<List<HazardReport>> watchMine();

  /// How many reports the account may still send this hour.
  Stream<ReportQuota> watchQuota();

  /// Sends a report and returns it as the server stored it. [clientId]
  /// ([newClientId]) stays the same when the page sends a draft again after
  /// a lost connection, so the server stores it once. Throws
  /// [ReportRejected] for the FR15 checks and [ActionRejected] with
  /// `offline` when the server cannot be reached.
  Future<HazardReport> submit({
    required String clientId,
    required DateTime capturedAt,
    required String description,
    required GeoPoint location,
    IncidentType? type,
    double? accuracyMeters,
    Barangay? barangay,
  });
}

/// The responder's unit, assignment, and status (F1 to F6). Status updates
/// and completion reports are saved on the phone first and sent over the
/// internet in capture order.
abstract interface class ResponderRepository {
  Stream<ResponderState> watch();

  /// Accepts the offered assignment: the unit goes En route and the map
  /// around the route starts saving for offline use (F2).
  Future<void> accept(String incidentId);

  /// Changes the unit's status from the F1 control. Throws [StatusRejected]
  /// for moves that make no sense, such as On scene with no assignment.
  Future<void> setStatus(UnitStatus status);

  /// Arrived at the scene (F4 "Arrived", F3 "Mark on scene").
  Future<void> arrive();

  /// The on-scene check (F5, FR8).
  Future<void> confirmOnScene({
    required bool realEmergency,
    String? reason,
    int? peopleFound,
  });

  /// Files the completion report (F6); the unit becomes Available again.
  Future<void> complete({
    required RescueOutcome outcome,
    required int personsAssisted,
    int housesDamaged = 0,
    int injured = 0,
    int missing = 0,
    int affectedFamilies = 0,
    String? notes,
  });

  /// Assignments this unit finished, newest first, with whether each
  /// completion report has reached the server (F7).
  Stream<List<CompletedAssignment>> watchHistory();
}

/// Resident sign-in by mobile number and a code sent by SMS (S3 to S5).
/// Staff use [AuthRepository.signIn] with email and password.
abstract interface class ResidentAccountRepository {
  /// Sends a sign-in code to a registered number. Throws
  /// [PhoneAuthException].
  Future<void> sendCode(String phone);

  /// Checks the code and signs the resident in.
  Future<AppUser> verifyCode({required String phone, required String code});

  /// Creates an account and sends the first code. Throws
  /// [PhoneAuthException] (for example, the number is already registered).
  Future<void> register({
    required String fullName,
    required String phone,
    required Barangay barangay,
  });

  /// Asks MDRRMD to delete the resident's personal data (NFR4, RA 10173).
  Future<void> requestDataDeletion();
}

/// The resident's Vulnerable Resident Priority List entry (R9 to R11).
/// Reading goes through [ResidentRepository.watchResident]. Every change
/// needs the internet; nothing here is queued on the phone.
abstract interface class VulnerabilityRepository {
  /// Records Data Privacy Act consent (R10, NFR4). Throws [ActionRejected].
  Future<void> giveConsent();

  /// Withdraws consent and deletes the household list, since no profile
  /// may be kept without consent.
  Future<void> withdrawConsent();

  /// Adds a member (no id) or updates one. Throws [ActionRejected], for
  /// example without consent or offline.
  Future<void> saveMember(VulnerableMember member);

  Future<void> removeMember(String memberId);
}

/// Alerts for Manila and the 72-hour forecast for the resident's barangay
/// (R7, R8). The phone keeps the last copy for offline reading.
abstract interface class AlertRepository {
  Stream<AlertFeed> watch();

  /// Asks the server for anything new (pull to refresh). Throws
  /// [ActionRejected] when offline; the saved copy stays.
  Future<void> refresh();

  Future<void> markRead(String alertId);
}

/// The phone's permissions (S2, S7).
abstract interface class PermissionService {
  Stream<Map<AppPermission, PermissionState>> watch();
  Future<PermissionState> request(AppPermission permission);
  Future<void> openSettings();
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
