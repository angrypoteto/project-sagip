// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'S.A.G.I.P.';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get demoSignInBody =>
      'Demo mode: this build uses sample data, not real accounts.';

  @override
  String get continueAsResident => 'Continue as resident';

  @override
  String get continueAsResidentDetail =>
      'Maria Dela Cruz · Barangay 412, Sampaloc';

  @override
  String get continueAsResponder => 'Continue as rescue personnel';

  @override
  String get continueAsResponderDetail => 'J. Reyes · Unit R-03';

  @override
  String get signingIn => 'Signing in';

  @override
  String get signInWrongCredentials => 'That account didn\'t work. Try again.';

  @override
  String get signInDisabled => 'This account is turned off. Ask MDRRMD.';

  @override
  String get signInNotStaff => 'This account can\'t use the mobile app.';

  @override
  String get signInOffline =>
      'You\'re offline. Signing in needs internet. In an emergency, call MDRRMD.';

  @override
  String get navHome => 'Home';

  @override
  String get navReport => 'Report';

  @override
  String get navAlerts => 'Alerts';

  @override
  String get navMe => 'Me';

  @override
  String get navHistory => 'History';

  @override
  String greeting(String name) {
    return 'Hi, $name';
  }

  @override
  String place(String barangay, String district) {
    return '$barangay, $district';
  }

  @override
  String alertStripSignal(int level, String mm) {
    return 'Signal No. $level · Rainfall $mm mm/hr · PAGASA';
  }

  @override
  String alertStripRain(String mm) {
    return 'Rainfall $mm mm/hr · PAGASA';
  }

  @override
  String get sosSemantic => 'Send SOS. Hold for 2 seconds.';

  @override
  String get sosOpenSemantic => 'Your SOS is active. Open its status.';

  @override
  String get sosHoldCaption => 'Hold for 2 seconds to send';

  @override
  String get sosCaptionSending => 'Sending your SOS';

  @override
  String get sosCaptionSaved => 'Saved on your phone';

  @override
  String get sosCaptionSms => 'Sent by SMS';

  @override
  String get sosCaptionRelaying => 'Passing to nearby phones';

  @override
  String get sosCaptionDelivered => 'MDRRMD has your SOS';

  @override
  String get gpsOff =>
      'Location unavailable. Turn on GPS to send your exact location.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get reportHazard => 'Report a hazard';

  @override
  String get sosSaveFailed => 'Couldn\'t save your SOS. Call MDRRMD.';

  @override
  String get activeSosTitle => 'Your SOS';

  @override
  String get viewStatus => 'View status';

  @override
  String elapsed(String time) {
    return '$time since you sent it';
  }

  @override
  String get bannerSmsOnly =>
      'Offline. Your SOS will be saved and sent by SMS.';

  @override
  String get bannerNoSignal =>
      'No signal. Your SOS will be saved and passed to nearby phones.';

  @override
  String bannerOfflineWaiting(int count) {
    return 'Offline · $count waiting to send';
  }

  @override
  String bannerSending(int count) {
    return 'Back online · sending $count saved on your phone';
  }

  @override
  String get bannerBackOnline => 'Back online';

  @override
  String get deliverySaved => 'Saved on phone';

  @override
  String get deliverySending => 'Sending';

  @override
  String get deliverySms => 'Sent by SMS';

  @override
  String get deliveryRelaying => 'Relaying to nearby phones';

  @override
  String get deliveryDelivered => 'Delivered';

  @override
  String get deliveryRejected => 'Not accepted';

  @override
  String sosDeliveredNotice(String time) {
    return 'Your SOS from $time was delivered.';
  }

  @override
  String reportDeliveredNotice(String time) {
    return 'Your hazard report from $time was delivered.';
  }

  @override
  String statusDeliveredNotice(String time) {
    return 'Your status update from $time was delivered.';
  }

  @override
  String completionDeliveredNotice(String time) {
    return 'Your completion report from $time was delivered.';
  }

  @override
  String get sosStatusTitle => 'Your SOS';

  @override
  String get sosStateSaved => 'Saved on your phone';

  @override
  String get sosStateSending => 'Sending';

  @override
  String get sosStateSms => 'Sent by SMS';

  @override
  String get sosStateRelaying => 'Passing to nearby phones';

  @override
  String get sosStatePending => 'Waiting for verification';

  @override
  String get sosStateVerified => 'Verified by MDRRMD';

  @override
  String get sosStateAssigned => 'Responder assigned';

  @override
  String get sosStateEnRoute => 'Responder on the way';

  @override
  String get sosStateOnScene => 'Responder has arrived';

  @override
  String get sosStateResolved => 'Resolved';

  @override
  String get sosStateRejected => 'SOS not accepted. Call MDRRMD.';

  @override
  String get keepTrying =>
      'We\'ll keep trying and tell you when it\'s delivered.';

  @override
  String get resolvedBody => 'Your SOS is resolved. Stay safe.';

  @override
  String get timelineTitle => 'Progress';

  @override
  String get stepSaved => 'Saved on phone';

  @override
  String get stepSentInternet => 'Sent by internet';

  @override
  String get stepSentSms => 'Sent by SMS';

  @override
  String get stepSentRelay => 'Passed to nearby phones';

  @override
  String get stepSent => 'Sent';

  @override
  String get stepReceived => 'Received by MDRRMD';

  @override
  String get stepPending => 'Pending verification';

  @override
  String get stepVerified => 'Verified';

  @override
  String get stepAssigned => 'Responder assigned';

  @override
  String stepAssignedUnit(String unit) {
    return 'Responder assigned: $unit';
  }

  @override
  String get stepEnRoute => 'En route';

  @override
  String get stepOnScene => 'On scene';

  @override
  String get stepResolved => 'Resolved';

  @override
  String get etaTitle => 'Arriving in about';

  @override
  String etaMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String unitLine(String callSign, String unitType) {
    return '$callSign · $unitType';
  }

  @override
  String get unitAmbulance => 'Ambulance';

  @override
  String get unitRescueBoat => 'Rescue boat';

  @override
  String get unitRescueTeam => 'Rescue team';

  @override
  String get locationTitle => 'Your location';

  @override
  String locationAccuracy(String coordinates, int meters) {
    return '$coordinates · accurate to $meters m';
  }

  @override
  String get locationUnknown => 'No GPS fix. MDRRMD has your barangay.';

  @override
  String get addDetails => 'Add details';

  @override
  String get editDetails => 'Edit details';

  @override
  String get detailsHint => 'Optional. Your SOS is already on its way.';

  @override
  String get detailsType => 'What is happening?';

  @override
  String get typeFlood => 'Flood';

  @override
  String get typeFire => 'Fire';

  @override
  String get typeMedical => 'Medical';

  @override
  String get typeStructural => 'Collapse or damage';

  @override
  String get detailsPeople => 'People with you';

  @override
  String detailsPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get fewerPeople => 'Fewer people';

  @override
  String get morePeople => 'More people';

  @override
  String get detailsExtraHelp => 'Someone here needs extra help';

  @override
  String get detailsExtraHelpHint =>
      'For example a senior, a person with disability, or a pregnant woman';

  @override
  String get detailsNote => 'Anything else (optional)';

  @override
  String get saveDetails => 'Save details';

  @override
  String get detailsSaved => 'Details added';

  @override
  String get guidanceTitle => 'While you wait';

  @override
  String get guidanceBody =>
      'Stay where you are if it\'s safe. If water is rising, move to a higher floor. Keep your phone on and near you.';

  @override
  String get callMdrrmd => 'Call MDRRMD';

  @override
  String get hotlineTitle => 'MDRRMD hotline';

  @override
  String hotlineBody(String number) {
    return 'Call $number from any phone.';
  }

  @override
  String get hotlineMissing =>
      'This build doesn\'t have the MDRRMD hotline number yet.';

  @override
  String get close => 'Close';

  @override
  String get sosNotFound => 'This SOS isn\'t on this phone anymore.';

  @override
  String get queueTitle => 'Waiting to send';

  @override
  String get queueEmpty => 'Nothing waiting to send.';

  @override
  String get queueTryNow => 'Try sending now';

  @override
  String get queueNextInternet =>
      'You\'re online. Everything saved here is being sent now.';

  @override
  String get queueNextSms =>
      'No internet. SOS messages go out by SMS; the rest waits for internet.';

  @override
  String get queueNextNone =>
      'No signal. We\'ll keep trying, and pass your SOS to nearby phones.';

  @override
  String queueCaptured(String time) {
    return 'Captured $time';
  }

  @override
  String get queueKindSos => 'SOS';

  @override
  String get queueKindReport => 'Hazard report';

  @override
  String get queueKindStatus => 'Status update';

  @override
  String get queueKindCompletion => 'Completion report';

  @override
  String get queueRemove => 'Remove';

  @override
  String get meTitle => 'Me';

  @override
  String get roleResident => 'Resident';

  @override
  String get roleResponder => 'Field rescue personnel';

  @override
  String get signOut => 'Sign out';

  @override
  String get demoTitle => 'Demo tools';

  @override
  String get demoNote => 'Shown only when the app runs on sample data.';

  @override
  String get demoSignal => 'Signal';

  @override
  String get signalInternet => 'Internet';

  @override
  String get signalSms => 'SMS only';

  @override
  String get signalNone => 'No signal';

  @override
  String get demoGps => 'GPS on';

  @override
  String comingTitle(String screen) {
    return '$screen comes next';
  }

  @override
  String get comingBody => 'This screen is part of the next build step.';

  @override
  String get screenAlerts => 'Alerts and forecast';

  @override
  String get screenResponderHome => 'Responder home';

  @override
  String get screenHistory => 'Assignment history';

  @override
  String get trackResponder => 'Track responder';

  @override
  String get trackTitle => 'Track responder';

  @override
  String get trackFinding => 'Finding your responder';

  @override
  String get trackWaiting => 'Waiting for a responder to be assigned.';

  @override
  String get trackArrived => 'Your responder has arrived.';

  @override
  String trackUpdated(String ago) {
    return 'Updated $ago';
  }

  @override
  String trackOffline(String time) {
    return 'Offline. Showing last known position from $time.';
  }

  @override
  String get youAreHere => 'Your location';

  @override
  String responderMarker(String callSign) {
    return 'Responder $callSign';
  }

  @override
  String secondsAgo(int n) {
    return '$n s ago';
  }

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String get mapAttribution => 'OpenStreetMap contributors';

  @override
  String get reportTitle => 'Report a hazard';

  @override
  String get reportExpectation =>
      'MDRRMD checks reports against others nearby before acting.';

  @override
  String get reportSosHint => 'In danger right now? Use SOS on the Home tab.';

  @override
  String get reportDescription => 'What do you see?';

  @override
  String get reportDescriptionHint =>
      'For example: Water is knee-deep on Dapitan St and rising.';

  @override
  String get reportType => 'Type (optional)';

  @override
  String get reportLocation => 'Location';

  @override
  String get reportLocationLast =>
      'Your last known location. Turn on GPS for a better one.';

  @override
  String get reportLocationFinding => 'Getting your location';

  @override
  String get reportSend => 'Send report';

  @override
  String get reportSaving => 'Saving';

  @override
  String get reportEmpty => 'Describe what you see.';

  @override
  String get reportOutsideManila =>
      'This location is outside Manila City. S.A.G.I.P. covers Manila only.';

  @override
  String get reportRateLimited =>
      'You\'ve sent several reports in the last hour. Try again later, or call MDRRMD.';

  @override
  String get reportNoLocation =>
      'We need your location to send a report. Turn on GPS and try again.';

  @override
  String get reportSentTitle => 'Report sent';

  @override
  String get reportSavedTitle => 'Saved on your phone';

  @override
  String get reportSentBody =>
      'Thank you. MDRRMD checks reports against others nearby before acting.';

  @override
  String get reportSavedBody => 'It will send when you\'re back online.';

  @override
  String get reportSeeQueue => 'See what\'s waiting';

  @override
  String get reportAnother => 'Send another report';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get retry => 'Try again';
}
