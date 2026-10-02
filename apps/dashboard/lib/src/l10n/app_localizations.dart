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
  /// **'S.A.G.I.P. Command'**
  String get appTitle;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'S.A.G.I.P.'**
  String get brandName;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this data.'**
  String get loadFailed;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to the command board'**
  String get signInTitle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For MDRRMD dispatchers and administrators.'**
  String get signInSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInButton;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get signingIn;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @signInWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get signInWrongCredentials;

  /// No description provided for @signInDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account is turned off. Ask an administrator.'**
  String get signInDisabled;

  /// No description provided for @signInNotStaff.
  ///
  /// In en, this message translates to:
  /// **'This account can\'t use the command board.'**
  String get signInNotStaff;

  /// No description provided for @signInOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Reconnect to sign in.'**
  String get signInOffline;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password? Ask an administrator.'**
  String get forgotPassword;

  /// No description provided for @demoAccountsHint.
  ///
  /// In en, this message translates to:
  /// **'Demo accounts: dispatcher@sagip.test or admin@sagip.test. Password: {password}'**
  String demoAccountsHint(String password);

  /// No description provided for @navCommandBoard.
  ///
  /// In en, this message translates to:
  /// **'Command Board'**
  String get navCommandBoard;

  /// No description provided for @navCrowdReports.
  ///
  /// In en, this message translates to:
  /// **'Crowd reports'**
  String get navCrowdReports;

  /// No description provided for @navUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get navUnits;

  /// No description provided for @navForecast.
  ///
  /// In en, this message translates to:
  /// **'Forecast'**
  String get navForecast;

  /// No description provided for @navVulnerable.
  ///
  /// In en, this message translates to:
  /// **'Vulnerable residents'**
  String get navVulnerable;

  /// No description provided for @navWeather.
  ///
  /// In en, this message translates to:
  /// **'Weather and advisories'**
  String get navWeather;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'NDRRMC reports'**
  String get navReports;

  /// No description provided for @navAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// No description provided for @navResources.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get navResources;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get navSettings;

  /// No description provided for @navAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get navAuditLog;

  /// No description provided for @signalLevel.
  ///
  /// In en, this message translates to:
  /// **'Signal No. {level}'**
  String signalLevel(int level);

  /// No description provided for @noSignal.
  ///
  /// In en, this message translates to:
  /// **'No signal raised'**
  String get noSignal;

  /// No description provided for @rainfall.
  ///
  /// In en, this message translates to:
  /// **'Rainfall {value} mm/hr'**
  String rainfall(String value);

  /// No description provided for @pagasaAt.
  ///
  /// In en, this message translates to:
  /// **'PAGASA, {time}'**
  String pagasaAt(String time);

  /// No description provided for @simulatedFeed.
  ///
  /// In en, this message translates to:
  /// **'Simulated feed'**
  String get simulatedFeed;

  /// No description provided for @linkLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get linkLive;

  /// No description provided for @linkReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get linkReconnecting;

  /// No description provided for @linkOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get linkOffline;

  /// No description provided for @roleResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get roleResident;

  /// No description provided for @roleResponder.
  ///
  /// In en, this message translates to:
  /// **'Responder'**
  String get roleResponder;

  /// No description provided for @roleDispatcher.
  ///
  /// In en, this message translates to:
  /// **'Dispatcher'**
  String get roleDispatcher;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdmin;

  /// No description provided for @roleSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get roleSystem;

  /// No description provided for @userWithRole.
  ///
  /// In en, this message translates to:
  /// **'{name}, {role}'**
  String userWithRole(String name, String role);

  /// No description provided for @switchToLight.
  ///
  /// In en, this message translates to:
  /// **'Switch to light theme'**
  String get switchToLight;

  /// No description provided for @switchToDark.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark theme'**
  String get switchToDark;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @demoConnection.
  ///
  /// In en, this message translates to:
  /// **'Demo: connection'**
  String get demoConnection;

  /// No description provided for @demoGoOffline.
  ///
  /// In en, this message translates to:
  /// **'Simulate going offline'**
  String get demoGoOffline;

  /// No description provided for @demoReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Simulate reconnecting'**
  String get demoReconnecting;

  /// No description provided for @demoGoLive.
  ///
  /// In en, this message translates to:
  /// **'Back online'**
  String get demoGoLive;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing data from {time}. Actions are off until you reconnect.'**
  String offlineBanner(String time);

  /// No description provided for @reconnectingBanner.
  ///
  /// In en, this message translates to:
  /// **'Live updates paused. Reconnecting.'**
  String get reconnectingBanner;

  /// No description provided for @offlineActionsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to take actions.'**
  String get offlineActionsDisabled;

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Triage queue'**
  String get queueTitle;

  /// No description provided for @queueCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active, by priority'**
  String queueCount(int count);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String filterAll(int count);

  /// No description provided for @filterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending {count}'**
  String filterPending(int count);

  /// No description provided for @filterSos.
  ///
  /// In en, this message translates to:
  /// **'SOS {count}'**
  String filterSos(int count);

  /// No description provided for @filterReports.
  ///
  /// In en, this message translates to:
  /// **'Reports {count}'**
  String filterReports(int count);

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No active incidents'**
  String get queueEmpty;

  /// No description provided for @queueEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'New reports will appear here.'**
  String get queueEmptyMessage;

  /// No description provided for @queueFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter.'**
  String get queueFilterEmpty;

  /// No description provided for @sosTitle.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sosTitle;

  /// No description provided for @sosWithType.
  ///
  /// In en, this message translates to:
  /// **'SOS, {type}'**
  String sosWithType(String type);

  /// No description provided for @clusterTitle.
  ///
  /// In en, this message translates to:
  /// **'{type}, {count} reports'**
  String clusterTitle(String type, int count);

  /// No description provided for @clusterUntyped.
  ///
  /// In en, this message translates to:
  /// **'Hazard, {count} reports'**
  String clusterUntyped(int count);

  /// No description provided for @mockLocationWarning.
  ///
  /// In en, this message translates to:
  /// **'Location may be faked'**
  String get mockLocationWarning;

  /// No description provided for @statusWithUnit.
  ///
  /// In en, this message translates to:
  /// **'{status} {unit}'**
  String statusWithUnit(String status, String unit);

  /// No description provided for @statusPendingShort.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPendingShort;

  /// No description provided for @channelApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get channelApp;

  /// No description provided for @channelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get channelSms;

  /// No description provided for @channelBle.
  ///
  /// In en, this message translates to:
  /// **'Nearby phones'**
  String get channelBle;

  /// No description provided for @channelWeb.
  ///
  /// In en, this message translates to:
  /// **'Web form'**
  String get channelWeb;

  /// No description provided for @statusPendingVerification.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get statusPendingVerification;

  /// No description provided for @statusUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get statusUnverified;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get statusAssigned;

  /// No description provided for @statusEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get statusEnRoute;

  /// No description provided for @statusOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get statusOnScene;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

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
  /// **'Structural'**
  String get typeStructural;

  /// No description provided for @vulnSenior.
  ///
  /// In en, this message translates to:
  /// **'Senior citizen'**
  String get vulnSenior;

  /// No description provided for @vulnPwd.
  ///
  /// In en, this message translates to:
  /// **'Person with disability'**
  String get vulnPwd;

  /// No description provided for @vulnPregnant.
  ///
  /// In en, this message translates to:
  /// **'Pregnant'**
  String get vulnPregnant;

  /// No description provided for @vulnOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get vulnOther;

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

  /// No description provided for @unitAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get unitAvailable;

  /// No description provided for @unitEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get unitEnRoute;

  /// No description provided for @unitOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get unitOnScene;

  /// No description provided for @viewMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get viewMap;

  /// No description provided for @viewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get viewList;

  /// No description provided for @layersTitle.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layersTitle;

  /// No description provided for @layerUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get layerUnits;

  /// No description provided for @layerReports.
  ///
  /// In en, this message translates to:
  /// **'Crowd reports'**
  String get layerReports;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @mapAttribution.
  ///
  /// In en, this message translates to:
  /// **'OpenStreetMap contributors'**
  String get mapAttribution;

  /// No description provided for @legendPending.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get legendPending;

  /// No description provided for @legendConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get legendConfirmed;

  /// No description provided for @legendAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get legendAssigned;

  /// No description provided for @legendEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get legendEnRoute;

  /// No description provided for @legendOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get legendOnScene;

  /// No description provided for @legendUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified report'**
  String get legendUnverified;

  /// No description provided for @legendUnitAvailable.
  ///
  /// In en, this message translates to:
  /// **'Unit available'**
  String get legendUnitAvailable;

  /// No description provided for @legendUnitBusy.
  ///
  /// In en, this message translates to:
  /// **'Unit busy'**
  String get legendUnitBusy;

  /// No description provided for @newSosTitle.
  ///
  /// In en, this message translates to:
  /// **'New SOS'**
  String get newSosTitle;

  /// No description provided for @newSosBody.
  ///
  /// In en, this message translates to:
  /// **'{place}, {ago}'**
  String newSosBody(String place, String ago);

  /// No description provided for @colPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get colPriority;

  /// No description provided for @colWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get colWaiting;

  /// No description provided for @colStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get colStatus;

  /// No description provided for @colType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get colType;

  /// No description provided for @colPlace.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get colPlace;

  /// No description provided for @colChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get colChannel;

  /// No description provided for @colVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get colVerified;

  /// No description provided for @colVulnerable.
  ///
  /// In en, this message translates to:
  /// **'Vulnerable'**
  String get colVulnerable;

  /// No description provided for @colUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get colUnit;

  /// No description provided for @severityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get severityCritical;

  /// No description provided for @severityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get severityHigh;

  /// No description provided for @severityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get severityNormal;

  /// No description provided for @drawerIncidentId.
  ///
  /// In en, this message translates to:
  /// **'Incident {id}'**
  String drawerIncidentId(String id);

  /// No description provided for @waitingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting {duration}'**
  String waitingFor(String duration);

  /// No description provided for @rankOf.
  ///
  /// In en, this message translates to:
  /// **'Rank {rank} of {total}'**
  String rankOf(int rank, int total);

  /// No description provided for @locationDetail.
  ///
  /// In en, this message translates to:
  /// **'{coordinates}, from {source}, accurate to {meters} m'**
  String locationDetail(String coordinates, String source, int meters);

  /// No description provided for @locationDetailNoAccuracy.
  ///
  /// In en, this message translates to:
  /// **'{coordinates}, from {source}'**
  String locationDetailNoAccuracy(String coordinates, String source);

  /// Where an incident location came from, after the word from.
  ///
  /// In en, this message translates to:
  /// **'{channel, select, app{the app} sms{SMS} bleRelay{nearby phones} webForm{the web form} other{an unknown source}}'**
  String locationSource(String channel);

  /// No description provided for @incidentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Incident type'**
  String get incidentTypeLabel;

  /// No description provided for @typeSuggested.
  ///
  /// In en, this message translates to:
  /// **'{type} (suggested)'**
  String typeSuggested(String type);

  /// No description provided for @typeNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get typeNotSet;

  /// No description provided for @confirmType.
  ///
  /// In en, this message translates to:
  /// **'Confirm type'**
  String get confirmType;

  /// No description provided for @typeConfirmedSnack.
  ///
  /// In en, this message translates to:
  /// **'Type set to {type}'**
  String typeConfirmedSnack(String type);

  /// No description provided for @verificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get verificationTitle;

  /// No description provided for @checkAccountVerified.
  ///
  /// In en, this message translates to:
  /// **'Registered account, verified mobile number'**
  String get checkAccountVerified;

  /// No description provided for @checkAccountNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Account not verified'**
  String get checkAccountNotVerified;

  /// No description provided for @checkGpsOk.
  ///
  /// In en, this message translates to:
  /// **'Location from phone GPS, not a mock location'**
  String get checkGpsOk;

  /// No description provided for @checkGpsMock.
  ///
  /// In en, this message translates to:
  /// **'The phone reported a mock location. Confirm by call before dispatching.'**
  String get checkGpsMock;

  /// No description provided for @checkNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Not yet confirmed by call or SMS'**
  String get checkNotVerified;

  /// No description provided for @checkVerifiedBy.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by {method}'**
  String checkVerifiedBy(String method);

  /// No description provided for @methodCallback.
  ///
  /// In en, this message translates to:
  /// **'callback'**
  String get methodCallback;

  /// No description provided for @methodSmsReply.
  ///
  /// In en, this message translates to:
  /// **'SMS reply'**
  String get methodSmsReply;

  /// No description provided for @methodOnScene.
  ///
  /// In en, this message translates to:
  /// **'responders on scene'**
  String get methodOnScene;

  /// No description provided for @checkClusterVerified.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by 3 or more reports within 50 m'**
  String get checkClusterVerified;

  /// No description provided for @smsCheckPending.
  ///
  /// In en, this message translates to:
  /// **'SMS check sent. Waiting for a reply.'**
  String get smsCheckPending;

  /// No description provided for @smsReplyReceived.
  ///
  /// In en, this message translates to:
  /// **'The resident replied YES to the SMS check.'**
  String get smsReplyReceived;

  /// No description provided for @callResident.
  ///
  /// In en, this message translates to:
  /// **'Call resident'**
  String get callResident;

  /// No description provided for @sendSmsCheck.
  ///
  /// In en, this message translates to:
  /// **'Send SMS check'**
  String get sendSmsCheck;

  /// No description provided for @smsCheckSentSnack.
  ///
  /// In en, this message translates to:
  /// **'SMS check sent'**
  String get smsCheckSentSnack;

  /// No description provided for @markVerified.
  ///
  /// In en, this message translates to:
  /// **'Mark verified'**
  String get markVerified;

  /// No description provided for @verifiedSnack.
  ///
  /// In en, this message translates to:
  /// **'SOS verified'**
  String get verifiedSnack;

  /// No description provided for @markFalse.
  ///
  /// In en, this message translates to:
  /// **'Mark as false report'**
  String get markFalse;

  /// No description provided for @residentTitle.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get residentTitle;

  /// No description provided for @showNumber.
  ///
  /// In en, this message translates to:
  /// **'Show number'**
  String get showNumber;

  /// No description provided for @peopleCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person} other{{count} people}}'**
  String peopleCount(int count);

  /// No description provided for @residentNote.
  ///
  /// In en, this message translates to:
  /// **'Note from the resident'**
  String get residentNote;

  /// No description provided for @clusterReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports in this cluster'**
  String get clusterReportsTitle;

  /// No description provided for @priorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Why it\'s ranked here'**
  String get priorityTitle;

  /// No description provided for @factorSos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get factorSos;

  /// No description provided for @factorCluster.
  ///
  /// In en, this message translates to:
  /// **'Confirmed cluster'**
  String get factorCluster;

  /// No description provided for @factorVulnerable.
  ///
  /// In en, this message translates to:
  /// **'Vulnerable household'**
  String get factorVulnerable;

  /// No description provided for @factorWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting time'**
  String get factorWaiting;

  /// No description provided for @factorMockLocation.
  ///
  /// In en, this message translates to:
  /// **'Possible mock location'**
  String get factorMockLocation;

  /// No description provided for @provisionalRules.
  ///
  /// In en, this message translates to:
  /// **'Provisional weights until MDRRMD\'s triage SOP is added.'**
  String get provisionalRules;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'{points, plural, =1{1 pt} other{{points} pts}}'**
  String points(int points);

  /// No description provided for @suggestedUnitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested units'**
  String get suggestedUnitsTitle;

  /// No description provided for @suggestedByRoad.
  ///
  /// In en, this message translates to:
  /// **'Available units, by travel time on the road network'**
  String get suggestedByRoad;

  /// No description provided for @suggestedByDistance.
  ///
  /// In en, this message translates to:
  /// **'Available units, estimated by straight-line distance'**
  String get suggestedByDistance;

  /// No description provided for @chooseAnotherUnit.
  ///
  /// In en, this message translates to:
  /// **'Choose another unit'**
  String get chooseAnotherUnit;

  /// No description provided for @noAvailableUnits.
  ///
  /// In en, this message translates to:
  /// **'No available units'**
  String get noAvailableUnits;

  /// No description provided for @noAvailableUnitsMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose another unit or wait for one to become available.'**
  String get noAvailableUnitsMessage;

  /// No description provided for @etaMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String etaMinutes(int minutes);

  /// No description provided for @distanceKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String distanceKm(String km);

  /// No description provided for @assignUnit.
  ///
  /// In en, this message translates to:
  /// **'Assign {unit}'**
  String assignUnit(String unit);

  /// No description provided for @reassignUnit.
  ///
  /// In en, this message translates to:
  /// **'Reassign to {unit}'**
  String reassignUnit(String unit);

  /// No description provided for @assignedSnack.
  ///
  /// In en, this message translates to:
  /// **'{unit} assigned'**
  String assignedSnack(String unit);

  /// No description provided for @assignedUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Assigned unit'**
  String get assignedUnitTitle;

  /// No description provided for @markResolved.
  ///
  /// In en, this message translates to:
  /// **'Mark resolved'**
  String get markResolved;

  /// No description provided for @resolvedSnack.
  ///
  /// In en, this message translates to:
  /// **'Incident resolved'**
  String get resolvedSnack;

  /// No description provided for @unitStationCrew.
  ///
  /// In en, this message translates to:
  /// **'{station}, crew of {crew}'**
  String unitStationCrew(String station, int crew);

  /// No description provided for @timelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timelineTitle;

  /// No description provided for @eventReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get eventReceived;

  /// No description provided for @eventSmsCheckSent.
  ///
  /// In en, this message translates to:
  /// **'SMS check sent'**
  String get eventSmsCheckSent;

  /// No description provided for @eventSmsReply.
  ///
  /// In en, this message translates to:
  /// **'SMS reply received'**
  String get eventSmsReply;

  /// No description provided for @eventVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get eventVerified;

  /// No description provided for @eventTypeConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Type confirmed'**
  String get eventTypeConfirmed;

  /// No description provided for @eventAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get eventAssigned;

  /// No description provided for @eventEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En route'**
  String get eventEnRoute;

  /// No description provided for @eventOnScene.
  ///
  /// In en, this message translates to:
  /// **'On scene'**
  String get eventOnScene;

  /// No description provided for @eventResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get eventResolved;

  /// No description provided for @eventFalseReport.
  ///
  /// In en, this message translates to:
  /// **'Marked as false report'**
  String get eventFalseReport;

  /// No description provided for @incidentClosed.
  ///
  /// In en, this message translates to:
  /// **'This incident was closed.'**
  String get incidentClosed;

  /// No description provided for @overrideTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign {unit} instead of the top suggestion?'**
  String overrideTitle(String unit);

  /// No description provided for @overrideBody.
  ///
  /// In en, this message translates to:
  /// **'{top} is about {minutes} min closer. You can still choose another unit. Add a reason so the audit log explains the choice.'**
  String overrideBody(String top, int minutes);

  /// No description provided for @overrideReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get overrideReasonLabel;

  /// No description provided for @reasonEquipment.
  ///
  /// In en, this message translates to:
  /// **'Top unit lacks the needed equipment'**
  String get reasonEquipment;

  /// No description provided for @reasonBusy.
  ///
  /// In en, this message translates to:
  /// **'Top unit is handling another call'**
  String get reasonBusy;

  /// No description provided for @reasonBlocked.
  ///
  /// In en, this message translates to:
  /// **'Known road blockage on the suggested route'**
  String get reasonBlocked;

  /// No description provided for @reasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reasonOther;

  /// No description provided for @overrideNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get overrideNoteLabel;

  /// No description provided for @overrideReasonMissing.
  ///
  /// In en, this message translates to:
  /// **'Choose a reason.'**
  String get overrideReasonMissing;

  /// No description provided for @chooseUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a unit'**
  String get chooseUnitTitle;

  /// No description provided for @chooseUnitBody.
  ///
  /// In en, this message translates to:
  /// **'Units that are available now, nearest first.'**
  String get chooseUnitBody;

  /// No description provided for @falseReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark as a false report?'**
  String get falseReportTitle;

  /// No description provided for @falseReportBody.
  ///
  /// In en, this message translates to:
  /// **'It leaves the queue, and any assigned unit becomes available. This is recorded in the audit log.'**
  String get falseReportBody;

  /// No description provided for @falseReportDone.
  ///
  /// In en, this message translates to:
  /// **'Marked as a false report'**
  String get falseReportDone;

  /// No description provided for @callTitle.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String callTitle(String name);

  /// No description provided for @callBody.
  ///
  /// In en, this message translates to:
  /// **'Call this number from the command center phone. Viewing it is recorded in the audit log.'**
  String get callBody;

  /// No description provided for @copyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get copyNumber;

  /// No description provided for @copiedSnack.
  ///
  /// In en, this message translates to:
  /// **'Number copied'**
  String get copiedSnack;

  /// No description provided for @errorOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Reconnect and try again.'**
  String get errorOffline;

  /// No description provided for @errorUnitTaken.
  ///
  /// In en, this message translates to:
  /// **'That unit is no longer available. Choose another.'**
  String get errorUnitTaken;

  /// No description provided for @errorAlreadyAssigned.
  ///
  /// In en, this message translates to:
  /// **'This incident already has that unit.'**
  String get errorAlreadyAssigned;

  /// No description provided for @errorIncidentClosed.
  ///
  /// In en, this message translates to:
  /// **'This incident was already closed.'**
  String get errorIncidentClosed;

  /// No description provided for @errorNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Your account can\'t do this.'**
  String get errorNotAllowed;

  /// No description provided for @errorInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'That value is outside the allowed range.'**
  String get errorInvalidValue;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'That item no longer exists. Reload the page.'**
  String get errorNotFound;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorGeneric;

  /// No description provided for @crowdReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Crowd reports'**
  String get crowdReportsTitle;

  /// No description provided for @crowdWindow.
  ///
  /// In en, this message translates to:
  /// **'Last 60 minutes'**
  String get crowdWindow;

  /// No description provided for @crowdSummary.
  ///
  /// In en, this message translates to:
  /// **'{total} reports: {clusters} in confirmed clusters, {singles} unverified'**
  String crowdSummary(int total, int clusters, int singles);

  /// No description provided for @clusterCardTitle.
  ///
  /// In en, this message translates to:
  /// **'{type}, {count} reports within 50 m'**
  String clusterCardTitle(String type, int count);

  /// No description provided for @clusterInQueue.
  ///
  /// In en, this message translates to:
  /// **'In the triage queue'**
  String get clusterInQueue;

  /// No description provided for @openInQueue.
  ///
  /// In en, this message translates to:
  /// **'Open in triage queue'**
  String get openInQueue;

  /// No description provided for @unverifiedSection.
  ///
  /// In en, this message translates to:
  /// **'Unverified, waiting for nearby reports'**
  String get unverifiedSection;

  /// No description provided for @reportMeta.
  ///
  /// In en, this message translates to:
  /// **'{time}, {channel}, suggested {type} ({percent}%)'**
  String reportMeta(String time, String channel, String type, int percent);

  /// No description provided for @crowdRule.
  ///
  /// In en, this message translates to:
  /// **'Three or more reports within 50 m in the last 60 minutes become a confirmed incident. A single report is never confirmed on its own.'**
  String get crowdRule;

  /// No description provided for @crowdEmpty.
  ///
  /// In en, this message translates to:
  /// **'No crowd reports in the last 60 minutes.'**
  String get crowdEmpty;

  /// No description provided for @unitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsTitle;

  /// No description provided for @countAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} available'**
  String countAvailable(int count);

  /// No description provided for @countEnRoute.
  ///
  /// In en, this message translates to:
  /// **'{count} en route'**
  String countEnRoute(int count);

  /// No description provided for @countOnScene.
  ///
  /// In en, this message translates to:
  /// **'{count} on scene'**
  String countOnScene(int count);

  /// No description provided for @colCallSign.
  ///
  /// In en, this message translates to:
  /// **'Call sign'**
  String get colCallSign;

  /// No description provided for @colUnitType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get colUnitType;

  /// No description provided for @colStation.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get colStation;

  /// No description provided for @colCrew.
  ///
  /// In en, this message translates to:
  /// **'Crew'**
  String get colCrew;

  /// No description provided for @colIncident.
  ///
  /// In en, this message translates to:
  /// **'Current incident'**
  String get colIncident;

  /// No description provided for @colLastGps.
  ///
  /// In en, this message translates to:
  /// **'Last GPS'**
  String get colLastGps;

  /// No description provided for @staleGps.
  ///
  /// In en, this message translates to:
  /// **'Stale'**
  String get staleGps;

  /// No description provided for @unitsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No units set up'**
  String get unitsEmpty;

  /// No description provided for @unitsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'An administrator can add units in Resources.'**
  String get unitsEmptyMessage;

  /// No description provided for @assignedNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Assigned, waiting for crew'**
  String get assignedNotStarted;

  /// No description provided for @vulnerableTitle.
  ///
  /// In en, this message translates to:
  /// **'Vulnerable Resident Priority List'**
  String get vulnerableTitle;

  /// No description provided for @vulnerablePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only dispatchers and administrators can see this list (Data Privacy Act, RA 10173).'**
  String get vulnerablePrivacy;

  /// No description provided for @colResident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get colResident;

  /// No description provided for @colHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get colHousehold;

  /// No description provided for @colConsent.
  ///
  /// In en, this message translates to:
  /// **'Consent given'**
  String get colConsent;

  /// No description provided for @colUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get colUpdated;

  /// No description provided for @colContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get colContact;

  /// No description provided for @vulnerableEmpty.
  ///
  /// In en, this message translates to:
  /// **'No registered vulnerable residents yet.'**
  String get vulnerableEmpty;

  /// No description provided for @weatherTitle.
  ///
  /// In en, this message translates to:
  /// **'Weather and advisories'**
  String get weatherTitle;

  /// No description provided for @signalCard.
  ///
  /// In en, this message translates to:
  /// **'Tropical cyclone wind signal'**
  String get signalCard;

  /// No description provided for @rainfallCard.
  ///
  /// In en, this message translates to:
  /// **'Rainfall intensity'**
  String get rainfallCard;

  /// No description provided for @stormSurgeCard.
  ///
  /// In en, this message translates to:
  /// **'Storm surge'**
  String get stormSurgeCard;

  /// No description provided for @noAdvisory.
  ///
  /// In en, this message translates to:
  /// **'No advisory'**
  String get noAdvisory;

  /// No description provided for @issuedAt.
  ///
  /// In en, this message translates to:
  /// **'Issued {time}'**
  String issuedAt(String time);

  /// No description provided for @rainfallValue.
  ///
  /// In en, this message translates to:
  /// **'{value} mm/hr'**
  String rainfallValue(String value);

  /// No description provided for @simulatedWeatherNote.
  ///
  /// In en, this message translates to:
  /// **'Replaying recorded data. The live PAGASA feed is not connected yet.'**
  String get simulatedWeatherNote;

  /// No description provided for @efcosTitle.
  ///
  /// In en, this message translates to:
  /// **'EFCOS water levels'**
  String get efcosTitle;

  /// No description provided for @efcosNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected yet. Alerts use PAGASA thresholds only (FR5 fallback).'**
  String get efcosNotConnected;

  /// No description provided for @phivolcsTitle.
  ///
  /// In en, this message translates to:
  /// **'PHIVOLCS advisories'**
  String get phivolcsTitle;

  /// No description provided for @phivolcsNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected yet. Advisories will be relayed to residents as notifications (FR14).'**
  String get phivolcsNotConnected;

  /// No description provided for @auditTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditTitle;

  /// No description provided for @auditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every dispatch action, status change, and verification, with who did it (FR11).'**
  String get auditSubtitle;

  /// No description provided for @colTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get colTime;

  /// No description provided for @colAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get colAccount;

  /// No description provided for @colAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get colAction;

  /// No description provided for @colTarget.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get colTarget;

  /// No description provided for @colDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get colDetail;

  /// No description provided for @actionVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get actionVerified;

  /// No description provided for @actionFalseReport.
  ///
  /// In en, this message translates to:
  /// **'Marked false report'**
  String get actionFalseReport;

  /// No description provided for @actionTypeConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed type'**
  String get actionTypeConfirmed;

  /// No description provided for @actionAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned unit'**
  String get actionAssigned;

  /// No description provided for @actionReassigned.
  ///
  /// In en, this message translates to:
  /// **'Reassigned unit'**
  String get actionReassigned;

  /// No description provided for @actionStatusChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed status'**
  String get actionStatusChanged;

  /// No description provided for @actionResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get actionResolved;

  /// No description provided for @actionSmsCheck.
  ///
  /// In en, this message translates to:
  /// **'Sent SMS check'**
  String get actionSmsCheck;

  /// No description provided for @actionContactViewed.
  ///
  /// In en, this message translates to:
  /// **'Viewed contact number'**
  String get actionContactViewed;

  /// No description provided for @actionSettingChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed a setting'**
  String get actionSettingChanged;

  /// No description provided for @analyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dispatch and response times for incidents received in the period (Objective 1).'**
  String get analyticsSubtitle;

  /// No description provided for @periodDay.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get periodDay;

  /// No description provided for @periodWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get periodWeek;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get periodMonth;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @analyticsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not enough data for this period.'**
  String get analyticsEmpty;

  /// No description provided for @kpiIncidents.
  ///
  /// In en, this message translates to:
  /// **'Incidents'**
  String get kpiIncidents;

  /// No description provided for @kpiIncidentsFooter.
  ///
  /// In en, this message translates to:
  /// **'{resolved} resolved · {falseReports} false reports'**
  String kpiIncidentsFooter(int resolved, int falseReports);

  /// No description provided for @kpiDispatch.
  ///
  /// In en, this message translates to:
  /// **'Median dispatch time'**
  String get kpiDispatch;

  /// No description provided for @kpiDispatchFooter.
  ///
  /// In en, this message translates to:
  /// **'Received to unit assigned · average {average}'**
  String kpiDispatchFooter(String average);

  /// No description provided for @kpiResponse.
  ///
  /// In en, this message translates to:
  /// **'Median response time'**
  String get kpiResponse;

  /// No description provided for @kpiResponseFooter.
  ///
  /// In en, this message translates to:
  /// **'Received to on scene · average {average}'**
  String kpiResponseFooter(String average);

  /// No description provided for @kpiVerify.
  ///
  /// In en, this message translates to:
  /// **'Average verification time'**
  String get kpiVerify;

  /// No description provided for @kpiVerifyFooter.
  ///
  /// In en, this message translates to:
  /// **'Received to verified'**
  String get kpiVerifyFooter;

  /// No description provided for @kpiSosChannels.
  ///
  /// In en, this message translates to:
  /// **'SOS by channel'**
  String get kpiSosChannels;

  /// No description provided for @kpiDijkstra.
  ///
  /// In en, this message translates to:
  /// **'Dijkstra run time'**
  String get kpiDijkstra;

  /// No description provided for @kpiDijkstraValue.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String kpiDijkstraValue(String ms);

  /// No description provided for @kpiDijkstraFooter.
  ///
  /// In en, this message translates to:
  /// **'Average of {runs} runs · 95th percentile {p95} ms'**
  String kpiDijkstraFooter(int runs, String p95);

  /// No description provided for @kpiDijkstraNone.
  ///
  /// In en, this message translates to:
  /// **'No timed runs in this period'**
  String get kpiDijkstraNone;

  /// No description provided for @channelCount.
  ///
  /// In en, this message translates to:
  /// **'{channel} {count}'**
  String channelCount(String channel, int count);

  /// No description provided for @baselineNote.
  ///
  /// In en, this message translates to:
  /// **'Objective 1 compares these times with MDRRMD\'s before S.A.G.I.P. Those records have not arrived yet (Table 3.1 item 2).'**
  String get baselineNote;

  /// No description provided for @dailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Incidents per day'**
  String get dailyTitle;

  /// No description provided for @dailyAvgResponse.
  ///
  /// In en, this message translates to:
  /// **'average response {time}'**
  String dailyAvgResponse(String time);

  /// No description provided for @byTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'By incident type'**
  String get byTypeTitle;

  /// No description provided for @byBarangayTitle.
  ///
  /// In en, this message translates to:
  /// **'Busiest barangays'**
  String get byBarangayTitle;

  /// No description provided for @byUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'By unit'**
  String get byUnitTitle;

  /// No description provided for @colBarangay.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get colBarangay;

  /// No description provided for @colIncidents.
  ///
  /// In en, this message translates to:
  /// **'Incidents'**
  String get colIncidents;

  /// No description provided for @colJobs.
  ///
  /// In en, this message translates to:
  /// **'Jobs'**
  String get colJobs;

  /// No description provided for @colAvgDispatch.
  ///
  /// In en, this message translates to:
  /// **'Average dispatch'**
  String get colAvgDispatch;

  /// No description provided for @colAvgResponse.
  ///
  /// In en, this message translates to:
  /// **'Average response'**
  String get colAvgResponse;

  /// No description provided for @colAvgTravel.
  ///
  /// In en, this message translates to:
  /// **'Average travel'**
  String get colAvgTravel;

  /// No description provided for @noValue.
  ///
  /// In en, this message translates to:
  /// **'–'**
  String get noValue;

  /// No description provided for @myAccount.
  ///
  /// In en, this message translates to:
  /// **'My account'**
  String get myAccount;

  /// No description provided for @demoExpireSession.
  ///
  /// In en, this message translates to:
  /// **'Simulate the session expiring'**
  String get demoExpireSession;

  /// No description provided for @accountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your account, display, and password.'**
  String get accountSubtitle;

  /// No description provided for @accountDetails.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountDetails;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// No description provided for @accountRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get accountRole;

  /// No description provided for @displayTitle.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displayTitle;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as this computer'**
  String get themeSystem;

  /// No description provided for @passwordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get passwordTitle;

  /// No description provided for @passwordCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get passwordCurrent;

  /// No description provided for @passwordNew.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get passwordNew;

  /// No description provided for @passwordConfirm.
  ///
  /// In en, this message translates to:
  /// **'New password again'**
  String get passwordConfirm;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least {min} characters.'**
  String passwordTooShort(int min);

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two new passwords are different.'**
  String get passwordMismatch;

  /// No description provided for @passwordSame.
  ///
  /// In en, this message translates to:
  /// **'Choose a password different from the current one.'**
  String get passwordSame;

  /// No description provided for @passwordWrong.
  ///
  /// In en, this message translates to:
  /// **'The current password is not right.'**
  String get passwordWrong;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @passwordSave.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get passwordSave;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutsTitle;

  /// No description provided for @shortcutQueue.
  ///
  /// In en, this message translates to:
  /// **'Select the next or previous incident in the Triage Queue (opens it)'**
  String get shortcutQueue;

  /// No description provided for @shortcutClose.
  ///
  /// In en, this message translates to:
  /// **'Close the incident drawer'**
  String get shortcutClose;

  /// No description provided for @shortcutUpDown.
  ///
  /// In en, this message translates to:
  /// **'Up or Down arrow'**
  String get shortcutUpDown;

  /// No description provided for @shortcutEsc.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get shortcutEsc;

  /// No description provided for @sessionExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Your session expired'**
  String get sessionExpiredTitle;

  /// No description provided for @sessionExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to go back to where you were. Nothing you saved was lost.'**
  String get sessionExpiredMessage;

  /// No description provided for @signInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgain;

  /// No description provided for @accountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Staff logins and resident accounts. Every change is recorded in the audit log.'**
  String get accountsSubtitle;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @tabStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get tabStaff;

  /// No description provided for @tabResponders.
  ///
  /// In en, this message translates to:
  /// **'Responders'**
  String get tabResponders;

  /// No description provided for @tabResidents.
  ///
  /// In en, this message translates to:
  /// **'Residents'**
  String get tabResidents;

  /// No description provided for @colName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get colName;

  /// No description provided for @colRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get colRole;

  /// No description provided for @colNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get colNumber;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get statusDeactivated;

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get statusSuspended;

  /// No description provided for @editAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get editAccount;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPassword;

  /// No description provided for @deactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// No description provided for @reactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// No description provided for @suspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get suspend;

  /// No description provided for @liftSuspension.
  ///
  /// In en, this message translates to:
  /// **'Lift suspension'**
  String get liftSuspension;

  /// No description provided for @ownAccountHint.
  ///
  /// In en, this message translates to:
  /// **'This is your account. Change it on My account.'**
  String get ownAccountHint;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get fieldRole;

  /// No description provided for @fieldUnitOptional.
  ///
  /// In en, this message translates to:
  /// **'Unit (responders)'**
  String get fieldUnitOptional;

  /// No description provided for @fieldEmailError.
  ///
  /// In en, this message translates to:
  /// **'Enter an email address like name@example.com.'**
  String get fieldEmailError;

  /// No description provided for @fieldNameError.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get fieldNameError;

  /// No description provided for @tempPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Temporary password'**
  String get tempPasswordTitle;

  /// No description provided for @tempPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Give this temporary password to {name}. They should change it on My account after signing in. It is not shown again.'**
  String tempPasswordBody(String name);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset the password for {name}?'**
  String resetTitle(String name);

  /// No description provided for @resetBody.
  ///
  /// In en, this message translates to:
  /// **'They are signed out and need the new temporary password to sign in.'**
  String get resetBody;

  /// No description provided for @deactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate {name}?'**
  String deactivateTitle(String name);

  /// No description provided for @deactivateBody.
  ///
  /// In en, this message translates to:
  /// **'They are signed out at once and cannot sign in until an admin reactivates the account. Their records stay.'**
  String get deactivateBody;

  /// No description provided for @suspendTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}?'**
  String suspendTitle(String name);

  /// No description provided for @suspendBody.
  ///
  /// In en, this message translates to:
  /// **'They cannot send crowd reports. An SOS still reaches MDRRMD, marked not account-verified, so a dispatcher calls back.'**
  String get suspendBody;

  /// No description provided for @accountSaved.
  ///
  /// In en, this message translates to:
  /// **'{name} saved'**
  String accountSaved(String name);

  /// No description provided for @accountDeactivatedSnack.
  ///
  /// In en, this message translates to:
  /// **'{name} deactivated'**
  String accountDeactivatedSnack(String name);

  /// No description provided for @accountReactivatedSnack.
  ///
  /// In en, this message translates to:
  /// **'{name} reactivated'**
  String accountReactivatedSnack(String name);

  /// No description provided for @residentSuspendedSnack.
  ///
  /// In en, this message translates to:
  /// **'{name} suspended'**
  String residentSuspendedSnack(String name);

  /// No description provided for @residentRestoredSnack.
  ///
  /// In en, this message translates to:
  /// **'Suspension lifted for {name}'**
  String residentRestoredSnack(String name);

  /// No description provided for @accountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Create the first one.'**
  String get accountsEmpty;

  /// No description provided for @residentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No resident accounts yet.'**
  String get residentsEmpty;

  /// No description provided for @errorOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'You cannot do that to your own account here. Use My account.'**
  String get errorOwnAccount;

  /// No description provided for @errorLastAdmin.
  ///
  /// In en, this message translates to:
  /// **'At least one admin must stay active.'**
  String get errorLastAdmin;

  /// No description provided for @actionAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Created an account'**
  String get actionAccountCreated;

  /// No description provided for @actionAccountUpdated.
  ///
  /// In en, this message translates to:
  /// **'Edited an account'**
  String get actionAccountUpdated;

  /// No description provided for @actionAccountDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated an account'**
  String get actionAccountDeactivated;

  /// No description provided for @actionAccountReactivated.
  ///
  /// In en, this message translates to:
  /// **'Reactivated an account'**
  String get actionAccountReactivated;

  /// No description provided for @actionPasswordReset.
  ///
  /// In en, this message translates to:
  /// **'Reset a password'**
  String get actionPasswordReset;

  /// No description provided for @actionResidentSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended a resident'**
  String get actionResidentSuspended;

  /// No description provided for @actionResidentRestored.
  ///
  /// In en, this message translates to:
  /// **'Lifted a suspension'**
  String get actionResidentRestored;

  /// No description provided for @resourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Units and the responders who crew them. Every change is recorded in the audit log.'**
  String get resourcesSubtitle;

  /// No description provided for @addUnit.
  ///
  /// In en, this message translates to:
  /// **'Add unit'**
  String get addUnit;

  /// No description provided for @editUnit.
  ///
  /// In en, this message translates to:
  /// **'Edit unit'**
  String get editUnit;

  /// No description provided for @unitsTitleA2.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsTitleA2;

  /// No description provided for @rosterTitle.
  ///
  /// In en, this message translates to:
  /// **'Responder roster'**
  String get rosterTitle;

  /// No description provided for @rosterNote.
  ///
  /// In en, this message translates to:
  /// **'A responder works for the unit chosen here. Responder accounts are created in Accounts.'**
  String get rosterNote;

  /// No description provided for @rosterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No responder accounts yet.'**
  String get rosterEmpty;

  /// No description provided for @colResponders.
  ///
  /// In en, this message translates to:
  /// **'Responders'**
  String get colResponders;

  /// No description provided for @colEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get colEmail;

  /// No description provided for @retire.
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get retire;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @retiredChip.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get retiredChip;

  /// No description provided for @retireTitle.
  ///
  /// In en, this message translates to:
  /// **'Retire {callSign}?'**
  String retireTitle(String callSign);

  /// No description provided for @retireBody.
  ///
  /// In en, this message translates to:
  /// **'It will not be dispatched and its responders come off it. Its past jobs stay in the records. You can restore it later.'**
  String get retireBody;

  /// No description provided for @retireBusy.
  ///
  /// In en, this message translates to:
  /// **'Only a unit that is Available with no job can be retired.'**
  String get retireBusy;

  /// No description provided for @unitSaved.
  ///
  /// In en, this message translates to:
  /// **'{callSign} saved'**
  String unitSaved(String callSign);

  /// No description provided for @unitRetiredSnack.
  ///
  /// In en, this message translates to:
  /// **'{callSign} retired'**
  String unitRetiredSnack(String callSign);

  /// No description provided for @unitRestoredSnack.
  ///
  /// In en, this message translates to:
  /// **'{callSign} restored'**
  String unitRestoredSnack(String callSign);

  /// No description provided for @rosterSaved.
  ///
  /// In en, this message translates to:
  /// **'Roster updated'**
  String get rosterSaved;

  /// No description provided for @noUnit.
  ///
  /// In en, this message translates to:
  /// **'No unit'**
  String get noUnit;

  /// No description provided for @fieldCallSign.
  ///
  /// In en, this message translates to:
  /// **'Call sign'**
  String get fieldCallSign;

  /// No description provided for @fieldCallSignHint.
  ///
  /// In en, this message translates to:
  /// **'For example R-12'**
  String get fieldCallSignHint;

  /// No description provided for @fieldCallSignError.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, and dashes, up to 12 characters.'**
  String get fieldCallSignError;

  /// No description provided for @fieldUnitType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get fieldUnitType;

  /// No description provided for @fieldStation.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get fieldStation;

  /// No description provided for @fieldStationHint.
  ///
  /// In en, this message translates to:
  /// **'For example Sampaloc station'**
  String get fieldStationHint;

  /// No description provided for @fieldStationError.
  ///
  /// In en, this message translates to:
  /// **'Enter the station.'**
  String get fieldStationError;

  /// No description provided for @fieldCrew.
  ///
  /// In en, this message translates to:
  /// **'Crew size'**
  String get fieldCrew;

  /// No description provided for @fieldCrewError.
  ///
  /// In en, this message translates to:
  /// **'Use a number from 1 to 50.'**
  String get fieldCrewError;

  /// No description provided for @errorAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Another unit already uses that call sign.'**
  String get errorAlreadyExists;

  /// No description provided for @actionUnitAdded.
  ///
  /// In en, this message translates to:
  /// **'Added a unit'**
  String get actionUnitAdded;

  /// No description provided for @actionUnitEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited a unit'**
  String get actionUnitEdited;

  /// No description provided for @actionUnitRetired.
  ///
  /// In en, this message translates to:
  /// **'Retired a unit'**
  String get actionUnitRetired;

  /// No description provided for @actionUnitRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored a unit'**
  String get actionUnitRestored;

  /// No description provided for @actionRosterChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed the roster'**
  String get actionRosterChanged;

  /// No description provided for @configSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Changes apply at once for every dispatcher and are recorded in the audit log.'**
  String get configSubtitle;

  /// No description provided for @configPriorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Triage Queue priority'**
  String get configPriorityTitle;

  /// No description provided for @settingSos.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get settingSos;

  /// No description provided for @settingCluster.
  ///
  /// In en, this message translates to:
  /// **'Confirmed cluster of crowd reports'**
  String get settingCluster;

  /// No description provided for @settingVulnerable.
  ///
  /// In en, this message translates to:
  /// **'Vulnerable household'**
  String get settingVulnerable;

  /// No description provided for @settingWaitingPerMinute.
  ///
  /// In en, this message translates to:
  /// **'Points per minute of waiting'**
  String get settingWaitingPerMinute;

  /// No description provided for @settingWaitingMax.
  ///
  /// In en, this message translates to:
  /// **'Most points for waiting'**
  String get settingWaitingMax;

  /// No description provided for @settingMockLocation.
  ///
  /// In en, this message translates to:
  /// **'Possible mock location'**
  String get settingMockLocation;

  /// No description provided for @settingCriticalAt.
  ///
  /// In en, this message translates to:
  /// **'Critical from'**
  String get settingCriticalAt;

  /// No description provided for @settingHighAt.
  ///
  /// In en, this message translates to:
  /// **'High from'**
  String get settingHighAt;

  /// No description provided for @settingRange.
  ///
  /// In en, this message translates to:
  /// **'{min} to {max}'**
  String settingRange(String min, String max);

  /// No description provided for @settingOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Use a number from {min} to {max}.'**
  String settingOutOfRange(String min, String max);

  /// No description provided for @settingNotNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a number.'**
  String get settingNotNumber;

  /// No description provided for @settingHighAboveCritical.
  ///
  /// In en, this message translates to:
  /// **'High must be at or below Critical.'**
  String get settingHighAboveCritical;

  /// No description provided for @settingLastChanged.
  ///
  /// In en, this message translates to:
  /// **'Last changed by {name}'**
  String settingLastChanged(String name);

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @previewTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue with these values'**
  String get previewTitle;

  /// No description provided for @previewNote.
  ///
  /// In en, this message translates to:
  /// **'Active incidents ranked now with the values above, before you save.'**
  String get previewNote;

  /// No description provided for @previewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No active incidents to rank.'**
  String get previewEmpty;

  /// No description provided for @algorithmsTitle.
  ///
  /// In en, this message translates to:
  /// **'Algorithm parameters'**
  String get algorithmsTitle;

  /// No description provided for @algorithmsNote.
  ///
  /// In en, this message translates to:
  /// **'Set in the thesis. Changes need team agreement.'**
  String get algorithmsNote;

  /// No description provided for @algDbscan.
  ///
  /// In en, this message translates to:
  /// **'DBSCAN clustering'**
  String get algDbscan;

  /// No description provided for @algDbscanValue.
  ///
  /// In en, this message translates to:
  /// **'50 m radius, 3 reports, reports from the last 60 minutes'**
  String get algDbscanValue;

  /// No description provided for @algDijkstra.
  ///
  /// In en, this message translates to:
  /// **'Dijkstra routing'**
  String get algDijkstra;

  /// No description provided for @algDijkstraValue.
  ///
  /// In en, this message translates to:
  /// **'{nodes} intersections, {edges} road segments, OpenStreetMap data from {date}'**
  String algDijkstraValue(int nodes, int edges, String date);

  /// No description provided for @algDijkstraLoading.
  ///
  /// In en, this message translates to:
  /// **'Road graph not loaded yet'**
  String get algDijkstraLoading;

  /// No description provided for @algSpeeds.
  ///
  /// In en, this message translates to:
  /// **'Road speeds'**
  String get algSpeeds;

  /// No description provided for @algSpeedsValue.
  ///
  /// In en, this message translates to:
  /// **'Provisional, by road class; to be tuned with MDRRMD dispatch records'**
  String get algSpeedsValue;

  /// No description provided for @algLstm.
  ///
  /// In en, this message translates to:
  /// **'LSTM forecast'**
  String get algLstm;

  /// No description provided for @algLstmValue.
  ///
  /// In en, this message translates to:
  /// **'14-day window, 64 then 32 units, dropout 0.2 (not trained yet)'**
  String get algLstmValue;

  /// No description provided for @algKde.
  ///
  /// In en, this message translates to:
  /// **'KDE hotspots'**
  String get algKde;

  /// No description provided for @algKdeValue.
  ///
  /// In en, this message translates to:
  /// **'Gaussian kernel, bandwidth 100 to 500 m by cross-validation (not trained yet)'**
  String get algKdeValue;

  /// No description provided for @algClassifier.
  ///
  /// In en, this message translates to:
  /// **'Incident type classifier'**
  String get algClassifier;

  /// No description provided for @algClassifierValue.
  ///
  /// In en, this message translates to:
  /// **'TF-IDF on words and word pairs, 4 types. Sample model: trained on made-up descriptions until the MDRRMD set arrives; a report it is under 50% sure of is left untagged'**
  String get algClassifierValue;

  /// No description provided for @configReportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Crowd reports'**
  String get configReportsTitle;

  /// No description provided for @configReportsNote.
  ///
  /// In en, this message translates to:
  /// **'The limit applies to each resident account, across the app and the web form (FR15).'**
  String get configReportsNote;

  /// No description provided for @settingReportsPerHour.
  ///
  /// In en, this message translates to:
  /// **'Reports per account each hour'**
  String get settingReportsPerHour;

  /// No description provided for @configAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alert thresholds'**
  String get configAlertsTitle;

  /// No description provided for @configAlertsNote.
  ///
  /// In en, this message translates to:
  /// **'A PAGASA reading at or above a threshold raises an alert for residents by itself (FR5). Provisional values until MDRRMD confirms them. EFCOS water levels are not connected yet.'**
  String get configAlertsNote;

  /// No description provided for @settingRainfallWarning.
  ///
  /// In en, this message translates to:
  /// **'Rainfall warning, mm per hour'**
  String get settingRainfallWarning;

  /// No description provided for @settingRainfallCritical.
  ///
  /// In en, this message translates to:
  /// **'Rainfall critical, mm per hour'**
  String get settingRainfallCritical;

  /// No description provided for @settingSignalWarning.
  ///
  /// In en, this message translates to:
  /// **'Wind signal warning'**
  String get settingSignalWarning;

  /// No description provided for @settingSignalCritical.
  ///
  /// In en, this message translates to:
  /// **'Wind signal critical'**
  String get settingSignalCritical;

  /// No description provided for @settingSurgeWarning.
  ///
  /// In en, this message translates to:
  /// **'Storm surge warning, metres'**
  String get settingSurgeWarning;

  /// No description provided for @settingSurgeCritical.
  ///
  /// In en, this message translates to:
  /// **'Storm surge critical, metres'**
  String get settingSurgeCritical;

  /// No description provided for @settingWarningAboveCritical.
  ///
  /// In en, this message translates to:
  /// **'Warning must be at or below Critical.'**
  String get settingWarningAboveCritical;

  /// No description provided for @configChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alert channels'**
  String get configChannelsTitle;

  /// No description provided for @configChannelsNote.
  ///
  /// In en, this message translates to:
  /// **'Alerts always appear in the apps. These switches decide where else the next alert goes.'**
  String get configChannelsNote;

  /// No description provided for @channelPush.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get channelPush;

  /// No description provided for @channelPushNote.
  ///
  /// In en, this message translates to:
  /// **'Needs the Firebase project, which is not set up yet.'**
  String get channelPushNote;

  /// No description provided for @channelSmsSetting.
  ///
  /// In en, this message translates to:
  /// **'SMS to residents in the affected barangays'**
  String get channelSmsSetting;

  /// No description provided for @channelSmsNote.
  ///
  /// In en, this message translates to:
  /// **'Sent through Semaphore; each text costs credit.'**
  String get channelSmsNote;

  /// No description provided for @channelFacebook.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD Facebook Page'**
  String get channelFacebook;

  /// No description provided for @channelFacebookNote.
  ///
  /// In en, this message translates to:
  /// **'Needs the page\'s approval and access token.'**
  String get channelFacebookNote;

  /// No description provided for @configSmsCapTitle.
  ///
  /// In en, this message translates to:
  /// **'SMS alert limit'**
  String get configSmsCapTitle;

  /// No description provided for @configSmsCapNote.
  ///
  /// In en, this message translates to:
  /// **'Each text costs Semaphore credit. When the day\'s limit is reached, the rest of an alert\'s texts are not sent, and the alert log says so.'**
  String get configSmsCapNote;

  /// No description provided for @settingSmsDailyCap.
  ///
  /// In en, this message translates to:
  /// **'Alert texts per day'**
  String get settingSmsDailyCap;

  /// No description provided for @configContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Numbers shown in the apps'**
  String get configContactTitle;

  /// No description provided for @configContactNote.
  ///
  /// In en, this message translates to:
  /// **'The apps read these when they start. Leave one empty to hide it.'**
  String get configContactNote;

  /// No description provided for @settingHotline.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD hotline'**
  String get settingHotline;

  /// No description provided for @settingHotlineHint.
  ///
  /// In en, this message translates to:
  /// **'For example (02) 8527-0000'**
  String get settingHotlineHint;

  /// No description provided for @settingHotlineError.
  ///
  /// In en, this message translates to:
  /// **'Use digits, spaces, and + ( ) - only, up to 40 characters.'**
  String get settingHotlineError;

  /// No description provided for @settingGateway.
  ///
  /// In en, this message translates to:
  /// **'SMS gateway number for SOS by text'**
  String get settingGateway;

  /// No description provided for @settingGatewayHint.
  ///
  /// In en, this message translates to:
  /// **'For example 0917 123 4567'**
  String get settingGatewayHint;

  /// No description provided for @settingGatewayError.
  ///
  /// In en, this message translates to:
  /// **'Enter a Philippine mobile number like 0917 123 4567, or leave it empty.'**
  String get settingGatewayError;

  /// No description provided for @configSimulationTitle.
  ///
  /// In en, this message translates to:
  /// **'Simulation mode'**
  String get configSimulationTitle;

  /// No description provided for @configSimulationNote.
  ///
  /// In en, this message translates to:
  /// **'For demos and UAT. A simulated reading raises alerts marked Simulated: they appear in the apps and are never texted or posted.'**
  String get configSimulationNote;

  /// No description provided for @simulationSwitch.
  ///
  /// In en, this message translates to:
  /// **'Simulation mode'**
  String get simulationSwitch;

  /// No description provided for @simulationOnCaption.
  ///
  /// In en, this message translates to:
  /// **'On. Simulated readings can be sent.'**
  String get simulationOnCaption;

  /// No description provided for @simulationOffCaption.
  ///
  /// In en, this message translates to:
  /// **'Off. Turn it on to send a simulated reading.'**
  String get simulationOffCaption;

  /// No description provided for @simulateTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a simulated PAGASA reading'**
  String get simulateTitle;

  /// No description provided for @simulateTyphoon.
  ///
  /// In en, this message translates to:
  /// **'Typhoon: Signal 3, 35 mm/hr, 2.5 m surge'**
  String get simulateTyphoon;

  /// No description provided for @simulateRain.
  ///
  /// In en, this message translates to:
  /// **'Heavy rain: 22 mm/hr'**
  String get simulateRain;

  /// No description provided for @simulateCalm.
  ///
  /// In en, this message translates to:
  /// **'Calm: no signal, 2 mm/hr'**
  String get simulateCalm;

  /// No description provided for @simulationSent.
  ///
  /// In en, this message translates to:
  /// **'Simulated reading sent'**
  String get simulationSent;

  /// No description provided for @unsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave without saving?'**
  String get unsavedTitle;

  /// No description provided for @unsavedBody.
  ///
  /// In en, this message translates to:
  /// **'Changes on this page have not been saved.'**
  String get unsavedBody;

  /// No description provided for @unsavedStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get unsavedStay;

  /// No description provided for @unsavedLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get unsavedLeave;

  /// No description provided for @actionWeatherSimulated.
  ///
  /// In en, this message translates to:
  /// **'Simulated a weather reading'**
  String get actionWeatherSimulated;

  /// No description provided for @advisoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue an advisory'**
  String get advisoryTitle;

  /// No description provided for @advisoryReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review before sending'**
  String get advisoryReviewTitle;

  /// No description provided for @advisoryFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get advisoryFrom;

  /// No description provided for @advisoryLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get advisoryLevel;

  /// No description provided for @advisoryTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get advisoryTitleLabel;

  /// No description provided for @advisoryTitleError.
  ///
  /// In en, this message translates to:
  /// **'Give the advisory a title.'**
  String get advisoryTitleError;

  /// No description provided for @advisoryBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get advisoryBodyLabel;

  /// No description provided for @advisoryBodyError.
  ///
  /// In en, this message translates to:
  /// **'Write the message.'**
  String get advisoryBodyError;

  /// No description provided for @advisoryStepsLabel.
  ///
  /// In en, this message translates to:
  /// **'What to do (optional)'**
  String get advisoryStepsLabel;

  /// No description provided for @advisoryStepsHint.
  ///
  /// In en, this message translates to:
  /// **'One step per line'**
  String get advisoryStepsHint;

  /// No description provided for @advisoryStepsError.
  ///
  /// In en, this message translates to:
  /// **'Use at most {steps} steps of up to {length} characters each.'**
  String advisoryStepsError(int steps, int length);

  /// No description provided for @advisoryArea.
  ///
  /// In en, this message translates to:
  /// **'Who it is for'**
  String get advisoryArea;

  /// No description provided for @advisoryChosenBarangays.
  ///
  /// In en, this message translates to:
  /// **'Chosen barangays'**
  String get advisoryChosenBarangays;

  /// No description provided for @advisoryAreaError.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one barangay.'**
  String get advisoryAreaError;

  /// No description provided for @advisoryReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get advisoryReview;

  /// No description provided for @advisoryBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get advisoryBack;

  /// No description provided for @advisorySend.
  ///
  /// In en, this message translates to:
  /// **'Send advisory'**
  String get advisorySend;

  /// No description provided for @advisoryStep.
  ///
  /// In en, this message translates to:
  /// **'• {step}'**
  String advisoryStep(String step);

  /// No description provided for @advisoryToEveryone.
  ///
  /// In en, this message translates to:
  /// **'For residents in all of Manila.'**
  String get advisoryToEveryone;

  /// No description provided for @advisoryToBarangays.
  ///
  /// In en, this message translates to:
  /// **'For residents in {barangays}.'**
  String advisoryToBarangays(String barangays);

  /// No description provided for @advisoryChannels.
  ///
  /// In en, this message translates to:
  /// **'It appears in the apps at once and is queued for {channels}.'**
  String advisoryChannels(String channels);

  /// No description provided for @advisoryAppsOnly.
  ///
  /// In en, this message translates to:
  /// **'It appears in the apps at once. The other channels are switched off.'**
  String get advisoryAppsOnly;

  /// No description provided for @advisorySimulated.
  ///
  /// In en, this message translates to:
  /// **'Simulation mode is on: it will be marked Simulated and shown in the apps only. Nothing is texted or posted.'**
  String get advisorySimulated;

  /// No description provided for @advisoryIssued.
  ///
  /// In en, this message translates to:
  /// **'Advisory issued'**
  String get advisoryIssued;

  /// No description provided for @endAlert.
  ///
  /// In en, this message translates to:
  /// **'End alert'**
  String get endAlert;

  /// No description provided for @endAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'End this alert?'**
  String get endAlertTitle;

  /// No description provided for @endAlertBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" stops showing in the apps. It stays in this log.'**
  String endAlertBody(String title);

  /// No description provided for @alertEndedSnack.
  ///
  /// In en, this message translates to:
  /// **'Alert ended'**
  String get alertEndedSnack;

  /// No description provided for @actionAlertIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued an advisory'**
  String get actionAlertIssued;

  /// No description provided for @actionAlertEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended an alert'**
  String get actionAlertEnded;

  /// No description provided for @levelInfo.
  ///
  /// In en, this message translates to:
  /// **'Advisory'**
  String get levelInfo;

  /// No description provided for @levelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get levelWarning;

  /// No description provided for @levelCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get levelCritical;

  /// No description provided for @thresholdNote.
  ///
  /// In en, this message translates to:
  /// **'Warning from {warning}, critical from {critical}'**
  String thresholdNote(String warning, String critical);

  /// No description provided for @stormSurgeMeters.
  ///
  /// In en, this message translates to:
  /// **'Up to {meters} m'**
  String stormSurgeMeters(String meters);

  /// No description provided for @alertLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts sent'**
  String get alertLogTitle;

  /// No description provided for @alertLogNote.
  ///
  /// In en, this message translates to:
  /// **'Every alert and what happened to it on each channel (FR6).'**
  String get alertLogNote;

  /// No description provided for @alertLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No alerts sent yet.'**
  String get alertLogEmpty;

  /// No description provided for @alertLogFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the alert log.'**
  String get alertLogFailed;

  /// No description provided for @alertAllManila.
  ///
  /// In en, this message translates to:
  /// **'All of Manila'**
  String get alertAllManila;

  /// No description provided for @alertSimulated.
  ///
  /// In en, this message translates to:
  /// **'Simulated'**
  String get alertSimulated;

  /// No description provided for @alertEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get alertEnded;

  /// No description provided for @alertAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Raised by a threshold'**
  String get alertAutomatic;

  /// No description provided for @alertFrom.
  ///
  /// In en, this message translates to:
  /// **'{source}, {time}'**
  String alertFrom(String source, String time);

  /// No description provided for @sourcePagasa.
  ///
  /// In en, this message translates to:
  /// **'PAGASA'**
  String get sourcePagasa;

  /// No description provided for @sourcePhivolcs.
  ///
  /// In en, this message translates to:
  /// **'PHIVOLCS'**
  String get sourcePhivolcs;

  /// No description provided for @sourceEfcos.
  ///
  /// In en, this message translates to:
  /// **'EFCOS'**
  String get sourceEfcos;

  /// No description provided for @sourceMdrrmd.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD'**
  String get sourceMdrrmd;

  /// No description provided for @alertChannelApp.
  ///
  /// In en, this message translates to:
  /// **'In the apps'**
  String get alertChannelApp;

  /// No description provided for @alertChannelPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get alertChannelPush;

  /// No description provided for @alertChannelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get alertChannelSms;

  /// No description provided for @alertChannelFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get alertChannelFacebook;

  /// No description provided for @deliveryQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get deliveryQueued;

  /// No description provided for @deliverySending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get deliverySending;

  /// No description provided for @deliveryEnded.
  ///
  /// In en, this message translates to:
  /// **'Not sent (the alert ended)'**
  String get deliveryEnded;

  /// No description provided for @deliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get deliverySent;

  /// No description provided for @deliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get deliveryFailed;

  /// No description provided for @deliveryOff.
  ///
  /// In en, this message translates to:
  /// **'Switched off'**
  String get deliveryOff;

  /// No description provided for @deliverySimulated.
  ///
  /// In en, this message translates to:
  /// **'Not sent (simulated)'**
  String get deliverySimulated;

  /// No description provided for @deliveryNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get deliveryNotSetUp;

  /// No description provided for @deliveryLine.
  ///
  /// In en, this message translates to:
  /// **'{channel}: {status}'**
  String deliveryLine(String channel, String status);

  /// No description provided for @deliveryCounts.
  ///
  /// In en, this message translates to:
  /// **'{channel}: sent to {delivered} of {recipients}'**
  String deliveryCounts(String channel, int delivered, int recipients);

  /// No description provided for @webAppTitle.
  ///
  /// In en, this message translates to:
  /// **'S.A.G.I.P. hazard report'**
  String get webAppTitle;

  /// No description provided for @webSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a hazard to MDRRMD'**
  String get webSignInTitle;

  /// No description provided for @webSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your mobile number. We\'ll text you a code.'**
  String get webSignInBody;

  /// No description provided for @webSosNotice.
  ///
  /// In en, this message translates to:
  /// **'SOS is only available in the S.A.G.I.P. app. In an emergency, call MDRRMD.'**
  String get webSosNotice;

  /// No description provided for @webSosNoticeHotline.
  ///
  /// In en, this message translates to:
  /// **'SOS is only available in the S.A.G.I.P. app. In an emergency, call MDRRMD at {number}.'**
  String webSosNoticeHotline(String number);

  /// No description provided for @webGetApp.
  ///
  /// In en, this message translates to:
  /// **'Get the S.A.G.I.P. app'**
  String get webGetApp;

  /// No description provided for @webMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get webMobileNumber;

  /// No description provided for @webMobileNumberHint.
  ///
  /// In en, this message translates to:
  /// **'917 123 4567'**
  String get webMobileNumberHint;

  /// No description provided for @webSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get webSendCode;

  /// No description provided for @webSendingCode.
  ///
  /// In en, this message translates to:
  /// **'Sending code'**
  String get webSendingCode;

  /// No description provided for @webCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'New to S.A.G.I.P.? Create an account'**
  String get webCreateAccount;

  /// No description provided for @webHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get webHaveAccount;

  /// No description provided for @webDemoHint.
  ///
  /// In en, this message translates to:
  /// **'Sample data: sign in with 917 000 4821 and the code {code}.'**
  String webDemoHint(String code);

  /// No description provided for @webCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get webCodeTitle;

  /// No description provided for @webCodeBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {phone}.'**
  String webCodeBody(String phone);

  /// No description provided for @webCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get webCodeLabel;

  /// No description provided for @webCheckCode.
  ///
  /// In en, this message translates to:
  /// **'Check code'**
  String get webCheckCode;

  /// No description provided for @webCheckingCode.
  ///
  /// In en, this message translates to:
  /// **'Checking code'**
  String get webCheckingCode;

  /// No description provided for @webResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String webResendIn(String time);

  /// No description provided for @webResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get webResendCode;

  /// No description provided for @webCodeSent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get webCodeSent;

  /// No description provided for @webChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get webChangeNumber;

  /// No description provided for @webRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get webRegisterTitle;

  /// No description provided for @webRegisterBody.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD uses this to reach you and to know your barangay.'**
  String get webRegisterBody;

  /// No description provided for @webFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get webFullName;

  /// No description provided for @webFullNameError.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name.'**
  String get webFullNameError;

  /// No description provided for @webBarangay.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get webBarangay;

  /// No description provided for @webChooseBarangay.
  ///
  /// In en, this message translates to:
  /// **'Choose your barangay'**
  String get webChooseBarangay;

  /// No description provided for @webBarangayError.
  ///
  /// In en, this message translates to:
  /// **'Choose your barangay.'**
  String get webBarangayError;

  /// No description provided for @webAgreeTerms.
  ///
  /// In en, this message translates to:
  /// **'I agree to the terms and the privacy notice'**
  String get webAgreeTerms;

  /// No description provided for @webTermsError.
  ///
  /// In en, this message translates to:
  /// **'Agree to the terms to continue.'**
  String get webTermsError;

  /// No description provided for @webReadPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Read the privacy notice'**
  String get webReadPrivacy;

  /// No description provided for @webPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a Philippine mobile number, like 917 123 4567.'**
  String get webPhoneInvalid;

  /// No description provided for @webPhoneNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'This number has no account yet. Create an account first.'**
  String get webPhoneNotRegistered;

  /// No description provided for @webPhoneNotRegisteredApp.
  ///
  /// In en, this message translates to:
  /// **'This number has no account yet. Create one in the S.A.G.I.P. app.'**
  String get webPhoneNotRegisteredApp;

  /// No description provided for @webPhoneTaken.
  ///
  /// In en, this message translates to:
  /// **'This number already has an account. Sign in instead.'**
  String get webPhoneTaken;

  /// No description provided for @webCodeWrong.
  ///
  /// In en, this message translates to:
  /// **'That code is not right. Check the text message and try again.'**
  String get webCodeWrong;

  /// No description provided for @webTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a minute, then try again.'**
  String get webTooManyAttempts;

  /// No description provided for @webOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline.'**
  String get webOffline;

  /// No description provided for @webSmsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send or check the code right now. Try again in a few minutes.'**
  String get webSmsUnavailable;

  /// No description provided for @webPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get webPrivacyTitle;

  /// No description provided for @webPrivacyCollectTitle.
  ///
  /// In en, this message translates to:
  /// **'What we collect'**
  String get webPrivacyCollectTitle;

  /// No description provided for @webPrivacyCollectBody.
  ///
  /// In en, this message translates to:
  /// **'Your name, mobile number, and barangay; and where a hazard is when you send a report.'**
  String get webPrivacyCollectBody;

  /// No description provided for @webPrivacyWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get webPrivacyWhyTitle;

  /// No description provided for @webPrivacyWhyBody.
  ///
  /// In en, this message translates to:
  /// **'To check reports against others nearby, to reach you about a report, and to send you alerts for your area.'**
  String get webPrivacyWhyBody;

  /// No description provided for @webPrivacyWhoTitle.
  ///
  /// In en, this message translates to:
  /// **'Who can see it'**
  String get webPrivacyWhoTitle;

  /// No description provided for @webPrivacyWhoBody.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD dispatchers and administrators. Rescue personnel see only the incident they are assigned to.'**
  String get webPrivacyWhoBody;

  /// No description provided for @webPrivacyKeepTitle.
  ///
  /// In en, this message translates to:
  /// **'How long we keep it'**
  String get webPrivacyKeepTitle;

  /// No description provided for @webPrivacyKeepBody.
  ///
  /// In en, this message translates to:
  /// **'As long as you have an account, and incident records as long as the law requires.'**
  String get webPrivacyKeepBody;

  /// No description provided for @webPrivacyRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get webPrivacyRightsTitle;

  /// No description provided for @webPrivacyRightsBody.
  ///
  /// In en, this message translates to:
  /// **'Under the Data Privacy Act (RA 10173) you can see, correct, or ask MDRRMD to delete your data. Ask in the S.A.G.I.P. app or at the MDRRMD office.'**
  String get webPrivacyRightsBody;

  /// No description provided for @webReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a hazard'**
  String get webReportTitle;

  /// No description provided for @webReportBody.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD checks reports against others nearby before acting. One report alone is not treated as an emergency.'**
  String get webReportBody;

  /// No description provided for @webSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String webSignedInAs(String name);

  /// No description provided for @webMyReports.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get webMyReports;

  /// No description provided for @webDescription.
  ///
  /// In en, this message translates to:
  /// **'What do you see?'**
  String get webDescription;

  /// No description provided for @webDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Water is knee-deep on Dapitan St and rising.'**
  String get webDescriptionHint;

  /// No description provided for @webDescriptionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Describe what you see.'**
  String get webDescriptionEmpty;

  /// No description provided for @webType.
  ///
  /// In en, this message translates to:
  /// **'Type (optional)'**
  String get webType;

  /// No description provided for @webLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Where is it?'**
  String get webLocationTitle;

  /// No description provided for @webUseMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get webUseMyLocation;

  /// No description provided for @webLocating.
  ///
  /// In en, this message translates to:
  /// **'Getting your location'**
  String get webLocating;

  /// No description provided for @webChooseBarangayButton.
  ///
  /// In en, this message translates to:
  /// **'Choose a barangay'**
  String get webChooseBarangayButton;

  /// No description provided for @webMapHint.
  ///
  /// In en, this message translates to:
  /// **'Or move the map until the pin is on the spot.'**
  String get webMapHint;

  /// No description provided for @webLocationNone.
  ///
  /// In en, this message translates to:
  /// **'No location chosen yet.'**
  String get webLocationNone;

  /// No description provided for @webLocationBrowser.
  ///
  /// In en, this message translates to:
  /// **'From your browser, accurate to {meters} m'**
  String webLocationBrowser(int meters);

  /// No description provided for @webLocationPin.
  ///
  /// In en, this message translates to:
  /// **'Chosen on the map'**
  String get webLocationPin;

  /// No description provided for @webLocationBarangay.
  ///
  /// In en, this message translates to:
  /// **'Centre of the barangay you chose'**
  String get webLocationBarangay;

  /// No description provided for @webNear.
  ///
  /// In en, this message translates to:
  /// **'Near {place}'**
  String webNear(String place);

  /// No description provided for @webPlace.
  ///
  /// In en, this message translates to:
  /// **'{barangay}, {district}'**
  String webPlace(String barangay, String district);

  /// No description provided for @webLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Your browser did not share your location. Move the map until the pin is on the spot, or choose a barangay.'**
  String get webLocationDenied;

  /// No description provided for @webLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location. Move the map until the pin is on the spot, or choose a barangay.'**
  String get webLocationUnavailable;

  /// No description provided for @webQuotaLeft.
  ///
  /// In en, this message translates to:
  /// **'{remaining} of {limit} reports left this hour'**
  String webQuotaLeft(int remaining, int limit);

  /// No description provided for @webQuotaNone.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent {limit} reports in the last hour. Try again after {time}.'**
  String webQuotaNone(int limit, String time);

  /// No description provided for @webQuotaNoneLater.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent {limit} reports in the last hour. Try again later.'**
  String webQuotaNoneLater(int limit);

  /// No description provided for @webSuspended.
  ///
  /// In en, this message translates to:
  /// **'This account cannot send reports right now. In an emergency, call MDRRMD.'**
  String get webSuspended;

  /// No description provided for @webRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the hourly limit for reports. Try again later.'**
  String get webRateLimited;

  /// No description provided for @webSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get webSend;

  /// No description provided for @webSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get webSending;

  /// No description provided for @webOutsideManila.
  ///
  /// In en, this message translates to:
  /// **'This location is outside Manila City. S.A.G.I.P. covers Manila only.'**
  String get webOutsideManila;

  /// No description provided for @webNeedLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose where it is: use your location, move the map, or choose a barangay.'**
  String get webNeedLocation;

  /// No description provided for @webConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Your report is kept on this page. Send it when you\'re back online.'**
  String get webConnectionLost;

  /// No description provided for @webPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Report location'**
  String get webPinLabel;

  /// No description provided for @webSearchBarangay.
  ///
  /// In en, this message translates to:
  /// **'Search barangays'**
  String get webSearchBarangay;

  /// No description provided for @webNoBarangayMatch.
  ///
  /// In en, this message translates to:
  /// **'No barangay matches that.'**
  String get webNoBarangayMatch;

  /// No description provided for @webReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Report received'**
  String get webReceivedTitle;

  /// No description provided for @webReference.
  ///
  /// In en, this message translates to:
  /// **'Reference {id}'**
  String webReference(String id);

  /// No description provided for @webReceivedBody.
  ///
  /// In en, this message translates to:
  /// **'MDRRMD checks it against other reports nearby. A single report is never confirmed on its own.'**
  String get webReceivedBody;

  /// No description provided for @webRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recent reports'**
  String get webRecentTitle;

  /// No description provided for @webNoReports.
  ///
  /// In en, this message translates to:
  /// **'No reports yet.'**
  String get webNoReports;

  /// No description provided for @webReportsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your reports.'**
  String get webReportsFailed;

  /// No description provided for @webSendAnother.
  ///
  /// In en, this message translates to:
  /// **'Send another report'**
  String get webSendAnother;

  /// No description provided for @webSentFromApp.
  ///
  /// In en, this message translates to:
  /// **'Sent from the app'**
  String get webSentFromApp;

  /// No description provided for @webSentFromWeb.
  ///
  /// In en, this message translates to:
  /// **'Sent from the web form'**
  String get webSentFromWeb;

  /// No description provided for @webReportWhen.
  ///
  /// In en, this message translates to:
  /// **'{date}, {time}'**
  String webReportWhen(String date, String time);

  /// No description provided for @webStageReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get webStageReceived;

  /// No description provided for @webStageChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get webStageChecking;

  /// No description provided for @webStageConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get webStageConfirmed;

  /// No description provided for @webStageNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed'**
  String get webStageNotConfirmed;

  /// No description provided for @webStageResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get webStageResolved;

  /// No description provided for @auditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No actions recorded yet.'**
  String get auditEmpty;

  /// No description provided for @comingSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'Not built yet'**
  String get comingSoonTitle;

  /// No description provided for @comingSoonFor.
  ///
  /// In en, this message translates to:
  /// **'{page}: not built yet'**
  String comingSoonFor(String page);

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get working;

  /// No description provided for @placeholderForecast.
  ///
  /// In en, this message translates to:
  /// **'The 72-hour risk heatmap arrives once the LSTM and KDE models are trained (plan 10.5).'**
  String get placeholderForecast;

  /// No description provided for @placeholderReports.
  ///
  /// In en, this message translates to:
  /// **'NDRRMC report generation arrives with the RAG proof of concept (plan 10.6).'**
  String get placeholderReports;

  /// No description provided for @notFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFoundTitle;

  /// No description provided for @notFoundBody.
  ///
  /// In en, this message translates to:
  /// **'It may have moved, or your account can\'t open it.'**
  String get notFoundBody;

  /// No description provided for @backToBoard.
  ///
  /// In en, this message translates to:
  /// **'Back to the Command Board'**
  String get backToBoard;

  /// No description provided for @secondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} s ago'**
  String secondsAgo(int count);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String hoursAgo(int count);
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
