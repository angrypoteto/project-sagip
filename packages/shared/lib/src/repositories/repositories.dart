import 'dart:typed_data';

import '../algorithms/dijkstra/hazard_penalty.dart';
import '../models/account.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/assignment.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/facebook_post.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
import '../models/incident.dart';
import '../models/incident_history.dart';
import '../models/ndrrmc.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/photo.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/safe_place.dart';
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

  /// A final NDRRMC report cannot be changed.
  alreadyFinal,

  /// The service behind the action has no key yet (the language model).
  notSetUp,

  /// Asked too often; try again later.
  rateLimited,

  /// The service answered, but not with something usable.
  failed,
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

  /// Closes an SOS the resident asked to cancel (D4). Refused with
  /// [ActionRejection.invalidValue] when the resident did not ask.
  Future<void> confirmCancel(String incidentId);

  /// What the resident who sent this SOS was told about it, and whether
  /// each text and push went out (FR6), oldest first. Empty for crowd
  /// clusters and for an SOS no unit has been sent to yet.
  Stream<List<ResidentNotice>> watchNotices(String incidentId);

  /// The incident's post on the MDRRMD Facebook Page, or null when it has
  /// none (yet).
  Stream<IncidentPost?> watchFacebookPost(String incidentId);

  /// The photos on an incident: its SOS's and those of the crowd reports in
  /// its cluster, oldest first (2026-10-19).
  Stream<List<IncidentPhoto>> watchPhotos(String incidentId);

  /// Incidents closed between [from] and [to], newest first, with what
  /// their units reported (the history page). At most [limit].
  Stream<List<ClosedIncident>> watchHistory({
    required DateTime from,
    required DateTime to,
    int limit = 1000,
  });
}

abstract interface class UnitRepository {
  Stream<List<ResponseUnit>> watchAll();

  /// Every unit's supplies as their crews last reported them (D7).
  Stream<List<UnitSupply>> watchSupplies();
}

/// A responder's own unit on the web: what it carries, reported by its
/// crew. Only responders use it, and only for the unit they are on.
abstract interface class UnitInventoryRepository {
  /// The unit this responder is on; null when on none.
  Stream<ResponseUnit?> watchMyUnit();

  /// That unit's supplies.
  Stream<List<UnitSupply>> watchMine();

  /// Reports one supply. Fuel and tank water: [quantity] is a percent, 0
  /// to 100. A stock: [quantity] on board, whole, with [capacity] (a full
  /// load) the first time. Throws [ActionRejected]: `invalidValue`,
  /// `notAllowed` (not a responder, or on no unit), `offline`.
  Future<void> setSupply(SupplyItem item, num quantity, {num? capacity});
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

/// The PAGASA feed's health (D10): one row per source; empty when the
/// feed is not connected (sample data).
abstract interface class FeedStatusRepository {
  Stream<List<FeedStatus>> watchFeeds();

  /// PHIVOLCS earthquakes near Manila from the last 48 hours, newest first.
  Stream<List<Earthquake>> watchEarthquakes();

  /// The newest water level of each river station.
  Stream<List<RiverLevel>> watchRiverLevels();
}

/// The 72-hour forecast for every barangay (D8, FR4).
abstract interface class ForecastRepository {
  /// The latest run of the model, or null when none has been generated.
  Stream<ForecastRun?> watchLatest();
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

  /// Sets where a unit's station is on the map, or clears it ([home]
  /// null).
  Future<void> setUnitHome(String id, GeoPoint? home);

  /// Only a free unit (no job, Available); its responders come off it.
  Future<void> retireUnit(String id);
  Future<void> restoreUnit(String id);

  /// Puts a responder on a unit, or takes them off ([unitId] null).
  Future<void> setResponderUnit(String staffId, String? unitId);
}

/// Safe places (Joshua, 2026-10-19): the nearest place that suits the
/// emergency, for residents; the list on the dashboard's map and A2, where
/// admins hide wrong places and add MDRRMD's evacuation centers (audited).
abstract interface class SafePlaceRepository {
  /// Every place; hidden ones too for dispatchers and admins.
  Stream<List<SafePlace>> watchPlaces();

  /// The nearest places that suit [need] from [from], nearest first. Never
  /// throws for lack of a connection: offline, the phone's bundled list is
  /// used (without the server's knowledge of confirmed floods and fires).
  Future<List<SafePlaceOption>> nearest(
    GeoPoint from,
    IncidentType need, {
    int limit = SafePlaceRules.defaultLimit,
  });

