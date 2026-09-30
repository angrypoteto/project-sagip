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

  /// No description provided for @placeholderAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Response-time analytics arrive with the Supabase backend (plan Phase 3).'**
  String get placeholderAnalytics;

  /// No description provided for @placeholderReports.
  ///
  /// In en, this message translates to:
  /// **'NDRRMC report generation arrives with the RAG proof of concept (plan 10.6).'**
  String get placeholderReports;

  /// No description provided for @placeholderAccounts.
  ///
  /// In en, this message translates to:
  /// **'Account management is built directly on Supabase in Phase 3.'**
  String get placeholderAccounts;

  /// No description provided for @placeholderResources.
  ///
  /// In en, this message translates to:
  /// **'Unit and roster management is built directly on Supabase in Phase 3.'**
  String get placeholderResources;

  /// No description provided for @placeholderSettings.
  ///
  /// In en, this message translates to:
  /// **'Alert thresholds and priority rules are built directly on Supabase in Phase 3.'**
  String get placeholderSettings;

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
