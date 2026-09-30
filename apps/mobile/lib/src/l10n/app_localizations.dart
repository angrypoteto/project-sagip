import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'S.A.G.I.P.'**
  String get appTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInTitle;

  /// No description provided for @demoSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Demo mode: this build uses sample data, not real accounts.'**
  String get demoSignInBody;

  /// No description provided for @continueAsResident.
  ///
  /// In en, this message translates to:
  /// **'Continue as resident'**
  String get continueAsResident;

  /// No description provided for @continueAsResidentDetail.
  ///
  /// In en, this message translates to:
  /// **'Maria Dela Cruz · Barangay 412, Sampaloc'**
  String get continueAsResidentDetail;

  /// No description provided for @continueAsResponder.
  ///
  /// In en, this message translates to:
  /// **'Continue as rescue personnel'**
  String get continueAsResponder;

  /// No description provided for @continueAsResponderDetail.
  ///
  /// In en, this message translates to:
  /// **'J. Reyes · Unit R-03'**
  String get continueAsResponderDetail;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get signingIn;

  /// No description provided for @signInWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'That account didn\'t work. Try again.'**
  String get signInWrongCredentials;

  /// No description provided for @signInDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account is turned off. Ask MDRRMD.'**
  String get signInDisabled;

  /// No description provided for @signInNotStaff.
  ///
  /// In en, this message translates to:
  /// **'This account can\'t use the mobile app.'**
  String get signInNotStaff;

  /// No description provided for @signInOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Signing in needs internet. In an emergency, call MDRRMD.'**
  String get signInOffline;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get navReport;

  /// No description provided for @navAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get navAlerts;

  /// No description provided for @navMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get navMe;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String greeting(String name);

  /// No description provided for @place.
  ///
  /// In en, this message translates to:
  /// **'{barangay}, {district}'**
  String place(String barangay, String district);

  /// No description provided for @alertStripSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal No. {level} · Rainfall {mm} mm/hr · PAGASA'**
  String alertStripSignal(int level, String mm);

  /// No description provided for @alertStripRain.
  ///
  /// In en, this message translates to:
  /// **'Rainfall {mm} mm/hr · PAGASA'**
  String alertStripRain(String mm);

  /// No description provided for @sosSemantic.
  ///
  /// In en, this message translates to:
  /// **'Send SOS. Hold for 2 seconds.'**
  String get sosSemantic;

  /// No description provided for @sosOpenSemantic.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is active. Open its status.'**
  String get sosOpenSemantic;

  /// No description provided for @sosHoldCaption.
  ///
  /// In en, this message translates to:
  /// **'Hold for 2 seconds to send'**
  String get sosHoldCaption;

  /// No description provided for @sosCaptionSending.
  ///
  /// In en, this message translates to:
  /// **'Sending your SOS'**
  String get sosCaptionSending;

  /// No description provided for @sosCaptionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved on your phone'**
  String get sosCaptionSaved;

  /// No description provided for @sosCaptionSms.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS'**
  String get sosCaptionSms;

  /// No description provided for @sosCaptionRelaying.
  ///
  /// In en, this message translates to:
  /// **'Passing to nearby phones'**
  String get sosCaptionRelaying;

  /// No description provided for @sosCaptionDelivered.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD has your SOS'**
  String get sosCaptionDelivered;

  /// No description provided for @gpsOff.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable. Turn on GPS to send your exact location.'**
  String get gpsOff;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @reportHazard.
  ///
  /// In en, this message translates to:
  /// **'Report a hazard'**
  String get reportHazard;

  /// No description provided for @sosSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your SOS. Call MDRRMD.'**
  String get sosSaveFailed;

  /// No description provided for @activeSosTitle.
  ///
  /// In en, this message translates to:
  /// **'Your SOS'**
  String get activeSosTitle;

  /// No description provided for @viewStatus.
  ///
  /// In en, this message translates to:
  /// **'View status'**
  String get viewStatus;

  /// No description provided for @elapsed.
  ///
  /// In en, this message translates to:
  /// **'{time} since you sent it'**
  String elapsed(String time);

  /// No description provided for @bannerSmsOnly.
  ///
  /// In en, this message translates to:
  /// **'Offline. Your SOS will be saved and sent by SMS.'**
  String get bannerSmsOnly;

  /// No description provided for @bannerNoSignal.
  ///
  /// In en, this message translates to:
  /// **'No signal. Your SOS will be saved and passed to nearby phones.'**
  String get bannerNoSignal;

  /// No description provided for @bannerOfflineWaiting.
  ///
  /// In en, this message translates to:
  /// **'Offline · {count} waiting to send'**
  String bannerOfflineWaiting(int count);

  /// No description provided for @bannerSending.
  ///
  /// In en, this message translates to:
  /// **'Back online · sending {count} saved on your phone'**
  String bannerSending(int count);

  /// No description provided for @bannerBackOnline.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get bannerBackOnline;

  /// No description provided for @deliverySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved on phone'**
  String get deliverySaved;

  /// No description provided for @deliverySending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get deliverySending;

  /// No description provided for @deliverySms.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS'**
  String get deliverySms;

  /// No description provided for @deliveryRelaying.
  ///
  /// In en, this message translates to:
  /// **'Relaying to nearby phones'**
  String get deliveryRelaying;

  /// No description provided for @deliveryDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get deliveryDelivered;

  /// No description provided for @deliveryRejected.
  ///
  /// In en, this message translates to:
  /// **'Not accepted'**
  String get deliveryRejected;

  /// No description provided for @sosDeliveredNotice.
  ///
  /// In en, this message translates to:
  /// **'Your SOS from {time} was delivered.'**
  String sosDeliveredNotice(String time);

  /// No description provided for @reportDeliveredNotice.
  ///
  /// In en, this message translates to:
  /// **'Your hazard report from {time} was delivered.'**
  String reportDeliveredNotice(String time);

  /// No description provided for @statusDeliveredNotice.
  ///
  /// In en, this message translates to:
  /// **'Your status update from {time} was delivered.'**
  String statusDeliveredNotice(String time);

  /// No description provided for @completionDeliveredNotice.
  ///
  /// In en, this message translates to:
  /// **'Your completion report from {time} was delivered.'**
  String completionDeliveredNotice(String time);

  /// No description provided for @sosStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Your SOS'**
  String get sosStatusTitle;

  /// No description provided for @sosStateSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved on your phone'**
  String get sosStateSaved;

  /// No description provided for @sosStateSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sosStateSending;

  /// No description provided for @sosStateSms.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS'**
  String get sosStateSms;

  /// No description provided for @sosStateRelaying.
  ///
  /// In en, this message translates to:
  /// **'Passing to nearby phones'**
  String get sosStateRelaying;

  /// No description provided for @sosStatePending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for verification'**
  String get sosStatePending;

  /// No description provided for @sosStateVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified by MDRRMD'**
  String get sosStateVerified;

  /// No description provided for @sosStateAssigned.
  ///
  /// In en, this message translates to:
  /// **'Responder assigned'**
  String get sosStateAssigned;

  /// No description provided for @sosStateEnRoute.
  ///
  /// In en, this message translates to:
  /// **'Responder on the way'**
  String get sosStateEnRoute;

  /// No description provided for @sosStateOnScene.
  ///
  /// In en, this message translates to:
  /// **'Responder has arrived'**
  String get sosStateOnScene;

  /// No description provided for @sosStateResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get sosStateResolved;

  /// No description provided for @sosStateRejected.
  ///
  /// In en, this message translates to:
  /// **'SOS not accepted. Call MDRRMD.'**
  String get sosStateRejected;

  /// No description provided for @keepTrying.
  ///
  /// In en, this message translates to:
  /// **'We\'ll keep trying and tell you when it\'s delivered.'**
  String get keepTrying;

  /// No description provided for @resolvedBody.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is resolved. Stay safe.'**
  String get resolvedBody;

  /// No description provided for @timelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get timelineTitle;

  /// No description provided for @stepSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved on phone'**
  String get stepSaved;

  /// No description provided for @stepSentInternet.
  ///
  /// In en, this message translates to:
  /// **'Sent by internet'**
  String get stepSentInternet;

  /// No description provided for @stepSentSms.
  ///
  /// In en, this message translates to:
  /// **'Sent by SMS'**
  String get stepSentSms;

  /// No description provided for @stepSentRelay.
  ///
  /// In en, this message translates to:
  /// **'Passed to nearby phones'**
  String get stepSentRelay;

  /// No description provided for @stepSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get stepSent;

  /// No description provided for @stepReceived.
  ///
  /// In en, this message translates to:
  /// **'Received by MDRRMD'**
  String get stepReceived;

  /// No description provided for @stepPending.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get stepPending;

  /// No description provided for @stepVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get stepVerified;

  /// No description provided for @stepAssigned.
  ///
  /// In en, this message translates to:
  /// **'Responder assigned'**
  String get stepAssigned;

  /// No description provided for @stepAssignedUnit.
  ///
  /// In en, this message translates to:
  /// **'Responder assigned: {unit}'**
  String stepAssignedUnit(String unit);

  /// No description provided for @stepEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get stepEnRoute;

  /// No description provided for @stepOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get stepOnScene;

  /// No description provided for @stepResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get stepResolved;

  /// No description provided for @etaTitle.
  ///
  /// In en, this message translates to:
  /// **'Arriving in about'**
  String get etaTitle;

  /// No description provided for @etaMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String etaMinutes(int minutes);

  /// No description provided for @unitLine.
  ///
  /// In en, this message translates to:
  /// **'{callSign} · {unitType}'**
  String unitLine(String callSign, String unitType);

  /// No description provided for @unitAmbulance.
  ///
  /// In en, this message translates to:
  /// **'Ambulance'**
  String get unitAmbulance;

  /// No description provided for @unitRescueBoat.
  ///
  /// In en, this message translates to:
  /// **'Rescue boat'**
  String get unitRescueBoat;

  /// No description provided for @unitRescueTeam.
  ///
  /// In en, this message translates to:
  /// **'Rescue team'**
  String get unitRescueTeam;

  /// No description provided for @locationTitle.
  ///
  /// In en, this message translates to:
  /// **'Your location'**
  String get locationTitle;

  /// No description provided for @locationAccuracy.
  ///
  /// In en, this message translates to:
  /// **'{coordinates} · accurate to {meters} m'**
  String locationAccuracy(String coordinates, int meters);

  /// No description provided for @locationUnknown.
  ///
  /// In en, this message translates to:
  /// **'No GPS fix. MDRRMD has your barangay.'**
  String get locationUnknown;

  /// No description provided for @addDetails.
  ///
  /// In en, this message translates to:
  /// **'Add details'**
  String get addDetails;

  /// No description provided for @editDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get editDetails;

  /// No description provided for @detailsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. Your SOS is already on its way.'**
  String get detailsHint;

  /// No description provided for @detailsType.
  ///
  /// In en, this message translates to:
  /// **'What is happening?'**
  String get detailsType;

  /// No description provided for @typeFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get typeFlood;

  /// No description provided for @typeFire.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get typeFire;

  /// No description provided for @typeMedical.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get typeMedical;

  /// No description provided for @typeStructural.
  ///
  /// In en, this message translates to:
  /// **'Collapse or damage'**
  String get typeStructural;

  /// No description provided for @detailsPeople.
  ///
  /// In en, this message translates to:
  /// **'People with you'**
  String get detailsPeople;

  /// No description provided for @detailsPeopleCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String detailsPeopleCount(int count);

  /// No description provided for @fewerPeople.
  ///
  /// In en, this message translates to:
  /// **'Fewer people'**
  String get fewerPeople;

  /// No description provided for @morePeople.
  ///
  /// In en, this message translates to:
  /// **'More people'**
  String get morePeople;

  /// No description provided for @detailsExtraHelp.
  ///
  /// In en, this message translates to:
  /// **'Someone here needs extra help'**
  String get detailsExtraHelp;

  /// No description provided for @detailsExtraHelpHint.
  ///
  /// In en, this message translates to:
  /// **'For example a senior, a person with disability, or a pregnant woman'**
  String get detailsExtraHelpHint;

  /// No description provided for @detailsNote.
  ///
  /// In en, this message translates to:
  /// **'Anything else (optional)'**
  String get detailsNote;

  /// No description provided for @saveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save details'**
  String get saveDetails;

  /// No description provided for @detailsSaved.
  ///
  /// In en, this message translates to:
  /// **'Details added'**
  String get detailsSaved;

  /// No description provided for @guidanceTitle.
  ///
  /// In en, this message translates to:
  /// **'While you wait'**
  String get guidanceTitle;

  /// No description provided for @guidanceBody.
  ///
  /// In en, this message translates to:
  /// **'Stay where you are if it\'s safe. If water is rising, move to a higher floor. Keep your phone on and near you.'**
  String get guidanceBody;

  /// No description provided for @callMdrrmd.
  ///
  /// In en, this message translates to:
  /// **'Call MDRRMD'**
  String get callMdrrmd;

  /// No description provided for @hotlineTitle.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD hotline'**
  String get hotlineTitle;

  /// No description provided for @hotlineBody.
  ///
  /// In en, this message translates to:
  /// **'Call {number} from any phone.'**
  String hotlineBody(String number);

  /// No description provided for @hotlineMissing.
  ///
  /// In en, this message translates to:
  /// **'This build doesn\'t have the MDRRMD hotline number yet.'**
  String get hotlineMissing;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @sosNotFound.
  ///
  /// In en, this message translates to:
  /// **'This SOS isn\'t on this phone anymore.'**
  String get sosNotFound;

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get queueTitle;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting to send.'**
  String get queueEmpty;

  /// No description provided for @queueTryNow.
  ///
  /// In en, this message translates to:
  /// **'Try sending now'**
  String get queueTryNow;

  /// No description provided for @queueNextInternet.
  ///
  /// In en, this message translates to:
  /// **'You\'re online. Everything saved here is being sent now.'**
  String get queueNextInternet;

  /// No description provided for @queueNextSms.
  ///
  /// In en, this message translates to:
  /// **'No internet. SOS messages go out by SMS; the rest waits for internet.'**
  String get queueNextSms;

  /// No description provided for @queueNextNone.
  ///
  /// In en, this message translates to:
  /// **'No signal. We\'ll keep trying, and pass your SOS to nearby phones.'**
  String get queueNextNone;

  /// No description provided for @queueCaptured.
  ///
  /// In en, this message translates to:
  /// **'Captured {time}'**
  String queueCaptured(String time);

  /// No description provided for @queueKindSos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get queueKindSos;

  /// No description provided for @queueKindReport.
  ///
  /// In en, this message translates to:
  /// **'Hazard report'**
  String get queueKindReport;

  /// No description provided for @queueKindStatus.
  ///
  /// In en, this message translates to:
  /// **'Status update'**
  String get queueKindStatus;

  /// No description provided for @queueKindCompletion.
  ///
  /// In en, this message translates to:
  /// **'Completion report'**
  String get queueKindCompletion;

  /// No description provided for @queueRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get queueRemove;

  /// No description provided for @meTitle.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get meTitle;

  /// No description provided for @roleResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get roleResident;

  /// No description provided for @roleResponder.
  ///
  /// In en, this message translates to:
  /// **'Field rescue personnel'**
  String get roleResponder;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @demoTitle.
  ///
  /// In en, this message translates to:
  /// **'Demo tools'**
  String get demoTitle;

  /// No description provided for @demoNote.
  ///
  /// In en, this message translates to:
  /// **'Shown only when the app runs on sample data.'**
  String get demoNote;

  /// No description provided for @demoSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get demoSignal;

  /// No description provided for @signalInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get signalInternet;

  /// No description provided for @signalSms.
  ///
  /// In en, this message translates to:
  /// **'SMS only'**
  String get signalSms;

  /// No description provided for @signalNone.
  ///
  /// In en, this message translates to:
  /// **'No signal'**
  String get signalNone;

  /// No description provided for @demoGps.
  ///
  /// In en, this message translates to:
  /// **'GPS on'**
  String get demoGps;

  /// No description provided for @comingTitle.
  ///
  /// In en, this message translates to:
  /// **'{screen} comes next'**
  String comingTitle(String screen);

  /// No description provided for @comingBody.
  ///
  /// In en, this message translates to:
  /// **'This screen is part of the next build step.'**
  String get comingBody;

  /// No description provided for @screenAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts and forecast'**
  String get screenAlerts;

  /// No description provided for @screenResponderHome.
  ///
  /// In en, this message translates to:
  /// **'Responder home'**
  String get screenResponderHome;

  /// No description provided for @screenHistory.
  ///
  /// In en, this message translates to:
  /// **'Assignment history'**
  String get screenHistory;

  /// No description provided for @trackResponder.
  ///
  /// In en, this message translates to:
  /// **'Track responder'**
  String get trackResponder;

  /// No description provided for @trackTitle.
  ///
  /// In en, this message translates to:
  /// **'Track responder'**
  String get trackTitle;

  /// No description provided for @trackFinding.
  ///
  /// In en, this message translates to:
  /// **'Finding your responder'**
  String get trackFinding;

  /// No description provided for @trackWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a responder to be assigned.'**
  String get trackWaiting;

  /// No description provided for @trackArrived.
  ///
  /// In en, this message translates to:
  /// **'Your responder has arrived.'**
  String get trackArrived;

  /// No description provided for @trackUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {ago}'**
  String trackUpdated(String ago);

  /// No description provided for @trackOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline. Showing last known position from {time}.'**
  String trackOffline(String time);

  /// No description provided for @youAreHere.
  ///
  /// In en, this message translates to:
  /// **'Your location'**
  String get youAreHere;

  /// No description provided for @responderMarker.
  ///
  /// In en, this message translates to:
  /// **'Responder {callSign}'**
  String responderMarker(String callSign);

  /// No description provided for @secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} s ago'**
  String secondsAgo(int n);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String hoursAgo(int n);

  /// No description provided for @mapAttribution.
  ///
  /// In en, this message translates to:
  /// **'OpenStreetMap contributors'**
  String get mapAttribution;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a hazard'**
  String get reportTitle;

  /// No description provided for @reportExpectation.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD checks reports against others nearby before acting.'**
  String get reportExpectation;

  /// No description provided for @reportSosHint.
  ///
  /// In en, this message translates to:
  /// **'In danger right now? Use SOS on the Home tab.'**
  String get reportSosHint;

  /// No description provided for @reportDescription.
  ///
  /// In en, this message translates to:
  /// **'What do you see?'**
  String get reportDescription;

  /// No description provided for @reportDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Water is knee-deep on Dapitan St and rising.'**
  String get reportDescriptionHint;

  /// No description provided for @reportType.
  ///
  /// In en, this message translates to:
  /// **'Type (optional)'**
  String get reportType;

  /// No description provided for @reportLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get reportLocation;

  /// No description provided for @reportLocationLast.
  ///
  /// In en, this message translates to:
  /// **'Your last known location. Turn on GPS for a better one.'**
  String get reportLocationLast;

  /// No description provided for @reportLocationFinding.
  ///
  /// In en, this message translates to:
  /// **'Getting your location'**
  String get reportLocationFinding;

  /// No description provided for @reportSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get reportSend;

  /// No description provided for @reportSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get reportSaving;

  /// No description provided for @reportEmpty.
  ///
  /// In en, this message translates to:
  /// **'Describe what you see.'**
  String get reportEmpty;

  /// No description provided for @reportOutsideManila.
  ///
  /// In en, this message translates to:
  /// **'This location is outside Manila City. S.A.G.I.P. covers Manila only.'**
  String get reportOutsideManila;

  /// No description provided for @reportRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent several reports in the last hour. Try again later, or call MDRRMD.'**
  String get reportRateLimited;

  /// No description provided for @reportNoLocation.
  ///
  /// In en, this message translates to:
  /// **'We need your location to send a report. Turn on GPS and try again.'**
  String get reportNoLocation;

  /// No description provided for @reportSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get reportSentTitle;

  /// No description provided for @reportSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on your phone'**
  String get reportSavedTitle;

  /// No description provided for @reportSentBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you. MDRRMD checks reports against others nearby before acting.'**
  String get reportSentBody;

  /// No description provided for @reportSavedBody.
  ///
  /// In en, this message translates to:
  /// **'It will send when you\'re back online.'**
  String get reportSavedBody;

  /// No description provided for @reportSeeQueue.
  ///
  /// In en, this message translates to:
  /// **'See what\'s waiting'**
  String get reportSeeQueue;

  /// No description provided for @reportAnother.
  ///
  /// In en, this message translates to:
  /// **'Send another report'**
  String get reportAnother;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorGeneric;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