  /// Adds a place ([id] null) or edits one; returns its id. Admins only.
  Future<String> savePlace({
    String? id,
    String? name,
    required SafePlaceKind kind,
    required GeoPoint location,
    required bool official,
  });

  /// Hides a wrong place, or shows it again. Admins only.
  Future<void> setHidden(String id, bool hidden);
}

/// A4 Performance analytics (admins only).
abstract interface class AnalyticsRepository {
  /// Incidents received in [from, to). Throws [ActionRejected].
  Future<AnalyticsReport> report(DateTime from, DateTime to);
}

/// A5 and A6: NDRRMC reports (Objective 4). Admins only.
abstract interface class ReportRepository {
  /// Every report, newest first, live.
  Stream<List<NdrrmcReport>> watchReports();

  /// The figures for incidents received in [from, to). Throws
  /// [ActionRejected].
  Future<ReportSource> source(DateTime from, DateTime to);

  /// Saves a new draft ([id] null) for a period, or the edited text of an
  /// existing draft. A new draft keeps the period's figures as they are at
  /// that moment. Returns the report's id. Throws [ActionRejected]:
  /// `alreadyFinal` for a final report, `invalidValue` for text outside
  /// the limits in `ReportSections`.
  Future<String> save({
    String? id,
    required DateTime from,
    required DateTime to,
    required String title,
    required List<ReportSection> sections,
    int? generationMs,
    ReportMethod? method,
  });

  /// Asks the language model to rewrite [sections] from [source] and the
  /// reference passages (RAG, plan 10.6). Nothing is saved: the
  /// administrator reviews the text first. Only figures are sent, never
  /// personal details. Throws [ActionRejected]: `notSetUp` without a key,
  /// `rateLimited`, `failed`.
  Future<ReportRewrite> rewrite({
    required ReportSource source,
    required List<ReportSection> sections,
  });

  /// Marks a draft final; it can no longer be edited. Audited.
  Future<void> finalize(String id);

  /// Keeps a final report's PDF in private storage (plan 10.6), once; a
  /// second call leaves the first copy. Throws [ActionRejected]:
  /// `invalidValue` for a draft.
  Future<void> storePdf(String id, Uint8List bytes);

  /// The stored PDF of a final report. Throws [ActionRejected] `notFound`
  /// when none is stored.
  Future<Uint8List> storedPdf(String id);
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

  /// Issues an advisory for residents (FR6, FR14): an MDRRMD notice, or one
  /// relayed by hand from PAGASA, PHIVOLCS, or EFCOS. It appears in the
  /// apps at once and is queued on each channel that is switched on; while
  /// simulation mode is on it is marked simulated and never texted or
  /// posted. An empty [barangays] means all of Manila. Returns the alert's
  /// id. Audited. Throws [ActionRejected].
  Future<String> issue({
    required AlertSource source,
    required AlertLevel level,
    required String title,
    required String body,
    List<String> guidance,
    List<String> barangays,
  });

  /// Ends an alert that is still showing, so the apps stop showing it.
  /// Audited.
  Future<void> end(String alertId);
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

  /// A simulated SOS near the centre of [barangay], on the board at once as
  /// Pending Verification, from an unknown sender; [vulnerable] adds a
  /// senior citizen. Returns the incident id. Audited.
  Future<String> simulateSos({required String barangay, bool vulnerable});

