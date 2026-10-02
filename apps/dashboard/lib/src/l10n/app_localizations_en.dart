// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'S.A.G.I.P. Command';

  @override
  String get brandName => 'S.A.G.I.P.';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get open => 'Open';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get loadFailed => 'Couldn\'t load this data.';

  @override
  String get signInTitle => 'Sign in to the command board';

  @override
  String get signInSubtitle => 'For MDRRMD dispatchers and administrators.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInButton => 'Sign in';

  @override
  String get signingIn => 'Signing in';

  @override
  String get fieldRequired => 'Required';

  @override
  String get signInWrongCredentials => 'Email or password is incorrect.';

  @override
  String get signInDisabled =>
      'This account is turned off. Ask an administrator.';

  @override
  String get signInNotStaff => 'This account can\'t use the command board.';

  @override
  String get signInOffline => 'You\'re offline. Reconnect to sign in.';

  @override
  String get forgotPassword => 'Forgot your password? Ask an administrator.';

  @override
  String demoAccountsHint(String password) {
    return 'Demo accounts: dispatcher@sagip.test or admin@sagip.test. Password: $password';
  }

  @override
  String get navCommandBoard => 'Command Board';

  @override
  String get navCrowdReports => 'Crowd reports';

  @override
  String get navUnits => 'Units';

  @override
  String get navForecast => 'Forecast';

  @override
  String get navVulnerable => 'Vulnerable residents';

  @override
  String get navWeather => 'Weather and advisories';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navReports => 'NDRRMC reports';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navResources => 'Resources';

  @override
  String get navSettings => 'Configuration';

  @override
  String get navAuditLog => 'Audit log';

  @override
  String signalLevel(int level) {
    return 'Signal No. $level';
  }

  @override
  String get noSignal => 'No signal raised';

  @override
  String rainfall(String value) {
    return 'Rainfall $value mm/hr';
  }

  @override
  String pagasaAt(String time) {
    return 'PAGASA, $time';
  }

  @override
  String get simulatedFeed => 'Simulated feed';

  @override
  String get linkLive => 'Live';

  @override
  String get linkReconnecting => 'Reconnecting';

  @override
  String get linkOffline => 'Offline';

  @override
  String get roleResident => 'Resident';

  @override
  String get roleResponder => 'Responder';

  @override
  String get roleDispatcher => 'Dispatcher';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleSystem => 'System';

  @override
  String userWithRole(String name, String role) {
    return '$name, $role';
  }

  @override
  String get switchToLight => 'Switch to light theme';

  @override
  String get switchToDark => 'Switch to dark theme';

  @override
  String get signOut => 'Sign out';

  @override
  String get demoConnection => 'Demo: connection';

  @override
  String get demoGoOffline => 'Simulate going offline';

  @override
  String get demoReconnecting => 'Simulate reconnecting';

  @override
  String get demoGoLive => 'Back online';

  @override
  String offlineBanner(String time) {
    return 'You\'re offline. Showing data from $time. Actions are off until you reconnect.';
  }

  @override
  String get reconnectingBanner => 'Live updates paused. Reconnecting.';

  @override
  String get offlineActionsDisabled => 'Reconnect to take actions.';

  @override
  String get queueTitle => 'Triage queue';

  @override
  String queueCount(int count) {
    return '$count active, by priority';
  }

  @override
  String filterAll(int count) {
    return 'All $count';
  }

  @override
  String filterPending(int count) {
    return 'Pending $count';
  }

  @override
  String filterSos(int count) {
    return 'SOS $count';
  }

  @override
  String filterReports(int count) {
    return 'Reports $count';
  }

  @override
  String get queueEmpty => 'No active incidents';

  @override
  String get queueEmptyMessage => 'New reports will appear here.';

  @override
  String get queueFilterEmpty => 'Nothing matches this filter.';

  @override
  String get sosTitle => 'SOS';

  @override
  String sosWithType(String type) {
    return 'SOS, $type';
  }

  @override
  String clusterTitle(String type, int count) {
    return '$type, $count reports';
  }

  @override
  String clusterUntyped(int count) {
    return 'Hazard, $count reports';
  }

  @override
  String get mockLocationWarning => 'Location may be faked';

  @override
  String statusWithUnit(String status, String unit) {
    return '$status $unit';
  }

  @override
  String get statusPendingShort => 'Pending';

  @override
  String get channelApp => 'App';

  @override
  String get channelSms => 'SMS';

  @override
  String get channelBle => 'Nearby phones';

  @override
  String get channelWeb => 'Web form';

  @override
  String get statusPendingVerification => 'Pending verification';

  @override
  String get statusUnverified => 'Unverified';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusAssigned => 'Assigned';

  @override
  String get statusEnRoute => 'En route';

  @override
  String get statusOnScene => 'On scene';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get typeFlood => 'Flood';

  @override
  String get typeFire => 'Fire';

  @override
  String get typeMedical => 'Medical';

  @override
  String get typeStructural => 'Structural';

  @override
  String get vulnSenior => 'Senior citizen';

  @override
  String get vulnPwd => 'Person with disability';

  @override
  String get vulnPregnant => 'Pregnant';

  @override
  String get vulnOther => 'Other';

  @override
  String get unitAmbulance => 'Ambulance';

  @override
  String get unitRescueBoat => 'Rescue boat';

  @override
  String get unitRescueTeam => 'Rescue team';

  @override
  String get unitAvailable => 'Available';

  @override
  String get unitEnRoute => 'En route';

  @override
  String get unitOnScene => 'On scene';

  @override
  String get viewMap => 'Map';

  @override
  String get viewList => 'List';

  @override
  String get layersTitle => 'Layers';

  @override
  String get layerUnits => 'Units';

  @override
  String get layerReports => 'Crowd reports';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get mapAttribution => 'OpenStreetMap contributors';

  @override
  String get legendPending => 'Pending verification';

  @override
  String get legendConfirmed => 'Confirmed';

  @override
  String get legendAssigned => 'Assigned';

  @override
  String get legendEnRoute => 'En route';

  @override
  String get legendOnScene => 'On scene';

  @override
  String get legendUnverified => 'Unverified report';

  @override
  String get legendUnitAvailable => 'Unit available';

  @override
  String get legendUnitBusy => 'Unit busy';

  @override
  String get newSosTitle => 'New SOS';

  @override
  String newSosBody(String place, String ago) {
    return '$place, $ago';
  }

  @override
  String get colPriority => 'Priority';

  @override
  String get colWaiting => 'Waiting';

  @override
  String get colStatus => 'Status';

  @override
  String get colType => 'Type';

  @override
  String get colPlace => 'Barangay';

  @override
  String get colChannel => 'Channel';

  @override
  String get colVerified => 'Verified';

  @override
  String get colVulnerable => 'Vulnerable';

  @override
  String get colUnit => 'Unit';

  @override
  String get severityCritical => 'Critical';

  @override
  String get severityHigh => 'High';

  @override
  String get severityNormal => 'Normal';

  @override
  String drawerIncidentId(String id) {
    return 'Incident $id';
  }

  @override
  String waitingFor(String duration) {
    return 'Waiting $duration';
  }

  @override
  String rankOf(int rank, int total) {
    return 'Rank $rank of $total';
  }

  @override
  String locationDetail(String coordinates, String source, int meters) {
    return '$coordinates, from $source, accurate to $meters m';
  }

  @override
  String locationDetailNoAccuracy(String coordinates, String source) {
    return '$coordinates, from $source';
  }

  @override
  String locationSource(String channel) {
    String _temp0 = intl.Intl.selectLogic(channel, {
      'app': 'the app',
      'sms': 'SMS',
      'bleRelay': 'nearby phones',
      'webForm': 'the web form',
      'other': 'an unknown source',
    });
    return '$_temp0';
  }

  @override
  String get incidentTypeLabel => 'Incident type';

  @override
  String typeSuggested(String type) {
    return '$type (suggested)';
  }

  @override
  String get typeNotSet => 'Not set';

  @override
  String get confirmType => 'Confirm type';

  @override
  String typeConfirmedSnack(String type) {
    return 'Type set to $type';
  }

  @override
  String get verificationTitle => 'Verification';

  @override
  String get checkAccountVerified =>
      'Registered account, verified mobile number';

  @override
  String get checkAccountNotVerified => 'Account not verified';

  @override
  String get checkGpsOk => 'Location from phone GPS, not a mock location';

  @override
  String get checkGpsMock =>
      'The phone reported a mock location. Confirm by call before dispatching.';

  @override
  String get checkNotVerified => 'Not yet confirmed by call or SMS';

  @override
  String checkVerifiedBy(String method) {
    return 'Confirmed by $method';
  }

  @override
  String get methodCallback => 'callback';

  @override
  String get methodSmsReply => 'SMS reply';

  @override
  String get methodOnScene => 'responders on scene';

  @override
  String get checkClusterVerified =>
      'Confirmed by 3 or more reports within 50 m';

  @override
  String get smsCheckPending => 'SMS check sent. Waiting for a reply.';

  @override
  String get smsReplyReceived => 'The resident replied YES to the SMS check.';

  @override
  String get callResident => 'Call resident';

  @override
  String get sendSmsCheck => 'Send SMS check';

  @override
  String get smsCheckSentSnack => 'SMS check sent';

  @override
  String get markVerified => 'Mark verified';

  @override
  String get verifiedSnack => 'SOS verified';

  @override
  String get markFalse => 'Mark as false report';

  @override
  String get residentTitle => 'Resident';

  @override
  String get showNumber => 'Show number';

  @override
  String peopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get residentNote => 'Note from the resident';

  @override
  String get clusterReportsTitle => 'Reports in this cluster';

  @override
  String get priorityTitle => 'Why it\'s ranked here';

  @override
  String get factorSos => 'SOS';

  @override
  String get factorCluster => 'Confirmed cluster';

  @override
  String get factorVulnerable => 'Vulnerable household';

  @override
  String get factorWaiting => 'Waiting time';

  @override
  String get factorMockLocation => 'Possible mock location';

  @override
  String get provisionalRules =>
      'Provisional weights until MDRRMD\'s triage SOP is added.';

  @override
  String points(int points) {
    String _temp0 = intl.Intl.pluralLogic(
      points,
      locale: localeName,
      other: '$points pts',
      one: '1 pt',
    );
    return '$_temp0';
  }

  @override
  String get suggestedUnitsTitle => 'Suggested units';

  @override
  String get suggestedByRoad =>
      'Available units, by travel time on the road network';

  @override
  String get suggestedByDistance =>
      'Available units, estimated by straight-line distance';

  @override
  String get chooseAnotherUnit => 'Choose another unit';

  @override
  String get noAvailableUnits => 'No available units';

  @override
  String get noAvailableUnitsMessage =>
      'Choose another unit or wait for one to become available.';

  @override
  String etaMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String distanceKm(String km) {
    return '$km km';
  }

  @override
  String assignUnit(String unit) {
    return 'Assign $unit';
  }

  @override
  String reassignUnit(String unit) {
    return 'Reassign to $unit';
  }

  @override
  String assignedSnack(String unit) {
    return '$unit assigned';
  }

  @override
  String get assignedUnitTitle => 'Assigned unit';

  @override
  String get markResolved => 'Mark resolved';

  @override
  String get resolvedSnack => 'Incident resolved';

  @override
  String unitStationCrew(String station, int crew) {
    return '$station, crew of $crew';
  }

  @override
  String get timelineTitle => 'Timeline';

  @override
  String get eventReceived => 'Received';

  @override
  String get eventSmsCheckSent => 'SMS check sent';

  @override
  String get eventSmsReply => 'SMS reply received';

  @override
  String get eventVerified => 'Verified';

  @override
  String get eventTypeConfirmed => 'Type confirmed';

  @override
  String get eventAssigned => 'Assigned';

  @override
  String get eventEnRoute => 'En route';

  @override
  String get eventOnScene => 'On scene';

  @override
  String get eventResolved => 'Resolved';

  @override
  String get eventFalseReport => 'Marked as false report';

  @override
  String get incidentClosed => 'This incident was closed.';

  @override
  String overrideTitle(String unit) {
    return 'Assign $unit instead of the top suggestion?';
  }

  @override
  String overrideBody(String top, int minutes) {
    return '$top is about $minutes min closer. You can still choose another unit. Add a reason so the audit log explains the choice.';
  }

  @override
  String get overrideReasonLabel => 'Reason (required)';

  @override
  String get reasonEquipment => 'Top unit lacks the needed equipment';

  @override
  String get reasonBusy => 'Top unit is handling another call';

  @override
  String get reasonBlocked => 'Known road blockage on the suggested route';

  @override
  String get reasonOther => 'Other';

  @override
  String get overrideNoteLabel => 'Note (optional)';

  @override
  String get overrideReasonMissing => 'Choose a reason.';

  @override
  String get chooseUnitTitle => 'Choose a unit';

  @override
  String get chooseUnitBody => 'Units that are available now, nearest first.';

  @override
  String get falseReportTitle => 'Mark as a false report?';

  @override
  String get falseReportBody =>
      'It leaves the queue, and any assigned unit becomes available. This is recorded in the audit log.';

  @override
  String get falseReportDone => 'Marked as a false report';

  @override
  String callTitle(String name) {
    return 'Call $name';
  }

  @override
  String get callBody =>
      'Call this number from the command center phone. Viewing it is recorded in the audit log.';

  @override
  String get copyNumber => 'Copy number';

  @override
  String get copiedSnack => 'Number copied';

  @override
  String get errorOffline => 'You\'re offline. Reconnect and try again.';

  @override
  String get errorUnitTaken =>
      'That unit is no longer available. Choose another.';

  @override
  String get errorAlreadyAssigned => 'This incident already has that unit.';

  @override
  String get errorIncidentClosed => 'This incident was already closed.';

  @override
  String get errorNotAllowed => 'Your account can\'t do this.';

  @override
  String get errorInvalidValue => 'That value is outside the allowed range.';

  @override
  String get errorNotFound => 'That item no longer exists. Reload the page.';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get crowdReportsTitle => 'Crowd reports';

  @override
  String get crowdWindow => 'Last 60 minutes';

  @override
  String crowdSummary(int total, int clusters, int singles) {
    return '$total reports: $clusters in confirmed clusters, $singles unverified';
  }

  @override
  String clusterCardTitle(String type, int count) {
    return '$type, $count reports within 50 m';
  }

  @override
  String get clusterInQueue => 'In the triage queue';

  @override
  String get openInQueue => 'Open in triage queue';

  @override
  String get unverifiedSection => 'Unverified, waiting for nearby reports';

  @override
  String reportMeta(String time, String channel, String type, int percent) {
    return '$time, $channel, suggested $type ($percent%)';
  }

  @override
  String get crowdRule =>
      'Three or more reports within 50 m in the last 60 minutes become a confirmed incident. A single report is never confirmed on its own.';

  @override
  String get crowdEmpty => 'No crowd reports in the last 60 minutes.';

  @override
  String get unitsTitle => 'Units';

  @override
  String countAvailable(int count) {
    return '$count available';
  }

  @override
  String countEnRoute(int count) {
    return '$count en route';
  }

  @override
  String countOnScene(int count) {
    return '$count on scene';
  }

  @override
  String get colCallSign => 'Call sign';

  @override
  String get colUnitType => 'Type';

  @override
  String get colStation => 'Station';

  @override
  String get colCrew => 'Crew';

  @override
  String get colIncident => 'Current incident';

  @override
  String get colLastGps => 'Last GPS';

  @override
  String get staleGps => 'Stale';

  @override
  String get unitsEmpty => 'No units set up';

  @override
  String get unitsEmptyMessage =>
      'An administrator can add units in Resources.';

  @override
  String get assignedNotStarted => 'Assigned, waiting for crew';

  @override
  String get vulnerableTitle => 'Vulnerable Resident Priority List';

  @override
  String get vulnerablePrivacy =>
      'Only dispatchers and administrators can see this list (Data Privacy Act, RA 10173).';

  @override
  String get colResident => 'Resident';

  @override
  String get colHousehold => 'Household';

  @override
  String get colConsent => 'Consent given';

  @override
  String get colUpdated => 'Updated';

  @override
  String get colContact => 'Contact';

  @override
  String get vulnerableEmpty => 'No registered vulnerable residents yet.';

  @override
  String get weatherTitle => 'Weather and advisories';

  @override
  String get signalCard => 'Tropical cyclone wind signal';

  @override
  String get rainfallCard => 'Rainfall intensity';

  @override
  String get stormSurgeCard => 'Storm surge';

  @override
  String get noAdvisory => 'No advisory';

  @override
  String issuedAt(String time) {
    return 'Issued $time';
  }

  @override
  String rainfallValue(String value) {
    return '$value mm/hr';
  }

  @override
  String get simulatedWeatherNote =>
      'Replaying recorded data. The live PAGASA feed is not connected yet.';

  @override
  String get efcosTitle => 'EFCOS water levels';

  @override
  String get efcosNotConnected =>
      'Not connected yet. Alerts use PAGASA thresholds only (FR5 fallback).';

  @override
  String get phivolcsTitle => 'PHIVOLCS advisories';

  @override
  String get phivolcsNotConnected =>
      'Not connected yet. Advisories will be relayed to residents as notifications (FR14).';

  @override
  String get auditTitle => 'Audit log';

  @override
  String get auditSubtitle =>
      'Every dispatch action, status change, and verification, with who did it (FR11).';

  @override
  String get colTime => 'Time';

  @override
  String get colAccount => 'Account';

  @override
  String get colAction => 'Action';

  @override
  String get colTarget => 'Record';

  @override
  String get colDetail => 'Detail';

  @override
  String get actionVerified => 'Verified';

  @override
  String get actionFalseReport => 'Marked false report';

  @override
  String get actionTypeConfirmed => 'Confirmed type';

  @override
  String get actionAssigned => 'Assigned unit';

  @override
  String get actionReassigned => 'Reassigned unit';

  @override
  String get actionStatusChanged => 'Changed status';

  @override
  String get actionResolved => 'Resolved';

  @override
  String get actionSmsCheck => 'Sent SMS check';

  @override
  String get actionContactViewed => 'Viewed contact number';

  @override
  String get actionSettingChanged => 'Changed a setting';

  @override
  String get analyticsSubtitle =>
      'Dispatch and response times for incidents received in the period (Objective 1).';

  @override
  String get periodDay => 'Last 24 hours';

  @override
  String get periodWeek => 'Last 7 days';

  @override
  String get periodMonth => 'Last 30 days';

  @override
  String get refresh => 'Refresh';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get analyticsEmpty => 'Not enough data for this period.';

  @override
  String get kpiIncidents => 'Incidents';

  @override
  String kpiIncidentsFooter(int resolved, int falseReports) {
    return '$resolved resolved · $falseReports false reports';
  }

  @override
  String get kpiDispatch => 'Median dispatch time';

  @override
  String kpiDispatchFooter(String average) {
    return 'Received to unit assigned · average $average';
  }

  @override
  String get kpiResponse => 'Median response time';

  @override
  String kpiResponseFooter(String average) {
    return 'Received to on scene · average $average';
  }

  @override
  String get kpiVerify => 'Average verification time';

  @override
  String get kpiVerifyFooter => 'Received to verified';

  @override
  String get kpiSosChannels => 'SOS by channel';

  @override
  String get kpiDijkstra => 'Dijkstra run time';

  @override
  String kpiDijkstraValue(String ms) {
    return '$ms ms';
  }

  @override
  String kpiDijkstraFooter(int runs, String p95) {
    return 'Average of $runs runs · 95th percentile $p95 ms';
  }

  @override
  String get kpiDijkstraNone => 'No timed runs in this period';

  @override
  String channelCount(String channel, int count) {
    return '$channel $count';
  }

  @override
  String get baselineNote =>
      'Objective 1 compares these times with MDRRMD\'s before S.A.G.I.P. Those records have not arrived yet (Table 3.1 item 2).';

  @override
  String get dailyTitle => 'Incidents per day';

  @override
  String dailyAvgResponse(String time) {
    return 'average response $time';
  }

  @override
  String get byTypeTitle => 'By incident type';

  @override
  String get byBarangayTitle => 'Busiest barangays';

  @override
  String get byUnitTitle => 'By unit';

  @override
  String get colBarangay => 'Barangay';

  @override
  String get colIncidents => 'Incidents';

  @override
  String get colJobs => 'Jobs';

  @override
  String get colAvgDispatch => 'Average dispatch';

  @override
  String get colAvgResponse => 'Average response';

  @override
  String get colAvgTravel => 'Average travel';

  @override
  String get noValue => '–';

  @override
  String get myAccount => 'My account';

  @override
  String get demoExpireSession => 'Simulate the session expiring';

  @override
  String get accountSubtitle => 'Your account, display, and password.';

  @override
  String get accountDetails => 'Account';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountRole => 'Role';

  @override
  String get displayTitle => 'Display';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'Same as this computer';

  @override
  String get passwordTitle => 'Change password';

  @override
  String get passwordCurrent => 'Current password';

  @override
  String get passwordNew => 'New password';

  @override
  String get passwordConfirm => 'New password again';

  @override
  String passwordTooShort(int min) {
    return 'Use at least $min characters.';
  }

  @override
  String get passwordMismatch => 'The two new passwords are different.';

  @override
  String get passwordSame =>
      'Choose a password different from the current one.';

  @override
  String get passwordWrong => 'The current password is not right.';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get passwordSave => 'Change password';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutQueue =>
      'Select the next or previous incident in the Triage Queue (opens it)';

  @override
  String get shortcutClose => 'Close the incident drawer';

  @override
  String get shortcutUpDown => 'Up or Down arrow';

  @override
  String get shortcutEsc => 'Esc';

  @override
  String get sessionExpiredTitle => 'Your session expired';

  @override
  String get sessionExpiredMessage =>
      'Sign in again to go back to where you were. Nothing you saved was lost.';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get accountsSubtitle =>
      'Staff logins and resident accounts. Every change is recorded in the audit log.';

  @override
  String get createAccount => 'Create account';

  @override
  String get tabStaff => 'Staff';

  @override
  String get tabResponders => 'Responders';

  @override
  String get tabResidents => 'Residents';

  @override
  String get colName => 'Name';

  @override
  String get colRole => 'Role';

  @override
  String get colNumber => 'Number';

  @override
  String get statusActive => 'Active';

  @override
  String get statusDeactivated => 'Deactivated';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get editAccount => 'Edit account';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get deactivate => 'Deactivate';

  @override
  String get reactivate => 'Reactivate';

  @override
  String get suspend => 'Suspend';

  @override
  String get liftSuspension => 'Lift suspension';

  @override
  String get ownAccountHint => 'This is your account. Change it on My account.';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldRole => 'Role';

  @override
  String get fieldUnitOptional => 'Unit (responders)';

  @override
  String get fieldEmailError => 'Enter an email address like name@example.com.';

  @override
  String get fieldNameError => 'Enter a name.';

  @override
  String get tempPasswordTitle => 'Temporary password';

  @override
  String tempPasswordBody(String name) {
    return 'Give this temporary password to $name. They should change it on My account after signing in. It is not shown again.';
  }

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get done => 'Done';

  @override
  String resetTitle(String name) {
    return 'Reset the password for $name?';
  }

  @override
  String get resetBody =>
      'They are signed out and need the new temporary password to sign in.';

  @override
  String deactivateTitle(String name) {
    return 'Deactivate $name?';
  }

  @override
  String get deactivateBody =>
      'They are signed out at once and cannot sign in until an admin reactivates the account. Their records stay.';

  @override
  String suspendTitle(String name) {
    return 'Suspend $name?';
  }

  @override
  String get suspendBody =>
      'They cannot send crowd reports. An SOS still reaches MDRRMD, marked not account-verified, so a dispatcher calls back.';

  @override
  String accountSaved(String name) {
    return '$name saved';
  }

  @override
  String accountDeactivatedSnack(String name) {
    return '$name deactivated';
  }

  @override
  String accountReactivatedSnack(String name) {
    return '$name reactivated';
  }

  @override
  String residentSuspendedSnack(String name) {
    return '$name suspended';
  }

  @override
  String residentRestoredSnack(String name) {
    return 'Suspension lifted for $name';
  }

  @override
  String get accountsEmpty => 'No accounts yet. Create the first one.';

  @override
  String get residentsEmpty => 'No resident accounts yet.';

  @override
  String get errorOwnAccount =>
      'You cannot do that to your own account here. Use My account.';

  @override
  String get errorLastAdmin => 'At least one admin must stay active.';

  @override
  String get actionAccountCreated => 'Created an account';

  @override
  String get actionAccountUpdated => 'Edited an account';

  @override
  String get actionAccountDeactivated => 'Deactivated an account';

  @override
  String get actionAccountReactivated => 'Reactivated an account';

  @override
  String get actionPasswordReset => 'Reset a password';

  @override
  String get actionResidentSuspended => 'Suspended a resident';

  @override
  String get actionResidentRestored => 'Lifted a suspension';

  @override
  String get resourcesSubtitle =>
      'Units and the responders who crew them. Every change is recorded in the audit log.';

  @override
  String get addUnit => 'Add unit';

  @override
  String get editUnit => 'Edit unit';

  @override
  String get unitsTitleA2 => 'Units';

  @override
  String get rosterTitle => 'Responder roster';

  @override
  String get rosterNote =>
      'A responder works for the unit chosen here. Responder accounts are created in Accounts.';

  @override
  String get rosterEmpty => 'No responder accounts yet.';

  @override
  String get colResponders => 'Responders';

  @override
  String get colEmail => 'Email';

  @override
  String get retire => 'Retire';

  @override
  String get restore => 'Restore';

  @override
  String get edit => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get retiredChip => 'Retired';

  @override
  String retireTitle(String callSign) {
    return 'Retire $callSign?';
  }

  @override
  String get retireBody =>
      'It will not be dispatched and its responders come off it. Its past jobs stay in the records. You can restore it later.';

  @override
  String get retireBusy =>
      'Only a unit that is Available with no job can be retired.';

  @override
  String unitSaved(String callSign) {
    return '$callSign saved';
  }

  @override
  String unitRetiredSnack(String callSign) {
    return '$callSign retired';
  }

  @override
  String unitRestoredSnack(String callSign) {
    return '$callSign restored';
  }

  @override
  String get rosterSaved => 'Roster updated';

  @override
  String get noUnit => 'No unit';

  @override
  String get fieldCallSign => 'Call sign';

  @override
  String get fieldCallSignHint => 'For example R-12';

  @override
  String get fieldCallSignError =>
      'Use letters, numbers, and dashes, up to 12 characters.';

  @override
  String get fieldUnitType => 'Type';

  @override
  String get fieldStation => 'Station';

  @override
  String get fieldStationHint => 'For example Sampaloc station';

  @override
  String get fieldStationError => 'Enter the station.';

  @override
  String get fieldCrew => 'Crew size';

  @override
  String get fieldCrewError => 'Use a number from 1 to 50.';

  @override
  String get errorAlreadyExists => 'Another unit already uses that call sign.';

  @override
  String get actionUnitAdded => 'Added a unit';

  @override
  String get actionUnitEdited => 'Edited a unit';

  @override
  String get actionUnitRetired => 'Retired a unit';

  @override
  String get actionUnitRestored => 'Restored a unit';

  @override
  String get actionRosterChanged => 'Changed the roster';

  @override
  String get configSubtitle =>
      'Changes apply at once for every dispatcher and are recorded in the audit log.';

  @override
  String get configPriorityTitle => 'Triage Queue priority';

  @override
  String get settingSos => 'SOS';

  @override
  String get settingCluster => 'Confirmed cluster of crowd reports';

  @override
  String get settingVulnerable => 'Vulnerable household';

  @override
  String get settingWaitingPerMinute => 'Points per minute of waiting';

  @override
  String get settingWaitingMax => 'Most points for waiting';

  @override
  String get settingMockLocation => 'Possible mock location';

  @override
  String get settingCriticalAt => 'Critical from';

  @override
  String get settingHighAt => 'High from';

  @override
  String settingRange(String min, String max) {
    return '$min to $max';
  }

  @override
  String settingOutOfRange(String min, String max) {
    return 'Use a number from $min to $max.';
  }

  @override
  String get settingNotNumber => 'Enter a number.';

  @override
  String get settingHighAboveCritical => 'High must be at or below Critical.';

  @override
  String settingLastChanged(String name) {
    return 'Last changed by $name';
  }

  @override
  String get saveChanges => 'Save changes';

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get previewTitle => 'Queue with these values';

  @override
  String get previewNote =>
      'Active incidents ranked now with the values above, before you save.';

  @override
  String get previewEmpty => 'No active incidents to rank.';

  @override
  String get algorithmsTitle => 'Algorithm parameters';

  @override
  String get algorithmsNote =>
      'Set in the thesis. Changes need team agreement.';

  @override
  String get algDbscan => 'DBSCAN clustering';

  @override
  String get algDbscanValue =>
      '50 m radius, 3 reports, reports from the last 60 minutes';

  @override
  String get algDijkstra => 'Dijkstra routing';

  @override
  String algDijkstraValue(int nodes, int edges, String date) {
    return '$nodes intersections, $edges road segments, OpenStreetMap data from $date';
  }

  @override
  String get algDijkstraLoading => 'Road graph not loaded yet';

  @override
  String get algSpeeds => 'Road speeds';

  @override
  String get algSpeedsValue =>
      'Provisional, by road class; to be tuned with MDRRMD dispatch records';

  @override
  String get algLstm => 'LSTM forecast';

  @override
  String get algLstmValue =>
      '14-day window, 64 then 32 units, dropout 0.2 (not trained yet)';

  @override
  String get algKde => 'KDE hotspots';

  @override
  String get algKdeValue =>
      'Gaussian kernel, bandwidth 100 to 500 m by cross-validation (not trained yet)';

  @override
  String get algClassifier => 'Incident type classifier';

  @override
  String get algClassifierValue =>
      'TF-IDF on words and word pairs, 4 types. Sample model: trained on made-up descriptions until the MDRRMD set arrives; a report it is under 50% sure of is left untagged';

  @override
  String get configReportsTitle => 'Crowd reports';

  @override
  String get configReportsNote =>
      'The limit applies to each resident account, across the app and the web form (FR15).';

  @override
  String get settingReportsPerHour => 'Reports per account each hour';

  @override
  String get configAlertsTitle => 'Alert thresholds';

  @override
  String get configAlertsNote =>
      'A PAGASA reading at or above a threshold raises an alert for residents by itself (FR5). Provisional values until MDRRMD confirms them. EFCOS water levels are not connected yet.';

  @override
  String get settingRainfallWarning => 'Rainfall warning, mm per hour';

  @override
  String get settingRainfallCritical => 'Rainfall critical, mm per hour';

  @override
  String get settingSignalWarning => 'Wind signal warning';

  @override
  String get settingSignalCritical => 'Wind signal critical';

  @override
  String get settingSurgeWarning => 'Storm surge warning, metres';

  @override
  String get settingSurgeCritical => 'Storm surge critical, metres';

  @override
  String get settingWarningAboveCritical =>
      'Warning must be at or below Critical.';

  @override
  String get configChannelsTitle => 'Alert channels';

  @override
  String get configChannelsNote =>
      'Alerts always appear in the apps. These switches decide where else the next alert goes.';

  @override
  String get channelPush => 'Push notifications';

  @override
  String get channelPushNote =>
      'Needs the Firebase project, which is not set up yet.';

  @override
  String get channelSmsSetting => 'SMS to residents in the affected barangays';

  @override
  String get channelSmsNote =>
      'Sent through Semaphore; each text costs credit.';

  @override
  String get channelFacebook => 'MDRRMD Facebook Page';

  @override
  String get channelFacebookNote =>
      'Needs the page\'s approval and access token.';

  @override
  String get configSmsCapTitle => 'SMS alert limit';

  @override
  String get configSmsCapNote =>
      'Each text costs Semaphore credit. When the day\'s limit is reached, the rest of an alert\'s texts are not sent, and the alert log says so.';

  @override
  String get settingSmsDailyCap => 'Alert texts per day';

  @override
  String get configContactTitle => 'Numbers shown in the apps';

  @override
  String get configContactNote =>
      'The apps read these when they start. Leave one empty to hide it.';

  @override
  String get settingHotline => 'MDRRMD hotline';

  @override
  String get settingHotlineHint => 'For example (02) 8527-0000';

  @override
  String get settingHotlineError =>
      'Use digits, spaces, and + ( ) - only, up to 40 characters.';

  @override
  String get settingGateway => 'SMS gateway number for SOS by text';

  @override
  String get settingGatewayHint => 'For example 0917 123 4567';

  @override
  String get settingGatewayError =>
      'Enter a Philippine mobile number like 0917 123 4567, or leave it empty.';

  @override
  String get configSimulationTitle => 'Simulation mode';

  @override
  String get configSimulationNote =>
      'For demos and UAT. A simulated reading raises alerts marked Simulated: they appear in the apps and are never texted or posted.';

  @override
  String get simulationSwitch => 'Simulation mode';

  @override
  String get simulationOnCaption => 'On. Simulated readings can be sent.';

  @override
  String get simulationOffCaption =>
      'Off. Turn it on to send a simulated reading.';

  @override
  String get simulateTitle => 'Send a simulated PAGASA reading';

  @override
  String get simulateTyphoon => 'Typhoon: Signal 3, 35 mm/hr, 2.5 m surge';

  @override
  String get simulateRain => 'Heavy rain: 22 mm/hr';

  @override
  String get simulateCalm => 'Calm: no signal, 2 mm/hr';

  @override
  String get simulationSent => 'Simulated reading sent';

  @override
  String get unsavedTitle => 'Leave without saving?';

  @override
  String get unsavedBody => 'Changes on this page have not been saved.';

  @override
  String get unsavedStay => 'Stay';

  @override
  String get unsavedLeave => 'Leave';

  @override
  String get actionWeatherSimulated => 'Simulated a weather reading';

  @override
  String get advisoryTitle => 'Issue an advisory';

  @override
  String get advisoryReviewTitle => 'Review before sending';

  @override
  String get advisoryFrom => 'From';

  @override
  String get advisoryLevel => 'Level';

  @override
  String get advisoryTitleLabel => 'Title';

  @override
  String get advisoryTitleError => 'Give the advisory a title.';

  @override
  String get advisoryBodyLabel => 'Message';

  @override
  String get advisoryBodyError => 'Write the message.';

  @override
  String get advisoryStepsLabel => 'What to do (optional)';

  @override
  String get advisoryStepsHint => 'One step per line';

  @override
  String advisoryStepsError(int steps, int length) {
    return 'Use at most $steps steps of up to $length characters each.';
  }

  @override
  String get advisoryArea => 'Who it is for';

  @override
  String get advisoryChosenBarangays => 'Chosen barangays';

  @override
  String get advisoryAreaError => 'Choose at least one barangay.';

  @override
  String get advisoryReview => 'Review';

  @override
  String get advisoryBack => 'Back';

  @override
  String get advisorySend => 'Send advisory';

  @override
  String advisoryStep(String step) {
    return '• $step';
  }

  @override
  String get advisoryToEveryone => 'For residents in all of Manila.';

  @override
  String advisoryToBarangays(String barangays) {
    return 'For residents in $barangays.';
  }

  @override
  String advisoryChannels(String channels) {
    return 'It appears in the apps at once and is queued for $channels.';
  }

  @override
  String get advisoryAppsOnly =>
      'It appears in the apps at once. The other channels are switched off.';

  @override
  String get advisorySimulated =>
      'Simulation mode is on: it will be marked Simulated and shown in the apps only. Nothing is texted or posted.';

  @override
  String get advisoryIssued => 'Advisory issued';

  @override
  String get endAlert => 'End alert';

  @override
  String get endAlertTitle => 'End this alert?';

  @override
  String endAlertBody(String title) {
    return '\"$title\" stops showing in the apps. It stays in this log.';
  }

  @override
  String get alertEndedSnack => 'Alert ended';

  @override
  String get actionAlertIssued => 'Issued an advisory';

  @override
  String get actionAlertEnded => 'Ended an alert';

  @override
  String get forecastTitle => '72-hour forecast';

  @override
  String get forecastSample => 'Sample forecast';

  @override
  String get forecastSampleNote =>
      'Sample values, not model output. The forecast model is not trained yet.';

  @override
  String forecastIssued(String issued, String until) {
    return 'Issued $issued. Valid until $until.';
  }

  @override
  String get forecastStale =>
      'This forecast is more than 24 hours old. A newer run is overdue.';

  @override
  String get forecastEmpty => 'No forecast generated yet.';

  @override
  String get forecastEmptyHint =>
      'The model runs once a day. Its results appear here.';

  @override
  String forecastCounts(int high, int moderate, int low) {
    return '$high high, $moderate moderate, $low low';
  }

  @override
  String get forecastNoneSection => 'No forecast';

  @override
  String forecastMarker(String barangay, String risk) {
    return '$barangay: $risk';
  }

  @override
  String forecastLegend(String hazard) {
    return '$hazard risk, next 72 hours';
  }

  @override
  String get forecastLegendNote =>
      'Circles mark barangay centers, not boundaries.';

  @override
  String get forecastRisks => 'Risk by hazard';

  @override
  String get forecastVulnerable => 'Registered vulnerable residents';

  @override
  String forecastVulnerableCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count residents',
      one: '1 resident',
      zero: 'None registered here',
    );
    return '$_temp0';
  }

  @override
  String get forecastVulnerableUnknown => 'Not loaded yet';

  @override
  String get forecastOpenList => 'Open the list';

  @override
  String get forecastWeatherNow => 'Weather now';

  @override
  String forecastSurge(String meters) {
    return 'Storm surge up to $meters m';
  }

  @override
  String get forecastNoSurge => 'No storm surge advisory';

  @override
  String get forecastAbout => 'About this forecast';

  @override
  String get forecastAboutSample =>
      'These are sample values so the page can be reviewed. Probabilities, the readings behind each risk, and the model\'s measured accuracy appear here once the model is trained.';

  @override
  String forecastAboutModel(String version) {
    return 'Model $version.';
  }

  @override
  String get forecastAboutNoVersion =>
      'The run did not record which model made it.';

  @override
  String get hazardFlood => 'Flood';

  @override
  String get hazardFire => 'Fire';

  @override
  String get hazardSurge => 'Storm surge';

  @override
  String get riskLow => 'Low';

  @override
  String get riskModerate => 'Moderate';

  @override
  String get riskHigh => 'High';

  @override
  String vulnerableOnly(String barangay) {
    return '$barangay only';
  }

  @override
  String get vulnerableShowAll => 'Show all barangays';

  @override
  String vulnerableNoneIn(String barangay) {
    return 'No registered vulnerable residents in $barangay.';
  }

  @override
  String get reportsTitle => 'NDRRMC reports';

  @override
  String get reportsSubtitle =>
      'Post-disaster reports drafted from incident, dispatch, and damage records.';

  @override
  String get reportsEmpty => 'No reports yet.';

  @override
  String get reportsEmptyHint => 'Generate one from incident records.';

  @override
  String get reportNew => 'New report';

  @override
  String get colReport => 'Report';

  @override
  String get colPeriod => 'Period';

  @override
  String get colMadeBy => 'Made by';

  @override
  String get colMadeOn => 'Made on';

  @override
  String reportPeriod(String from, String to) {
    return '$from to $to';
  }

  @override
  String get reportStatusDraft => 'Draft';

  @override
  String get reportStatusFinal => 'Final';

  @override
  String get reportNewTitle => 'New NDRRMC report';

  @override
  String get reportNewSubtitle =>
      'The draft is put together from the records. You review and edit it before it is final.';

  @override
  String get reportPeriodTitle => 'Period to report on';

  @override
  String get reportPeriodNote =>
      'Incidents received in this period are counted.';

  @override
  String get reportPeriodCustom => 'Dates';

  @override
  String get reportPeriodNoDates => 'No dates chosen yet.';

  @override
  String reportPeriodDates(String from, String to) {
    return '$from to $to, whole days';
  }

  @override
  String get reportPeriodChange => 'Choose dates';

  @override
  String get reportCollect => 'Collect records';

  @override
  String get reportCollecting => 'Collecting records and drafting the report';

  @override
  String reportElapsed(String seconds) {
    return '$seconds s';
  }

  @override
  String get reportNoIncidents => 'No incidents in this period.';

  @override
  String get reportChoosePeriod => 'Choose another period';

  @override
  String get reportCollectFailed =>
      'Couldn\'t collect the records. Your period is kept.';

  @override
  String get reportNotFound => 'This report does not exist.';

  @override
  String get reportBackToList => 'Back to the reports';

  @override
  String get reportTitleLabel => 'Report title';

  @override
  String get reportTitleError => 'Give the report a title.';

  @override
  String get reportRemarksHint =>
      'Written by you: what the figures do not say, and what is recommended.';

  @override
  String get reportSave => 'Save draft';

  @override
  String get reportSaved => 'Draft saved';

  @override
  String get reportFinalize => 'Mark as final';

  @override
  String get reportFinalizeTitle => 'Mark this report as final?';

  @override
  String get reportFinalizeBody =>
      'A final report can no longer be edited. It stays in the list and can still be downloaded.';

  @override
  String reportFinalizeUnmet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count checks are not met:',
      one: '1 check is not met:',
    );
    return '$_temp0';
  }

  @override
  String get reportFinalized => 'Report marked as final';

  @override
  String get reportDownload => 'Download PDF';

  @override
  String get reportFigures => 'From the records';

  @override
  String get reportFiguresNote =>
      'The figures the draft was written from, as they were when it was made.';

  @override
  String get reportChecklist => 'Before it is final';

  @override
  String get reportCheckIncidents => 'The period has incidents to report';

  @override
  String get reportCheckNoneOpen => 'No incident of the period is still open';

  @override
  String get reportCheckAllFiled =>
      'Every resolved incident has a completion report';

  @override
  String get reportCheckNoSimulated =>
      'No simulated alerts or readings are counted';

  @override
  String get reportCheckNoEmpty => 'Every section has text';

  @override
  String reportCheckFailed(String check) {
    return 'Not yet: $check';
  }

  @override
  String reportDraftedIn(String seconds) {
    return 'Drafted from the records in $seconds s.';
  }

  @override
  String get reportMethodNote =>
      'The text is put together from the figures with fixed wording. The RAG engine is not connected yet.';

  @override
  String get reportPdfAgency =>
      'Manila Disaster Risk Reduction and Management Department';

  @override
  String reportPdfPeriod(String from, String to) {
    return 'Period covered: $from to $to';
  }

  @override
  String get reportPdfDraft => 'Status: draft, not yet final';

  @override
  String reportPdfFinal(String name, String date) {
    return 'Status: final, marked by $name on $date';
  }

  @override
  String reportPdfPrepared(String name, String date) {
    return 'Prepared by $name on $date';
  }

  @override
  String get reportPdfFooter => 'Prepared with Project S.A.G.I.P.';

  @override
  String get reportPdfEmptySection => '(Nothing written.)';

  @override
  String get figIncidents => 'Incidents';

  @override
  String get figSos => 'SOS requests';

  @override
  String get figClusters => 'Crowd report clusters';

  @override
  String get figResolved => 'Resolved';

  @override
  String get figOpen => 'Still open';

  @override
  String get figFalse => 'False reports';

  @override
  String get figVulnerable => 'With vulnerable households';

  @override
  String get figCompletions => 'Completion reports';

  @override
  String get figAssisted => 'Persons assisted';

  @override
  String get figInjured => 'Injured';

  @override
  String get figMissing => 'Missing';

  @override
  String get figFamilies => 'Affected families';

  @override
  String get figHouses => 'Houses damaged';

  @override
  String get figDispatches => 'Dispatches';

  @override
  String get figUnits => 'Units deployed';

  @override
  String get figAlerts => 'Alerts issued';

  @override
  String get actionReportDrafted => 'Drafted an NDRRMC report';

  @override
  String get actionReportFinalized => 'Marked an NDRRMC report final';

  @override
  String get errorAlreadyFinal =>
      'This report is final and can no longer be changed.';

  @override
  String get levelInfo => 'Advisory';

  @override
  String get levelWarning => 'Warning';

  @override
  String get levelCritical => 'Critical';

  @override
  String thresholdNote(String warning, String critical) {
    return 'Warning from $warning, critical from $critical';
  }

  @override
  String stormSurgeMeters(String meters) {
    return 'Up to $meters m';
  }

  @override
  String get alertLogTitle => 'Alerts sent';

  @override
  String get alertLogNote =>
      'Every alert and what happened to it on each channel (FR6).';

  @override
  String get alertLogEmpty => 'No alerts sent yet.';

  @override
  String get alertLogFailed => 'Couldn\'t load the alert log.';

  @override
  String get alertAllManila => 'All of Manila';

  @override
  String get alertSimulated => 'Simulated';

  @override
  String get alertEnded => 'Ended';

  @override
  String get alertAutomatic => 'Raised by a threshold';

  @override
  String alertFrom(String source, String time) {
    return '$source, $time';
  }

  @override
  String get sourcePagasa => 'PAGASA';

  @override
  String get sourcePhivolcs => 'PHIVOLCS';

  @override
  String get sourceEfcos => 'EFCOS';

  @override
  String get sourceMdrrmd => 'MDRRMD';

  @override
  String get alertChannelApp => 'In the apps';

  @override
  String get alertChannelPush => 'Push';

  @override
  String get alertChannelSms => 'SMS';

  @override
  String get alertChannelFacebook => 'Facebook';

  @override
  String get deliveryQueued => 'Waiting to send';

  @override
  String get deliverySending => 'Sending';

  @override
  String get deliveryEnded => 'Not sent (the alert ended)';

  @override
  String get deliverySent => 'Sent';

  @override
  String get deliveryFailed => 'Failed';

  @override
  String get deliveryOff => 'Switched off';

  @override
  String get deliverySimulated => 'Not sent (simulated)';

  @override
  String get deliveryNotSetUp => 'Not set up';

  @override
  String deliveryLine(String channel, String status) {
    return '$channel: $status';
  }

  @override
  String deliveryCounts(String channel, int delivered, int recipients) {
    return '$channel: sent to $delivered of $recipients';
  }

  @override
  String get webAppTitle => 'S.A.G.I.P. hazard report';

  @override
  String get webSignInTitle => 'Report a hazard to MDRRMD';

  @override
  String get webSignInBody =>
      'Sign in with your mobile number. We\'ll text you a code.';

  @override
  String get webSosNotice =>
      'SOS is only available in the S.A.G.I.P. app. In an emergency, call MDRRMD.';

  @override
  String webSosNoticeHotline(String number) {
    return 'SOS is only available in the S.A.G.I.P. app. In an emergency, call MDRRMD at $number.';
  }

  @override
  String get webGetApp => 'Get the S.A.G.I.P. app';

  @override
  String get webMobileNumber => 'Mobile number';

  @override
  String get webMobileNumberHint => '917 123 4567';

  @override
  String get webSendCode => 'Send code';

  @override
  String get webSendingCode => 'Sending code';

  @override
  String get webCreateAccount => 'New to S.A.G.I.P.? Create an account';

  @override
  String get webHaveAccount => 'Already have an account? Sign in';

  @override
  String webDemoHint(String code) {
    return 'Sample data: sign in with 917 000 4821 and the code $code.';
  }

  @override
  String get webCodeTitle => 'Enter the code';

  @override
  String webCodeBody(String phone) {
    return 'We sent a 6-digit code to $phone.';
  }

  @override
  String get webCodeLabel => '6-digit code';

  @override
  String get webCheckCode => 'Check code';

  @override
  String get webCheckingCode => 'Checking code';

  @override
  String webResendIn(String time) {
    return 'Resend code in $time';
  }

  @override
  String get webResendCode => 'Resend code';

  @override
  String get webCodeSent => 'A new code is on its way.';

  @override
  String get webChangeNumber => 'Change number';

  @override
  String get webRegisterTitle => 'Create an account';

  @override
  String get webRegisterBody =>
      'MDRRMD uses this to reach you and to know your barangay.';

  @override
  String get webFullName => 'Full name';

  @override
  String get webFullNameError => 'Enter your full name.';

  @override
  String get webBarangay => 'Barangay';

  @override
  String get webChooseBarangay => 'Choose your barangay';

  @override
  String get webBarangayError => 'Choose your barangay.';

  @override
  String get webAgreeTerms => 'I agree to the terms and the privacy notice';

  @override
  String get webTermsError => 'Agree to the terms to continue.';

  @override
  String get webReadPrivacy => 'Read the privacy notice';

  @override
  String get webPhoneInvalid =>
      'Enter a Philippine mobile number, like 917 123 4567.';

  @override
  String get webPhoneNotRegistered =>
      'This number has no account yet. Create an account first.';

  @override
  String get webPhoneNotRegisteredApp =>
      'This number has no account yet. Create one in the S.A.G.I.P. app.';

  @override
  String get webPhoneTaken =>
      'This number already has an account. Sign in instead.';

  @override
  String get webCodeWrong =>
      'That code is not right. Check the text message and try again.';

  @override
  String get webTooManyAttempts =>
      'Too many tries. Wait a minute, then try again.';

  @override
  String get webOffline => 'You\'re offline.';

  @override
  String get webSmsUnavailable =>
      'Couldn\'t send or check the code right now. Try again in a few minutes.';

  @override
  String get webPrivacyTitle => 'Privacy notice';

  @override
  String get webPrivacyCollectTitle => 'What we collect';

  @override
  String get webPrivacyCollectBody =>
      'Your name, mobile number, and barangay; and where a hazard is when you send a report.';

  @override
  String get webPrivacyWhyTitle => 'Why';

  @override
  String get webPrivacyWhyBody =>
      'To check reports against others nearby, to reach you about a report, and to send you alerts for your area.';

  @override
  String get webPrivacyWhoTitle => 'Who can see it';

  @override
  String get webPrivacyWhoBody =>
      'MDRRMD dispatchers and administrators. Rescue personnel see only the incident they are assigned to.';

  @override
  String get webPrivacyKeepTitle => 'How long we keep it';

  @override
  String get webPrivacyKeepBody =>
      'As long as you have an account, and incident records as long as the law requires.';

  @override
  String get webPrivacyRightsTitle => 'Your rights';

  @override
  String get webPrivacyRightsBody =>
      'Under the Data Privacy Act (RA 10173) you can see, correct, or ask MDRRMD to delete your data. Ask in the S.A.G.I.P. app or at the MDRRMD office.';

  @override
  String get webReportTitle => 'Report a hazard';

  @override
  String get webReportBody =>
      'MDRRMD checks reports against others nearby before acting. One report alone is not treated as an emergency.';

  @override
  String webSignedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get webMyReports => 'My reports';

  @override
  String get webDescription => 'What do you see?';

  @override
  String get webDescriptionHint =>
      'For example: Water is knee-deep on Dapitan St and rising.';

  @override
  String get webDescriptionEmpty => 'Describe what you see.';

  @override
  String get webType => 'Type (optional)';

  @override
  String get webLocationTitle => 'Where is it?';

  @override
  String get webUseMyLocation => 'Use my location';

  @override
  String get webLocating => 'Getting your location';

  @override
  String get webChooseBarangayButton => 'Choose a barangay';

  @override
  String get webMapHint => 'Or move the map until the pin is on the spot.';

  @override
  String get webLocationNone => 'No location chosen yet.';

  @override
  String webLocationBrowser(int meters) {
    return 'From your browser, accurate to $meters m';
  }

  @override
  String get webLocationPin => 'Chosen on the map';

  @override
  String get webLocationBarangay => 'Centre of the barangay you chose';

  @override
  String webNear(String place) {
    return 'Near $place';
  }

  @override
  String webPlace(String barangay, String district) {
    return '$barangay, $district';
  }

  @override
  String get webLocationDenied =>
      'Your browser did not share your location. Move the map until the pin is on the spot, or choose a barangay.';

  @override
  String get webLocationUnavailable =>
      'Couldn\'t get your location. Move the map until the pin is on the spot, or choose a barangay.';

  @override
  String webQuotaLeft(int remaining, int limit) {
    return '$remaining of $limit reports left this hour';
  }

  @override
  String webQuotaNone(int limit, String time) {
    return 'You\'ve sent $limit reports in the last hour. Try again after $time.';
  }

  @override
  String webQuotaNoneLater(int limit) {
    return 'You\'ve sent $limit reports in the last hour. Try again later.';
  }

  @override
  String get webSuspended =>
      'This account cannot send reports right now. In an emergency, call MDRRMD.';

  @override
  String get webRateLimited =>
      'You\'ve reached the hourly limit for reports. Try again later.';

  @override
  String get webSend => 'Send report';

  @override
  String get webSending => 'Sending';

  @override
  String get webOutsideManila =>
      'This location is outside Manila City. S.A.G.I.P. covers Manila only.';

  @override
  String get webNeedLocation =>
      'Choose where it is: use your location, move the map, or choose a barangay.';

  @override
  String get webConnectionLost =>
      'Connection lost. Your report is kept on this page. Send it when you\'re back online.';

  @override
  String get webPinLabel => 'Report location';

  @override
  String get webSearchBarangay => 'Search barangays';

  @override
  String get webNoBarangayMatch => 'No barangay matches that.';

  @override
  String get webReceivedTitle => 'Report received';

  @override
  String webReference(String id) {
    return 'Reference $id';
  }

  @override
  String get webReceivedBody =>
      'MDRRMD checks it against other reports nearby. A single report is never confirmed on its own.';

  @override
  String get webRecentTitle => 'Your recent reports';

  @override
  String get webNoReports => 'No reports yet.';

  @override
  String get webReportsFailed => 'Couldn\'t load your reports.';

  @override
  String get webSendAnother => 'Send another report';

  @override
  String get webSentFromApp => 'Sent from the app';

  @override
  String get webSentFromWeb => 'Sent from the web form';

  @override
  String webReportWhen(String date, String time) {
    return '$date, $time';
  }

  @override
  String get webStageReceived => 'Received';

  @override
  String get webStageChecking => 'Checking';

  @override
  String get webStageConfirmed => 'Confirmed';

  @override
  String get webStageNotConfirmed => 'Not confirmed';

  @override
  String get webStageResolved => 'Resolved';

  @override
  String get auditEmpty => 'No actions recorded yet.';

  @override
  String get comingSoonTitle => 'Not built yet';

  @override
  String get working => 'Working';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundBody =>
      'It may have moved, or your account can\'t open it.';

  @override
  String get backToBoard => 'Back to the Command Board';

  @override
  String secondsAgo(int count) {
    return '$count s ago';
  }

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count h ago';
  }
}
