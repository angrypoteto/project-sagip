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
  String get unitAvailable => 'Available';

  @override
  String get unitEnRoute => 'En route';

  @override
  String get unitOnScene => 'On scene';

  @override
  String unitDetail(String type, String station, int crew) {
    return '$type · $station · crew of $crew';
  }

  @override
  String sharingLocation(String ago) {
    return 'Sharing location · sent $ago';
  }

  @override
  String locationNotShared(String ago) {
    return 'Location not shared while offline. Last sent $ago.';
  }

  @override
  String get waitingForGps => 'Waiting for GPS';

  @override
  String get noAssignmentTitle => 'No assignment. Stay available.';

  @override
  String get noAssignmentBody =>
      'New assignments appear here and on a full-screen alert.';

  @override
  String get statusNoAssignment =>
      'There\'s no assignment to be en route to or on scene at.';

  @override
  String get statusFinishReport =>
      'File the completion report first. Then the unit becomes available.';

  @override
  String get statusAlreadyOnScene => 'You\'re already on scene.';

  @override
  String get currentAssignment => 'Current assignment';

  @override
  String get openAssignment => 'Open';

  @override
  String get newAssignment => 'New assignment';

  @override
  String get newAssignmentOpen => 'View the new assignment';

  @override
  String distanceEta(String distance, int minutes) {
    return '$distance away · about $minutes min';
  }

  @override
  String vulnerableTypes(String types) {
    return 'Vulnerable: $types';
  }

  @override
  String get vulnSenior => 'Senior citizen';

  @override
  String get vulnPwd => 'Person with disability';

  @override
  String get vulnPregnant => 'Pregnant';

  @override
  String get vulnOther => 'Other';

  @override
  String get typeUnknown => 'Emergency';

  @override
  String get acceptAndStart => 'Accept and start';

  @override
  String get viewDetails => 'View details';

  @override
  String assignmentTitle(String id) {
    return 'Assignment $id';
  }

  @override
  String get assignmentReassigned =>
      'This assignment was reassigned or closed by the dispatcher.';

  @override
  String get victimLocation => 'Where to go';

  @override
  String get incidentDetails => 'What was reported';

  @override
  String reportedVia(String channel) {
    return 'Reported by $channel';
  }

  @override
  String get channelApp => 'the app';

  @override
  String get channelSms => 'SMS';

  @override
  String get channelBle => 'nearby phones';

  @override
  String get channelWeb => 'the web form';

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
  String residentSaid(String note) {
    return 'The resident said: $note';
  }

  @override
  String mapSaving(int percent) {
    return 'Saving map for offline use, $percent%';
  }

  @override
  String get mapSaved => 'Map saved for offline use';

  @override
  String mapNotSaved(int percent) {
    return 'Map not fully saved ($percent%). It continues when you\'re back online.';
  }

  @override
  String get startNavigation => 'Start navigation';

  @override
  String get markOnScene => 'Mark on scene';

  @override
  String get continueOnScene => 'Continue the on-scene check';

  @override
  String get fileReport => 'File the completion report';

  @override
  String get callDispatcher => 'Call dispatcher';

  @override
  String get navigateTitle => 'Navigate';

  @override
  String headDirection(String direction) {
    return 'Head $direction';
  }

  @override
  String get dirN => 'north';

  @override
  String get dirNE => 'northeast';

  @override
  String get dirE => 'east';

  @override
  String get dirSE => 'southeast';

  @override
  String get dirS => 'south';

  @override
  String get dirSW => 'southwest';

  @override
  String get dirW => 'west';

  @override
  String get dirNW => 'northwest';

  @override
  String toGo(String distance) {
    return '$distance to go';
  }

  @override
  String get straightLineNote =>
      'Direct line. Road routes come in a later version.';

  @override
  String get offlineSavedMap => 'Offline. Using saved map.';

  @override
  String get arrived => 'Arrived';

  @override
  String get atScene => 'You\'re at the scene';

  @override
  String distanceAway(String distance) {
    return '$distance away';
  }

  @override
  String get recenter => 'Recenter';

  @override
  String get destination => 'Destination';

  @override
  String get yourUnit => 'Your unit';

  @override
  String get onSceneTitle => 'On scene';

  @override
  String onSceneAt(String time) {
    return 'Arrived at $time';
  }

  @override
  String get realEmergencyQuestion => 'Is this a real emergency?';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get notRealReason => 'Why not? (required)';

  @override
  String get notRealReasonHint =>
      'For example: no one at the address, already handled';

  @override
  String get peopleFound => 'People found';

  @override
  String get completeRescue => 'Complete rescue';

  @override
  String get answerRealFirst => 'Answer whether this is a real emergency.';

  @override
  String get reasonRequired => 'Say why it is not a real emergency.';

  @override
  String get completeTitle => 'Completion report';

  @override
  String get outcome => 'Outcome';

  @override
  String get outcomeRescued => 'Rescued';

  @override
  String get outcomeTreated => 'Treated on site';

  @override
  String get outcomeTransported => 'Transported';

  @override
  String get outcomeNoOne => 'No one found';

  @override
  String get outcomeFalse => 'False report';

  @override
  String get personsAssisted => 'Persons assisted';

  @override
  String get damageTitle => 'Damage assessment';

  @override
  String get housesDamaged => 'Houses damaged';

  @override
  String get injured => 'Injured';

  @override
  String get missing => 'Missing';

  @override
  String get affectedFamilies => 'Affected families';

  @override
  String get reportNotes => 'Notes (optional)';

  @override
  String timeOnScene(int minutes) {
    return 'Time on scene: $minutes min';
  }

  @override
  String get submitReport => 'Submit report';

  @override
  String get chooseOutcome => 'Choose an outcome.';

  @override
  String get reportSubmitted => 'Report sent. The unit is available again.';

  @override
  String get reportSavedOffline =>
      'Report saved on your phone. It will send when you\'re back online.';

  @override
  String get demoOffer => 'Send an assignment now';

  @override
  String get demoClose => 'Dispatcher closes the assignment';

  @override
  String get starting => 'Starting';

  @override
  String get welcomeStep1Title => 'Share your location';

  @override
  String get welcomeStep1Body =>
      'So your SOS shows exactly where you are, and you can see your responder coming.';

  @override
  String get welcomeStep2Title => 'Get alerts';

  @override
  String get welcomeStep2Body =>
      'Weather warnings, updates on your SOS, and a note when something saved on your phone is delivered.';

  @override
  String get welcomeStep3Title => 'Keep SOS working without internet';

  @override
  String get welcomeStep3Body =>
      'With no data, your SOS goes out by SMS. With no signal at all, nearby phones can pass it on.';

  @override
  String get allow => 'Allow';

  @override
  String get allowed => 'Allowed';

  @override
  String get notAllowed => 'Not allowed. SOS still works, but less reliably.';

  @override
  String get next => 'Next';

  @override
  String get skip => 'Skip';

  @override
  String get getStarted => 'Get started';

  @override
  String welcomeStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get residentSignInTitle => 'Sign in';

  @override
  String get residentSignInBody =>
      'Enter your mobile number. We\'ll text you a code.';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get mobileNumberHint => '917 123 4567';

  @override
  String get sendCode => 'Send code';

  @override
  String get sendingCode => 'Sending code';

  @override
  String get createAccountPrompt => 'New to S.A.G.I.P.? Create an account';

  @override
  String get staffSignInLink => 'MDRRMD personnel sign in';

  @override
  String get hotlineCardTitle => 'In an emergency, call MDRRMD';

  @override
  String get offlineSignIn =>
      'You\'re offline. Signing in needs internet. In an emergency, call MDRRMD.';

  @override
  String get demoAccounts => 'Demo accounts';

  @override
  String get phoneInvalid =>
      'Enter a Philippine mobile number, like 917 123 4567.';

  @override
  String get phoneNotRegistered => 'This number has no account yet.';

  @override
  String get phoneTaken =>
      'This number already has an account. Sign in instead.';

  @override
  String get phoneWrongCode =>
      'That code is wrong or has expired. Check it or send a new one.';

  @override
  String get phoneTooMany => 'Too many tries. Try again in 60 s.';

  @override
  String get phoneOffline => 'You\'re offline. Connect to continue.';

  @override
  String get staffSignInTitle => 'MDRRMD personnel';

  @override
  String get staffSignInBody => 'Sign in with the account MDRRMD gave you.';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signInButton => 'Sign in';

  @override
  String get staffDemoHint => 'Demo: r03@sagip.test, password sagip-demo';

  @override
  String get registerTitle => 'Create an account';

  @override
  String get registerBody =>
      'MDRRMD uses this to reach you and to know your barangay.';

  @override
  String get fullName => 'Full name';

  @override
  String get barangay => 'Barangay';

  @override
  String get chooseBarangay => 'Choose your barangay';

  @override
  String get searchBarangay => 'Search barangays';

  @override
  String get sampleBarangays =>
      'Sample list. The full list of Manila\'s 897 barangays comes later.';

  @override
  String get noBarangayMatch => 'No barangay matches that.';

  @override
  String get agreeTerms => 'I agree to the terms and the privacy notice';

  @override
  String get readPrivacy => 'Read the privacy notice';

  @override
  String get continueButton => 'Continue';

  @override
  String get creatingAccount => 'Creating account';

  @override
  String get nameRequired => 'Enter your full name.';

  @override
  String get barangayRequired => 'Choose your barangay.';

  @override
  String get termsRequired => 'Agree to the terms to continue.';

  @override
  String get verifyTitle => 'Enter the code';

  @override
  String verifyBody(String phone) {
    return 'We sent a 6-digit code to $phone.';
  }

  @override
  String get codeLabel => '6-digit code';

  @override
  String get checkCode => 'Check code';

  @override
  String get checkingCode => 'Checking code';

  @override
  String resendIn(String time) {
    return 'Resend code in $time';
  }

  @override
  String get resendCode => 'Resend code';

  @override
  String get codeSent => 'A new code is on its way.';

  @override
  String get changeNumber => 'Change number';

  @override
  String get waitingForConnection =>
      'Waiting for connection. Your code is kept.';

  @override
  String demoCodeHint(String code) {
    return 'Demo code: $code';
  }

  @override
  String get profile => 'Profile';

  @override
  String get myActivity => 'My activity';

  @override
  String get vulnerabilityProfile => 'Vulnerability profile';

  @override
  String get settings => 'Settings';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSoon => 'Filipino is coming';

  @override
  String get testNotification => 'Send a test notification';

  @override
  String get testNotificationSent =>
      'Test: this is how S.A.G.I.P. alerts appear.';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyNotice => 'Privacy notice';

  @override
  String get requestDeletion => 'Request deletion of my data';

  @override
  String get requestDeletionTitle => 'Delete your data?';

  @override
  String get requestDeletionBody =>
      'MDRRMD will delete your profile and household list and keep only what the law requires for incident records. You\'ll need a new account to send an SOS.';

  @override
  String get requestDeletionConfirm => 'Send request';

  @override
  String get requestDeletionSent =>
      'Request sent. MDRRMD will contact you to confirm.';

  @override
  String get cancel => 'Cancel';

  @override
  String get signOutTitle => 'Sign out?';

  @override
  String signOutWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are',
      one: '1 item is',
    );
    return '$_temp0 waiting to send. They stay on this phone and send after you sign in again.';
  }

  @override
  String get privacyTitle => 'Privacy notice';

  @override
  String get privacyCollectTitle => 'What we collect';

  @override
  String get privacyCollectBody =>
      'Your name, mobile number, and barangay; where you are when you send an SOS or a report; and, only if you agree, household members who may need priority rescue.';

  @override
  String get privacyWhyTitle => 'Why';

  @override
  String get privacyWhyBody =>
      'To find and reach you in an emergency, to send you alerts for your area, and to plan rescues for people who need extra help.';

  @override
  String get privacyWhoTitle => 'Who can see it';

  @override
  String get privacyWhoBody =>
      'MDRRMD dispatchers and administrators. Rescue personnel see only the incident they are assigned to, and vulnerability types, never names.';

  @override
  String get privacyKeepTitle => 'How long we keep it';

  @override
  String get privacyKeepBody =>
      'As long as you have an account, and incident records as long as the law requires.';

  @override
  String get privacyRightsTitle => 'Your rights';

  @override
  String get privacyRightsBody =>
      'Under the Data Privacy Act (RA 10173) you can see, correct, or ask us to delete your data, and withdraw consent at any time in Me.';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get retry => 'Try again';
}