  /// [count] simulated crowd reports (1 to 5) of [type] within about 20 m
  /// of each other in [barangay]; three or more become a confirmed incident
  /// through DBSCAN (FR7). Audited.
  Future<void> simulateCrowdReports({
    required String barangay,
    required IncidentType type,
    int count,
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

/// The newest mobile app build on the download site (Joshua, 2026-10-19),
/// so an older app can say a newer one is out.
abstract interface class LatestBuildRepository {
  /// Null when it cannot be known (no internet, no file); never throws.
  Future<int?> fetch();
}

/// A fixed newest build: sample data, tests, and builds with no server.
class StaticLatestBuildRepository implements LatestBuildRepository {
  const StaticLatestBuildRepository([this.build]);

  final int? build;

  @override
  Future<int?> fetch() async => build;
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

  /// Asks MDRRMD to cancel an SOS they already have (R2). The SOS stays
  /// open until a dispatcher closes it. Needs internet: throws
  /// [ActionRejected] with [ActionRejection.offline] without it.
  Future<void> requestCancel(
    String clientId,
    SosCancelReason reason, {
    String? note,
  });

  /// Takes a cancel request back: "I still need help" (R2).
  Future<void> withdrawCancel(String clientId);

  /// Tells MDRRMD where the phone is now, while the SOS is open. Best
  /// effort: nothing is queued, and a failure is not an error.
  Future<void> updateLocation(String clientId, LocationFix fix);

  /// Adds a photo to an SOS that was already sent (2026-10-19). Saved on
  /// the phone and sent after the SOS (after every other record), over the
  /// internet only. [jpeg] is ready to send ([preparePhoto]).
  Future<void> addPhoto(String clientId, Uint8List jpeg);

  /// How many photos this phone has added to the SOS (sent or waiting).
  Stream<int> watchPhotoCount(String clientId);
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

  /// Adds a photo to a report already saved ([submit] first): sent after
  /// it, over the internet only.
  Future<void> addPhoto(String clientId, Uint8List jpeg);
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

  /// Adds a photo to a report the server already has (online only).
  /// Throws like [submit].
  Future<void> addPhoto(String clientId, Uint8List jpeg);
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

  /// The confirmed floods and fires this unit's route should go around:
  /// where and which, nothing about who reported them. Never the unit's own
  /// incident. Offline it is the last list the phone was given.
  Stream<List<HazardZone>> watchRoadHazards();
}

/// Resident sign-in by mobile number and a code sent by SMS (S3 to S5).
/// Staff use [AuthRepository.signIn] with email and password.
abstract interface class ResidentAccountRepository {
  /// Sends a sign-in code to a registered number. A number with no account
  /// gets no text: [PhoneAuthFailure.notRegistered]. Throws
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

  /// The resident has seen a rescue confirmation (FR6).
  Future<void> markConfirmationRead(String confirmationId);
}

/// Saves the map around a job on the phone, so the responder can still see
/// it with no signal (FR13: map tiles are downloaded at dispatch time).
abstract interface class MapSaver {
  /// Saves the map along [path] (the route, or the unit and the incident).
  /// Emits the share saved so far, from 0 to 1, and closes when done. Tiles
  /// already saved are not fetched again. Errors end the stream early; the
  /// last share saved stays.
  Stream<double> save(List<GeoPoint> path);
}

/// The assignment alert tone (F2): the app's own two-tone sound, the same
/// as the "New assignments" notifications.
abstract interface class AlertSound {
  Future<void> playAssignment();
}

/// The phone notification that says how a waiting SOS is being sent (data,
/// then SMS, then Bluetooth; Joshua, 2026-10-19). One notification, changed
/// in place; the app shows it again only when the step changes.
abstract interface class SosSendNotice {
  /// [done] once the SOS is delivered: it can then be swiped away.
  Future<void> show({
    required String title,
    required String text,
    bool done = false,
  });

  Future<void> clear();
}

/// Reads text aloud (the responder's spoken directions on F4).
abstract interface class Speaker {
  /// Says [text], cutting off anything still being said.
  Future<void> say(String text);

  Future<void> stop();
}

/// Android's battery saver may stop an app in the background, which would
/// stop a responder's phone sharing the unit's position (FR9). The app asks
/// to be left running.
abstract interface class BatteryOptimization {
  /// True when the app may run in the background, or the phone has no such
  /// setting.
  Future<bool> isExempt();

  /// Shows the phone's own question. Check [isExempt] again afterwards: the
  /// person may say no.
  Future<void> requestExemption();
}

/// Turning Bluetooth on from the app (2026-10-20): airplane mode turns it
/// off, and an app may not switch it back by itself, but it may show the
/// phone's own one-tap question.
abstract interface class BluetoothSwitch {
  /// Shows the phone's "Turn on Bluetooth?" question (nothing when it is
  /// already on). False when it could not be shown.
  Future<bool> requestOn();
}

/// Keeps the screen on (Joshua, 2026-10-20): while an SOS is still on the
/// phone, a screen that goes dark can let the phone (Xiaomi's HyperOS, for
/// one) hold back Bluetooth and the network, so R2 keeps it lit until the
/// SOS reaches MDRRMD.
abstract interface class ScreenAwake {
  Future<void> keepOn(bool on);
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

  /// The SOS [id] as its Tier 2 text (SAGIP1 format), for the resident to
  /// send from the phone's own messages app when the app may not text.
  /// Null for anything that is not a waiting SOS.
  Future<String?> sosSmsText(String id);
}

/// Opens the phone's messages app with a text ready to send (S6): the
/// fallback when the SMS permission was refused. The person presses send
/// there, so the app never knows whether it went.
abstract interface class SmsComposer {
  /// False when no messages app could be opened.
  Future<bool> compose(String number, String text);
}
