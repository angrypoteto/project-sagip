// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get appTitle => 'S.A.G.I.P.';

  @override
  String get signInTitle => 'Mag-sign in';

  @override
  String get demoSignInBody =>
      'Demo mode: halimbawang data ang gamit dito, hindi totoong mga account.';

  @override
  String get continueAsResident => 'Magpatuloy bilang residente';

  @override
  String get continueAsResidentDetail =>
      'Maria Dela Cruz ? Barangay 412, Sampaloc';

  @override
  String get continueAsResponder => 'Magpatuloy bilang tagasagip';

  @override
  String get continueAsResponderDetail => 'J. Reyes ? Yunit R-03';

  @override
  String get signingIn => 'Nagsa-sign in';

  @override
  String get signInWrongCredentials =>
      'Hindi gumana ang account na iyan. Subukan muli.';

  @override
  String get signInDisabled =>
      'Naka-disable ang account na ito. Magtanong sa MDRRMD.';

  @override
  String get signInNotStaff =>
      'Hindi puwedeng gamitin ng account na ito ang mobile app.';

  @override
  String get signInOffline =>
      'Offline ka. Kailangan ng internet para mag-sign in. Sa emergency, tawagan ang MDRRMD.';

  @override
  String get navHome => 'Simula';

  @override
  String get navReport => 'Report';

  @override
  String get navAlerts => 'Mga alert';

  @override
  String get navMe => 'Ako';

  @override
  String get navHistory => 'Mga nakaraan';

  @override
  String greeting(String name) {
    return 'Kumusta, $name';
  }

  @override
  String place(String barangay, String district) {
    return '$barangay, $district';
  }

  @override
  String alertStripSignal(int level, String mm) {
    return 'Signal No. $level ? Ulan $mm mm/hr ? PAGASA';
  }

  @override
  String alertStripRain(String mm) {
    return 'Ulan $mm mm/hr ? PAGASA';
  }

  @override
  String get sosSemantic => 'Magpadala ng SOS. Pindutin nang 2 segundo.';

  @override
  String get sosOpenSemantic => 'Aktibo ang iyong SOS. Buksan ang status nito.';

  @override
  String get sosHoldCaption => 'Pindutin nang 2 segundo para ipadala';

  @override
  String get sosCaptionSending => 'Ipinapadala ang iyong SOS';

  @override
  String get sosCaptionSaved => 'Naka-save sa iyong phone';

  @override
  String get sosCaptionSms => 'Naipadala sa SMS';

  @override
  String get sosCaptionRelaying => 'Ipinapasa sa mga kalapit na phone';

  @override
  String get sosCaptionDelivered => 'Nasa MDRRMD na ang iyong SOS';

  @override
  String get gpsOff =>
      'Hindi makuha ang lokasyon. I-on ang GPS para maipadala ang eksaktong lokasyon mo.';

  @override
  String get openSettings => 'Buksan ang mga setting';

  @override
  String get batteryTitle => 'Panatilihing gumagana ang S.A.G.I.P.';

  @override
  String get batteryBody =>
      'Para makatipid sa baterya, maaaring ihinto ng phone na ito ang S.A.G.I.P. sa background. Mawawala sa board ang lokasyon ng iyong yunit. Payagang patuloy itong gumana.';

  @override
  String get batteryAllow => 'Payagan';

  @override
  String get reportHazard => 'Mag-report ng panganib';

  @override
  String get sosSaveFailed =>
      'Hindi ma-save ang iyong SOS. Tawagan ang MDRRMD.';

  @override
  String get activeSosTitle => 'Iyong SOS';

  @override
  String get viewStatus => 'Tingnan ang status';

  @override
  String elapsed(String time) {
    return '$time mula nang ipadala mo';
  }

  @override
  String get bannerSmsOnly =>
      'Offline. Ise-save ang iyong SOS at ipapadala sa SMS.';

  @override
  String get bannerNoSignal =>
      'Walang signal. Ise-save ang iyong SOS at ipapasa sa mga kalapit na phone.';

  @override
  String get bannerOfflineSaved =>
      'Offline. Ise-save ang SOS at mga report at ipapadala kapag online ka na ulit.';

  @override
  String bannerOfflineWaiting(int count) {
    return 'Offline ? $count naghihintay maipadala';
  }

  @override
  String bannerSending(int count) {
    return 'Online na ulit ? ipinapadala ang $count naka-save sa iyong phone';
  }

  @override
  String get bannerBackOnline => 'Online na ulit';

  @override
  String get deliverySaved => 'Naka-save sa phone';

  @override
  String get deliverySending => 'Ipinapadala';

  @override
  String get deliverySms => 'Naipadala sa SMS';

  @override
  String get deliveryRelaying => 'Ipinapasa sa mga kalapit na phone';

  @override
  String get deliveryDelivered => 'Nakarating na';

  @override
  String get deliveryRejected => 'Hindi tinanggap';

  @override
  String sosDeliveredNotice(String time) {
    return 'Nakarating na ang iyong SOS mula $time.';
  }

  @override
  String reportDeliveredNotice(String time) {
    return 'Nakarating na ang iyong report ng panganib mula $time.';
  }

  @override
  String statusDeliveredNotice(String time) {
    return 'Nakarating na ang iyong update sa status mula $time.';
  }

  @override
  String completionDeliveredNotice(String time) {
    return 'Nakarating na ang iyong report ng natapos na pagsagip mula $time.';
  }

  @override
  String detailsDeliveredNotice(String time) {
    return 'Nakarating na ang mga detalye ng iyong SOS mula $time.';
  }

  @override
  String get sosStatusTitle => 'Iyong SOS';

  @override
  String get sosStateSaved => 'Naka-save sa iyong phone';

  @override
  String get sosStateSending => 'Ipinapadala';

  @override
  String get sosStateSms => 'Naipadala sa SMS';

  @override
  String get sosStateRelaying => 'Ipinapasa sa mga kalapit na phone';

  @override
  String get sosStatePending => 'Hinihintay ang pag-verify';

  @override
  String get sosStateVerified => 'Na-verify ng MDRRMD';

  @override
  String get sosStateAssigned => 'May nakatalagang tagasagip';

  @override
  String get sosStateEnRoute => 'Paparating ang tagasagip';

  @override
  String get sosStateOnScene => 'Dumating na ang tagasagip';

  @override
  String get sosStateResolved => 'Natugunan na';

  @override
  String get sosStateRejected => 'Hindi tinanggap ang SOS. Tawagan ang MDRRMD.';

  @override
  String get keepTrying =>
      'Patuloy naming susubukan at ipapaalam kapag nakarating na.';

  @override
  String get sosSendDataTitle => 'Walang internet. Sinusubukan ulit sa data';

  @override
  String get sosSendDataText =>
      'Naka-save ang iyong SOS sa phone na ito. Kung hindi gumana ang data, ipapadala ito sa SMS, saka sa mga kalapit na phone.';

  @override
  String get sosSendSmsTitle => 'Naipadala sa SMS ang SOS sa MDRRMD';

  @override
  String get sosSendSmsText =>
      'Hinihintay ang kumpirmasyon ng MDRRMD. Sinusubukan pa rin ang data. Kung walang balita sa loob ng 2 minuto, hihingan din ng tulong ang mga kalapit na phone sa Bluetooth.';

  @override
  String get sosSendSmsFailedTitle => 'Hindi naipadala ang SMS';

  @override
  String get sosSendSmsFailedText =>
      'I-on ang Bluetooth para maipasa ng mga kalapit na phone ang iyong SOS. Sinusubukan pa rin ang data at SMS.';

  @override
  String get sosSendBluetoothTitle =>
      'Hinihiling sa mga kalapit na phone na ipasa ang iyong SOS';

  @override
  String get sosSendBluetoothText =>
      'Hindi naipadala ang SMS. Ipapasa sa MDRRMD ng kalapit na phone na may S.A.G.I.P. ang iyong SOS kapag online ito. Panatilihing naka-on ang Bluetooth.';

  @override
  String get sosSendBluetoothAfterSms =>
      'Naipadala ang SMS pero hindi pa ito kinukumpirma ng MDRRMD, kaya hinihingan din ng tulong ang mga kalapit na phone na may S.A.G.I.P. Panatilihing naka-on ang Bluetooth.';

  @override
  String get sosSendDeliveredTitle => 'Nakarating na sa MDRRMD ang iyong SOS';

  @override
  String sosSendDeliveredText(String time) {
    return 'Ipinadala nang $time. Buksan ang S.A.G.I.P. para masubaybayan ito.';
  }

  @override
  String get sosSendRejectedTitle => 'Hindi tinanggap ang iyong SOS';

  @override
  String get sosSendRejectedText =>
      'Buksan ang S.A.G.I.P. para makita kung bakit, o tumawag sa MDRRMD.';

  @override
  String get sendStepsTitle => 'Paano ipinapadala ang iyong SOS';

  @override
  String get sendStepData => 'Data';

  @override
  String get sendStepSms => 'SMS';

  @override
  String get sendStepBluetooth => 'Mga kalapit na phone (Bluetooth)';

  @override
  String get sendStepTrying => 'Sinusubukan';

  @override
  String get sendStepSent => 'Naipadala';

  @override
  String get sendStepFailed => 'Hindi naipadala';

  @override
  String get sendStepNext => 'Susunod';

  @override
  String get sendStepAsking => 'Hinihiling';

  @override
  String sendStepLine(String step, String state) {
    return '$step: $state';
  }

  @override
  String get resolvedBody => 'Natugunan na ang iyong SOS. Mag-ingat po.';

  @override
  String get sosStateCancelled => 'Nakansela ang SOS';

  @override
  String get cancelledBody =>
      'Isinara ng MDRRMD ang SOS na ito dahil hiniling mo. Kung kailangan mo ulit ng tulong, magpadala ng bagong SOS.';

  @override
  String get cancelSos => 'Kanselahin ang SOS';

  @override
  String get cancelSheetTitle => 'Kanselahin ang SOS na ito?';

  @override
  String get cancelSheetBody =>
      'Sabihin sa MDRRMD kung bakit. Sila ang magsasara ng SOS: hangga\'t hindi nila ito ginagawa, bukas pa ito at maaaring dumating pa ang tulong.';

  @override
  String get cancelReasonSafeNow => 'Ligtas na ako';

  @override
  String get cancelReasonMistake => 'Naipadala ko nang hindi sinasadya';

  @override
  String get cancelReasonOther => 'Ibang dahilan';

  @override
  String get cancelAsk => 'Hilinging kanselahin sa MDRRMD';

  @override
  String get cancelKeep => 'Panatilihin ang SOS ko';

  @override
  String get cancelAskedSnack =>
      'Naabisuhan na ang MDRRMD. Bukas pa ang iyong SOS hanggang isara nila ito.';

  @override
  String get cancelAskedTitle => 'Hiniling mong kanselahin ang SOS na ito';

  @override
  String cancelAskedBody(String reason) {
    return 'Dahilan: $reason. Isasara ito ng MDRRMD, o tatawagan ka muna. Hangga\'t hindi pa, bukas pa ito at maaaring dumating pa ang tulong.';
  }

  @override
  String get cancelWithdraw => 'Kailangan ko pa ng tulong';

  @override
  String get cancelWithdrawnSnack =>
      'Bukas pa ang iyong SOS. Paparating pa rin ang tulong.';

  @override
  String get cancelOffline =>
      'Offline ka, kaya hindi maabisuhan ang MDRRMD. Tawagan ang MDRRMD para magkansela.';

  @override
  String get cancelFailed =>
      'Hindi naipadala. Subukan muli, o tawagan ang MDRRMD.';

  @override
  String get locationShared =>
      'Habang bukas ang SOS na ito at naka-on ang app, naabisuhan ang MDRRMD kapag gumagalaw ka.';

  @override
  String get assignmentCancelAsked =>
      'Hiniling ng residente na magkansela. Magpatuloy hanggang may ibang utos ang dispatcher.';

  @override
  String assignmentResidentMoved(String time) {
    return 'Lumipat ang residente. Ito ang pinakabagong lokasyon niya, na-update $time.';
  }

  @override
  String get timelineTitle => 'Mga hakbang';

  @override
  String get stepSaved => 'Naka-save sa phone';

  @override
  String get stepSentInternet => 'Naipadala sa internet';

  @override
  String get stepSentSms => 'Naipadala sa SMS';

  @override
  String get stepSentRelay => 'Naipasa sa mga kalapit na phone';

  @override
  String get stepSent => 'Naipadala';

  @override
  String get stepReceived => 'Natanggap ng MDRRMD';

  @override
  String get stepPending => 'Hinihintay ang pag-verify';

  @override
  String get stepVerified => 'Na-verify';

  @override
  String get stepAssigned => 'May nakatalagang tagasagip';

  @override
  String stepAssignedUnit(String unit) {
    return 'Nakatalagang tagasagip: $unit';
  }

  @override
  String get stepEnRoute => 'Paparating';

  @override
  String get stepOnScene => 'Nasa lugar na';

  @override
  String get stepResolved => 'Natugunan na';

  @override
  String get etaTitle => 'Darating sa humigit-kumulang';

  @override
  String etaMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String unitLine(String callSign, String unitType) {
    return '$callSign ? $unitType';
  }

  @override
  String get unitAmbulance => 'Ambulansya';

  @override
  String get unitRescueBoat => 'Bangkang pangsagip';

  @override
  String get unitFireTruck => 'Fire truck';

  @override
  String get unitRescueTeam => 'Grupong tagasagip';

  @override
  String get locationTitle => 'Iyong lokasyon';

  @override
  String locationAccuracy(String coordinates, int meters) {
    return '$coordinates ? maaaring lumihis ng $meters m';
  }

  @override
  String get locationUnknown =>
      'Hindi makuha ng GPS ang lokasyon. Alam ng MDRRMD ang iyong barangay.';

  @override
  String get addDetails => 'Magdagdag ng detalye';

  @override
  String get editDetails => 'Baguhin ang mga detalye';

  @override
  String get detailsHint => 'Opsyonal. Ipinapadala na ang iyong SOS.';

  @override
  String get detailsType => 'Ano ang nangyayari?';

  @override
  String get whatsHappeningBody =>
      'Naipadala na ang iyong SOS. Isang pindot para malaman ng mga rescuer kung ano ang dadalhin.';

  @override
  String get typeFlood => 'Baha';

  @override
  String get typeFire => 'Sunog';

  @override
  String get typeMedical => 'Medikal';

  @override
  String get typeStructural => 'Pagguho o pinsala';

  @override
  String get detailsPeople => 'Mga kasama mo';

  @override
  String detailsPeopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tao',
      one: '1 tao',
    );
    return '$_temp0';
  }

  @override
  String get fewerPeople => 'Bawasan ang tao';

  @override
  String get morePeople => 'Dagdagan ang tao';

  @override
  String get detailsExtraHelp => 'May nangangailangan ng dagdag na tulong dito';

  @override
  String get detailsExtraHelpHint =>
      'Halimbawa, senior citizen, taong may kapansanan, o buntis';

  @override
  String get detailsNote => 'Iba pang detalye (opsyonal)';

  @override
  String get saveDetails => 'I-save ang mga detalye';

  @override
  String get detailsSaved => 'Naidagdag ang mga detalye';

  @override
  String get guidanceTitle => 'Habang naghihintay';

  @override
  String get guidanceBody =>
      'Manatili po kung nasaan ka kung ligtas. Kung tumataas ang tubig, umakyat sa mas mataas na palapag. Panatilihing naka-on at malapit sa iyo ang phone.';

  @override
  String get callMdrrmd => 'Tawagan ang MDRRMD';

  @override
  String get hotlineTitle => 'Hotline ng MDRRMD';

  @override
  String hotlineBody(String number) {
    return 'Tawagan ang $number mula sa kahit anong phone.';
  }

  @override
  String get hotlineMissing =>
      'Wala pang nakatakdang numero ng hotline ng MDRRMD.';

  @override
  String get close => 'Isara';

  @override
  String get sosNotFound => 'Wala na sa phone na ito ang SOS na ito.';

  @override
  String get queueTitle => 'Naghihintay maipadala';

  @override
  String get queueEmpty => 'Walang naghihintay maipadala.';

  @override
  String get queueTryNow => 'Subukang ipadala ngayon';

  @override
  String get queueNextInternet =>
      'Online ka. Ipinapadala na ang lahat ng naka-save dito.';

  @override
  String get queueNextSms =>
      'Walang internet. Ipinapadala ang mga SOS sa SMS; naghihintay ng internet ang iba.';

  @override
  String get queueNextSteps =>
      'Walang internet. Sinusubukan ang SOS sa data, saka sa SMS, saka sa mga kalapit na phone. Ang iba ay maghihintay ng internet.';

  @override
  String get queueNextNone =>
      'Walang signal. Patuloy naming susubukan at ipapasa ang iyong SOS sa mga kalapit na phone.';

  @override
  String get queueNextWait =>
      'Walang internet. Mananatili sa iyong phone ang lahat at ipapadala kapag online ka na ulit. Sa emergency, tawagan ang MDRRMD.';

  @override
  String queueCaptured(String time) {
    return 'Naitala $time';
  }

  @override
  String get queueKindSos => 'SOS';

  @override
  String get queueKindReport => 'Report ng panganib';

  @override
  String get queueKindStatus => 'Update sa status';

  @override
  String get queueKindCompletion => 'Report ng natapos na pagsagip';

  @override
  String get queueKindDetails => 'Mga detalye ng SOS';

  @override
  String get queueRemove => 'Alisin';

  @override
  String get queueTextIt => 'Ako ang magte-text';

  @override
  String get queueTextItHint =>
      'Walang internet, at hindi ito ma-text ng app. Bubuksan nito ang messages app na may nakahandang SOS: pindutin ang send doon.';

  @override
  String get queueTextItFailed =>
      'Hindi mabuksan ang messages app. Sa emergency, tawagan ang MDRRMD.';

  @override
  String get meTitle => 'Ako';

  @override
  String get roleResident => 'Residente';

  @override
  String get roleResponder => 'Tagasagip sa lugar';

  @override
  String get signOut => 'Mag-sign out';

  @override
  String get demoTitle => 'Mga gamit sa demo';

  @override
  String get demoNote =>
      'Makikita lang kapag halimbawang data ang gamit ng app.';

  @override
  String get demoSignal => 'Signal';

  @override
  String get signalInternet => 'Internet';

  @override
  String get signalSms => 'SMS lang';

  @override
  String get signalNone => 'Walang signal';

  @override
  String get demoGps => 'Naka-on ang GPS';

  @override
  String get trackResponder => 'Tingnan ang tagasagip sa map';

  @override
  String get trackTitle => 'Tingnan ang tagasagip sa map';

  @override
  String get trackFinding => 'Hinahanap ang iyong tagasagip';

  @override
  String get trackWaiting => 'Hinihintay na magtalaga ng tagasagip.';

  @override
  String get trackArrived => 'Dumating na ang iyong tagasagip.';

  @override
  String trackUpdated(String ago) {
    return 'Na-update $ago';
  }

  @override
  String trackOffline(String time) {
    return 'Offline. Ipinapakita ang huling lokasyon mula $time.';
  }

  @override
  String get youAreHere => 'Iyong lokasyon';

  @override
  String responderMarker(String callSign) {
    return 'Tagasagip $callSign';
  }

  @override
  String secondsAgo(int n) {
    return '$n s ang nakalipas';
  }

  @override
  String minutesAgo(int n) {
    return '$n min ang nakalipas';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ang nakalipas';
  }

  @override
  String get mapAttribution => 'Mga nag-ambag sa OpenStreetMap';

  @override
  String get reportTitle => 'Mag-report ng panganib';

  @override
  String get reportExpectation =>
      'Ikinukumpara ng MDRRMD ang mga report sa iba pang kalapit na report bago kumilos.';

  @override
  String get reportSosHint =>
      'Nasa panganib ngayon? Gamitin ang SOS sa tab na Simula.';

  @override
  String get reportDescription => 'Ano ang nakikita mo?';

  @override
  String get reportDescriptionHint =>
      'Halimbawa: Hanggang tuhod na ang tubig sa Dapitan St at tumataas pa.';

  @override
  String get reportType => 'Uri (opsyonal)';

  @override
  String get reportLocation => 'Lokasyon';

  @override
  String get reportLocationLast =>
      'Huling lokasyon mo. I-on ang GPS para mas tumpak.';

  @override
  String get reportLocationFinding => 'Kinukuha ang iyong lokasyon';

  @override
  String get reportSend => 'Ipadala ang report';

  @override
  String get reportSaving => 'Isine-save';

  @override
  String get reportEmpty => 'Ilarawan ang nakikita mo.';

  @override
  String get reportOutsideManila =>
      'Nasa labas ng Manila City ang lokasyong ito. Manila lang ang sakop ng S.A.G.I.P.';

  @override
  String get reportRateLimited =>
      'Nakapagpadala ka na ng ilang report nitong nakaraang oras. Subukan mamaya, o tawagan ang MDRRMD.';

  @override
  String get reportNoLocation =>
      'Kailangan ang lokasyon mo para magpadala ng report. I-on ang GPS at subukan muli.';

  @override
  String get reportAccountSuspended =>
      'Hindi makapagpadala ng report ang account na ito ngayon. Sa emergency, pindutin nang matagal ang SOS o tawagan ang MDRRMD.';

  @override
  String get reportSentTitle => 'Naipadala ang report';

  @override
  String get reportSavedTitle => 'Naka-save sa iyong phone';

  @override
  String get reportSentBody =>
      'Salamat po. Ikinukumpara ng MDRRMD ang mga report sa iba pang kalapit na report bago kumilos.';

  @override
  String get reportSavedBody => 'Ipapadala kapag online ka na ulit.';

  @override
  String get reportSeeQueue => 'Tingnan ang naghihintay';

  @override
  String get reportAnother => 'Magpadala ng isa pang report';

  @override
  String get unitAvailable => 'Handang tumugon';

  @override
  String get unitEnRoute => 'Paparating';

  @override
  String get unitOnScene => 'Nasa lugar na';

  @override
  String unitDetail(String type, String station, int crew) {
    return '$type ? $station ? $crew na tauhan';
  }

  @override
  String sharingLocation(String ago) {
    return 'Ibinabahagi ang lokasyon ? naipadala $ago';
  }

  @override
  String locationNotShared(String ago) {
    return 'Hindi ibinabahagi ang lokasyon habang offline. Huling naipadala $ago.';
  }

  @override
  String get waitingForGps => 'Hinihintay ang GPS';

  @override
  String get dutyNoticeTitle => 'Ibinabahagi ng S.A.G.I.P. ang iyong lokasyon';

  @override
  String get dutyNoticeText =>
      'Nakikita ng MDRRMD dispatcher ang iyong yunit habang naka-sign in ka. Mag-sign out para ihinto.';

  @override
  String get dutyNoticeChannel => 'Pagbabahagi ng lokasyon ng yunit';

  @override
  String get noAssignmentTitle => 'Walang atas. Manatiling handang tumugon.';

  @override
  String get noAssignmentBody =>
      'Lalabas dito ang mga bagong atas at sa alert na sakop ang buong screen.';

  @override
  String get statusNoAssignment =>
      'Walang atas na pupuntahan o lugar na tutugunan.';

  @override
  String get statusFinishReport =>
      'Ipadala muna ang report ng natapos na pagsagip. Pagkatapos, magiging handang tumugon ang yunit.';

  @override
  String get statusAlreadyOnScene => 'Nasa lugar ka na.';

  @override
  String get currentAssignment => 'Kasalukuyang atas';

  @override
  String get openAssignment => 'Buksan';

  @override
  String get newAssignment => 'Bagong atas';

  @override
  String get newAssignmentOpen => 'Tingnan ang bagong atas';

  @override
  String distanceEta(String distance, int minutes) {
    return '$distance ang layo ? mga $minutes min';
  }

  @override
  String vulnerableTypes(String types) {
    return 'Nangangailangan ng dagdag na tulong: $types';
  }

  @override
  String get vulnSenior => 'Senior citizen';

  @override
  String get vulnPwd => 'Taong may kapansanan';

  @override
  String get vulnPregnant => 'Buntis';

  @override
  String get vulnOther => 'Iba pa';

  @override
  String get typeUnknown => 'Emergency';

  @override
  String get acceptAndStart => 'Tanggapin at simulan';

  @override
  String get viewDetails => 'Tingnan ang mga detalye';

  @override
  String assignmentTitle(String id) {
    return 'Atas $id';
  }

  @override
  String get assignmentReassigned =>
      'Inilipat sa iba o isinara ng dispatcher ang atas na ito.';

  @override
  String get victimLocation => 'Pupuntahan';

  @override
  String get incidentDetails => 'Ano ang ni-report';

  @override
  String reportedVia(String channel) {
    return 'Ni-report sa $channel';
  }

  @override
  String get channelApp => 'app';

  @override
  String get channelSms => 'SMS';

  @override
  String get channelBle => 'mga kalapit na phone';

  @override
  String get channelWeb => 'web form';

  @override
  String peopleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tao',
      one: '1 tao',
    );
    return '$_temp0';
  }

  @override
  String residentSaid(String note) {
    return 'Sabi ng residente: $note';
  }

  @override
  String mapSaving(int percent) {
    return 'Isine-save ang map para magamit offline, $percent%';
  }

  @override
  String get mapSaved => 'Naka-save ang map para magamit offline';

  @override
  String mapNotSaved(int percent) {
    return 'Hindi pa kumpletong naka-save ang map ($percent%). Magpapatuloy kapag online ka na ulit.';
  }

  @override
  String get startNavigation => 'Simulan ang paggabay';

  @override
  String get markOnScene => 'Itakdang nasa lugar na';

  @override
  String get continueOnScene => 'Ituloy ang pagsusuri sa lugar';

  @override
  String get fileReport => 'Gumawa ng report ng natapos na pagsagip';

  @override
  String get callDispatcher => 'Tawagan ang dispatcher';

  @override
  String get navigateTitle => 'Gabay sa daan';

  @override
  String headDirection(String direction) {
    return 'Pumunta sa $direction';
  }

  @override
  String get dirN => 'hilaga';

  @override
  String get dirNE => 'hilagang-silangan';

  @override
  String get dirE => 'silangan';

  @override
  String get dirSE => 'timog-silangan';

  @override
  String get dirS => 'timog';

  @override
  String get dirSW => 'timog-kanluran';

  @override
  String get dirW => 'kanluran';

  @override
  String get dirNW => 'hilagang-kanluran';

  @override
  String toGo(String distance) {
    return '$distance pa';
  }

  @override
  String get straightLineNote =>
      'Diretsong linya. Darating ang mga ruta sa kalsada sa susunod na bersyon.';

  @override
  String get roadRouteNote =>
      'Ruta sa kalsada mula sa OpenStreetMap. Tantiya ang mga oras.';

  @override
  String routeAvoidsHazards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kumpirmadong baha at sunog',
      one: '1 kumpirmadong baha o sunog',
    );
    return 'Umiiwas ang ruta sa $_temp0 kapag kaya.';
  }

  @override
  String turnOnto(String turn, String street) {
    String _temp0 = intl.Intl.selectLogic(turn, {
      'straight': 'Dumiretso sa $street',
      'slightLeft': 'Bahagyang kumaliwa sa $street',
      'left': 'Kumaliwa sa $street',
      'sharpLeft': 'Kumaliwa nang matalim sa $street',
      'slightRight': 'Bahagyang kumanan sa $street',
      'right': 'Kumanan sa $street',
      'sharpRight': 'Kumanan nang matalim sa $street',
      'uTurn': 'Mag-U-turn sa $street',
      'other': 'Pumunta sa $street',
    });
    return '$_temp0';
  }

  @override
  String turnHere(String turn) {
    String _temp0 = intl.Intl.selectLogic(turn, {
      'straight': 'Dumiretso',
      'slightLeft': 'Bahagyang kumaliwa',
      'left': 'Kumaliwa',
      'sharpLeft': 'Kumaliwa nang matalim',
      'slightRight': 'Bahagyang kumanan',
      'right': 'Kumanan',
      'sharpRight': 'Kumanan nang matalim',
      'uTurn': 'Mag-U-turn',
      'other': 'Magpatuloy',
    });
    return '$_temp0';
  }

  @override
  String inDistance(String distance) {
    return 'Pagkalipas ng $distance';
  }

  @override
  String get continueToScene => 'Magpatuloy sa lugar';

  @override
  String get offlineSavedMap => 'Offline. Gamit ang naka-save na map.';

  @override
  String get arrived => 'Dumating na';

  @override
  String get atScene => 'Nasa lugar ka na';

  @override
  String voiceAheadMeters(int meters, String turn) {
    return 'Pagkalipas ng $meters metro, $turn';
  }

  @override
  String voiceAheadKilometers(String kilometers, String turn) {
    return 'Pagkalipas ng $kilometers kilometro, $turn';
  }

  @override
  String get voiceOn =>
      'Naka-on ang binibigkas na gabay. I-tap para patahimikin.';

  @override
  String get voiceOff => 'Naka-off ang binibigkas na gabay. I-tap para i-on.';

  @override
  String distanceAway(String distance) {
    return '$distance ang layo';
  }

  @override
  String get recenter => 'Igitna muli';

  @override
  String get destination => 'Pupuntahan';

  @override
  String get yourUnit => 'Iyong yunit';

  @override
  String get onSceneTitle => 'Nasa lugar na';

  @override
  String onSceneAt(String time) {
    return 'Dumating nang $time';
  }

  @override
  String get realEmergencyQuestion => 'Totoong emergency ba ito?';

  @override
  String get yes => 'Oo';

  @override
  String get no => 'Hindi';

  @override
  String get notRealReason => 'Bakit hindi? (kailangan)';

  @override
  String get notRealReasonHint =>
      'Halimbawa: walang tao sa address, natugunan na';

  @override
  String get peopleFound => 'Mga taong nakita';

  @override
  String get completeRescue => 'Tapusin ang pagsagip';

  @override
  String get answerRealFirst => 'Sagutin kung totoong emergency ito.';

  @override
  String get reasonRequired =>
      'Sabihin kung bakit hindi ito totoong emergency.';

  @override
  String get completeTitle => 'Report ng natapos na pagsagip';

  @override
  String get outcome => 'Resulta';

  @override
  String get outcomeRescued => 'Nasagip';

  @override
  String get outcomeTreated => 'Nagamot sa lugar';

  @override
  String get outcomeTransported => 'Naihatid';

  @override
  String get outcomeNoOne => 'Walang taong nakita';

  @override
  String get outcomeFalse => 'Maling report';

  @override
  String get personsAssisted => 'Mga taong natulungan';

  @override
  String get damageTitle => 'Pagtatasa ng pinsala';

  @override
  String get housesDamaged => 'Mga bahay na napinsala';

  @override
  String get injured => 'Nasugatan';

  @override
  String get missing => 'Nawawala';

  @override
  String get affectedFamilies => 'Mga pamilyang naapektuhan';

  @override
  String get reportNotes => 'Mga tala (opsyonal)';

  @override
  String timeOnScene(int minutes) {
    return 'Oras sa lugar: $minutes min';
  }

  @override
  String get submitReport => 'Ipadala ang report';

  @override
  String get chooseOutcome => 'Pumili ng resulta.';

  @override
  String get reportSubmitted =>
      'Naipadala ang report. Handang tumugon muli ang yunit.';

  @override
  String get reportSavedOffline =>
      'Naka-save sa iyong phone ang report. Ipapadala kapag online ka na ulit.';

  @override
  String get demoOffer => 'Magpadala ng atas ngayon';

  @override
  String get demoClose => 'Isinasara ng dispatcher ang atas';

  @override
  String get starting => 'Nagsisimula';

  @override
  String get welcomeStep1Title => 'Ibahagi ang iyong lokasyon';

  @override
  String get welcomeStep1Body =>
      'Para makita sa SOS mo kung nasaan ka mismo, at makita mong paparating ang tagasagip.';

  @override
  String get welcomeStep2Title => 'Makatanggap ng mga alert';

  @override
  String get welcomeStep2Body =>
      'Mga babala sa panahon, update sa iyong SOS, at abiso kapag nakarating na ang naka-save sa iyong phone.';

  @override
  String get welcomeStep3Title => 'Gamitin ang SOS kahit walang internet';

  @override
  String get welcomeStep3Body =>
      'Kapag walang data, ipinapadala ang SOS mo sa SMS. Kapag wala talagang signal, puwedeng ipasa ito ng mga kalapit na phone.';

  @override
  String get allow => 'Payagan';

  @override
  String get allowed => 'Pinayagan';

  @override
  String get notAllowed =>
      'Hindi pinayagan. Gumagana pa ang SOS, pero hindi kasing maaasahan.';

  @override
  String get next => 'Susunod';

  @override
  String get skip => 'Laktawan';

  @override
  String get getStarted => 'Magsimula';

  @override
  String welcomeStepOf(int step, int total) {
    return 'Hakbang $step sa $total';
  }

  @override
  String get residentSignInTitle => 'Mag-sign in';

  @override
  String get residentSignInBody =>
      'Ilagay ang mobile number mo. Magte-text kami ng code.';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get mobileNumberHint => '917 123 4567';

  @override
  String get sendCode => 'Ipadala ang code';

  @override
  String get sendingCode => 'Ipinapadala ang code';

  @override
  String get createAccountPrompt => 'Bago sa S.A.G.I.P.? Gumawa ng account';

  @override
  String get staffSignInLink => 'Sign in ng tauhan ng MDRRMD';

  @override
  String get hotlineCardTitle => 'Sa emergency, tawagan ang MDRRMD';

  @override
  String get offlineSignIn =>
      'Offline ka. Kailangan ng internet para mag-sign in. Sa emergency, tawagan ang MDRRMD.';

  @override
  String get demoAccounts => 'Mga demo account';

  @override
  String get phoneInvalid =>
      'Ilagay ang mobile number sa Pilipinas, gaya ng 917 123 4567.';

  @override
  String get phoneNotRegistered => 'Wala pang account ang numerong ito.';

  @override
  String get phoneTaken => 'May account na ang numerong ito. Mag-sign in.';

  @override
  String get phoneWrongCode =>
      'Mali o paso na ang code na iyan. Tingnan ito o magpadala ng bago.';

  @override
  String get phoneTooMany =>
      'Masyadong maraming pagsubok. Subukan muli pagkalipas ng 60 s.';

  @override
  String get phoneOffline => 'Offline ka. Kumonekta para magpatuloy.';

  @override
  String get phoneUnavailable =>
      'Hindi maipadala o masuri ang code ngayon. Subukan muli makalipas ang ilang minuto. Sa emergency, tawagan ang MDRRMD.';

  @override
  String get staffSignInTitle => 'Mga tauhan ng MDRRMD';

  @override
  String get staffSignInBody =>
      'Mag-sign in gamit ang account na ibinigay sa iyo ng MDRRMD.';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signInButton => 'Mag-sign in';

  @override
  String get staffDemoHint => 'Demo: r03@sagip.test, password sagip-demo';

  @override
  String get registerTitle => 'Gumawa ng account';

  @override
  String get registerBody =>
      'Ginagamit ito ng MDRRMD para makontak ka at malaman ang iyong barangay.';

  @override
  String get fullName => 'Buong pangalan';

  @override
  String get barangay => 'Barangay';

  @override
  String get chooseBarangay => 'Piliin ang iyong barangay';

  @override
  String get searchBarangay => 'Maghanap ng barangay';

  @override
  String get sampleBarangays =>
      'Halimbawang listahan. Susunod pa ang buong listahan ng 897 barangay sa Manila.';

  @override
  String get noBarangayMatch => 'Walang tugmang barangay.';

  @override
  String get agreeTerms =>
      'Sumasang-ayon ako sa mga tuntunin at abiso sa privacy';

  @override
  String get readPrivacy => 'Basahin ang abiso sa privacy';

  @override
  String get continueButton => 'Magpatuloy';

  @override
  String get creatingAccount => 'Gumagawa ng account';

  @override
  String get nameRequired => 'Ilagay ang buong pangalan mo.';

  @override
  String get barangayRequired => 'Piliin ang iyong barangay.';

  @override
  String get termsRequired => 'Sumang-ayon sa mga tuntunin para magpatuloy.';

  @override
  String get verifyTitle => 'Ilagay ang code';

  @override
  String verifyBody(String phone) {
    return 'Nagpadala kami ng 6-digit na code sa $phone.';
  }

  @override
  String get codeLabel => '6-digit na code';

  @override
  String get checkCode => 'Suriin ang code';

  @override
  String get checkingCode => 'Sinusuri ang code';

  @override
  String resendIn(String time) {
    return 'Ipadala muli ang code pagkalipas ng $time';
  }

  @override
  String get resendCode => 'Ipadala muli ang code';

  @override
  String get codeSent => 'Paparating na ang bagong code.';

  @override
  String get changeNumber => 'Palitan ang numero';

  @override
  String get waitingForConnection =>
      'Hinihintay ang koneksyon. Nakatago ang iyong code.';

  @override
  String demoCodeHint(String code) {
    return 'Demo code: $code';
  }

  @override
  String get profile => 'Profile';

  @override
  String get myActivity => 'Mga ginawa ko';

  @override
  String get vulnerabilityProfile => 'Profile para sa dagdag na tulong';

  @override
  String get settings => 'Mga setting';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Ayon sa system';

  @override
  String get themeLight => 'Maliwanag';

  @override
  String get themeDark => 'Madilim';

  @override
  String get language => 'Wika';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFilipino => 'Filipino';

  @override
  String get languageChoose => 'Pumili ng wika';

  @override
  String get testNotification => 'Magpadala ng pagsubok na abiso';

  @override
  String get testNotificationSent =>
      'Pagsubok: ganito lumalabas ang mga alert ng S.A.G.I.P.';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyNotice => 'Abiso sa privacy';

  @override
  String get requestDeletion => 'Hilinging burahin ang data ko';

  @override
  String get requestDeletionTitle => 'Burahin ang iyong data?';

  @override
  String get requestDeletionBody =>
      'Buburahin ng MDRRMD ang iyong profile at listahan ng mga kasama sa bahay. Itatago lang nila ang hinihingi ng batas para sa mga tala ng insidente. Kakailanganin mo ng bagong account para magpadala ng SOS.';

  @override
  String get requestDeletionConfirm => 'Ipadala ang hiling';

  @override
  String get requestDeletionSent =>
      'Naipadala ang hiling. Kokontakin ka ng MDRRMD para kumpirmahin.';

  @override
  String get cancel => 'Kanselahin';

  @override
  String get signOutTitle => 'Mag-sign out?';

  @override
  String signOutWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count item ang',
      one: '1 item ang',
    );
    return '$_temp0 naghihintay maipadala. Mananatili ang mga ito sa phone na ito at ipapadala kapag nag-sign in ka ulit.';
  }

  @override
  String get privacyTitle => 'Abiso sa privacy';

  @override
  String get privacyCollectTitle => 'Ano ang kinokolekta namin';

  @override
  String get privacyCollectBody =>
      'Ang iyong pangalan, mobile number, at barangay; kung nasaan ka kapag nagpapadala ka ng SOS o report, at kung saan gumagalaw ang phone mo habang bukas ang SOS na iyon; at, kung papayag ka lang, ang mga kasama sa bahay na maaaring kailangang unahing sagipin; at anumang larawang pipiliin mong idagdag sa SOS o report (ipinapadala nang walang location data na itinatago ng camera mo).';

  @override
  String get privacyWhyTitle => 'Bakit';

  @override
  String get privacyWhyBody =>
      'Para mahanap at marating ka sa emergency, makapagpadala ng mga alert para sa lugar mo, at makapagplano ng pagsagip para sa mga nangangailangan ng dagdag na tulong.';

  @override
  String get privacyWhoTitle => 'Sino ang makakakita nito';

  @override
  String get privacyWhoBody =>
      'Mga dispatcher at administrador ng MDRRMD. Ang mga tagasagip ay makakakita lang ng insidenteng nakatalaga sa kanila at mga uri ng pangangailangan ng dagdag na tulong, hindi kailanman ng mga pangalan.';

  @override
  String get privacyKeepTitle => 'Gaano katagal namin ito itatago';

  @override
  String get privacyKeepBody =>
      'Ang mga detalye ng account mo, hangga\'t may account ka. Isang taon matapos isara ang SOS o report (maaaring magtakda ang MDRRMD ng ibang panahon), inaalis dito ang makapagtuturo sa iyo: ang pangalan mo, tala mo, at eksaktong lugar. Nananatili ang mismong rekord para sa mga report ng MDRRMD. Itinatago rin sa lahat ang mga larawan sa parehong oras.';

  @override
  String get privacyRightsTitle => 'Iyong mga karapatan';

  @override
  String get privacyRightsBody =>
      'Sa ilalim ng Batas sa Privacy ng Data (RA 10173), maaari mong tingnan, itama, o hilinging burahin namin ang data mo, at bawiin ang pahintulot anumang oras sa Ako.';

  @override
  String get incPending => 'Hinihintay ang pag-verify';

  @override
  String get incUnverified => 'Hindi pa na-verify';

  @override
  String get incConfirmed => 'Kumpirmado';

  @override
  String get incAssigned => 'May nakatalaga';

  @override
  String get incEnRoute => 'Paparating';

  @override
  String get incOnScene => 'Nasa lugar na';

  @override
  String get incResolved => 'Natugunan na';

  @override
  String get pickLocationTitle => 'Pumili ng lokasyon';

  @override
  String get pickSearch => 'Maghanap ng barangay';

  @override
  String get pickUseGps => 'Gamitin ang GPS ko';

  @override
  String get pickNoGps =>
      'Hindi pa makuha ng GPS ang lokasyon. Igalaw ang map o pumili ng barangay.';

  @override
  String pickNear(String place) {
    return 'Malapit sa $place';
  }

  @override
  String get pickNoBarangay => 'Makikita ng MDRRMD ang eksaktong pin.';

  @override
  String get pickMoveHint => 'Igalaw ang map para mailagay ang pin sa lugar.';

  @override
  String get pickConfirm => 'Gamitin ang lokasyong ito';

  @override
  String get pickOfflineTitle => 'Walang map habang offline';

  @override
  String get pickOfflineBody =>
      'Gamitin ang lokasyon sa GPS o piliin ang iyong barangay.';

  @override
  String get pickGpsOption => 'Lokasyon sa GPS ko';

  @override
  String get pickPin => 'Napiling lugar';

  @override
  String get reportChangeLocation => 'Baguhin';

  @override
  String get reportLocationChosen => 'Pinili mo';

  @override
  String get reportUseGpsAgain => 'Gamitin na lang ang GPS ko';

  @override
  String get activityTabSos => 'SOS';

  @override
  String get activityTabReports => 'Mga report';

  @override
  String get activitySosEmpty =>
      'Wala pang SOS. Kung magpadala ka, lalabas ito rito.';

  @override
  String get activityReportsEmpty =>
      'Wala pang report. Lalabas dito ang mga report na ipapadala mo.';

  @override
  String get activityError =>
      'Hindi ma-refresh. Ipinapakita ang naka-save mong listahan.';

  @override
  String get stageReceived => 'Natanggap';

  @override
  String get stageChecking => 'Sinusuri';

  @override
  String get stageConfirmed => 'Kumpirmado';

  @override
  String get stageNotConfirmed => 'Hindi nakumpirma';

  @override
  String get stageResolved => 'Natugunan na';

  @override
  String get reportDetailTitle => 'Iyong report';

  @override
  String get reportStepReceived => 'Natanggap';

  @override
  String get reportStepChecking => 'Ikinukumpara sa mga kalapit na report';

  @override
  String get reportStepConfirmed => 'Bahagi ng kumpirmadong insidente';

  @override
  String get reportStepResolved => 'Natugunan na';

  @override
  String get reportNoteWaiting =>
      'Naka-save sa iyong phone. Ipapadala kapag online ka na ulit.';

  @override
  String get reportNoteReceived => 'Nasa MDRRMD na ang iyong report.';

  @override
  String get reportNoteChecking =>
      'Kumikilos ang MDRRMD kapag ilang tao ang nag-report ng parehong pangyayari sa magkakalapit na lugar. Ikinukumpara ang sa iyo sa ibang report nitong nakaraang oras.';

  @override
  String reportNoteConfirmed(String id) {
    return 'Ang iyong report at iba pang kalapit na report ay naging insidente $id. Tinutugunan ito ng mga tagasagip.';
  }

  @override
  String get reportNoteNotConfirmed =>
      'Walang ibang nag-report nito sa malapit sa loob ng oras na iyon. Itinatago ng MDRRMD ang iyong report sa mga tala.';

  @override
  String reportNoteResolved(String id) {
    return 'Natugunan na ang insidente $id.';
  }

  @override
  String capturedAt(String time) {
    return 'Naipadala $time';
  }

  @override
  String get alertsTitle => 'Mga alert';

  @override
  String get alertsTabAlerts => 'Mga alert';

  @override
  String get alertsTabForecast => 'Pagtataya';

  @override
  String get alertsEmpty => 'Walang aktibong alert para sa Manila.';

  @override
  String get alertsError =>
      'Hindi makuha ang mga alert. Hilahin pababa para subukan muli.';

  @override
  String alertsOffline(String time) {
    return 'Offline. Huling na-update $time.';
  }

  @override
  String get rescueSection => 'Tungkol sa iyong SOS';

  @override
  String get rescueKindAssigned => 'May nakatalagang yunit';

  @override
  String get rescueKindOnScene => 'Nasa lugar na';

  @override
  String get rescueKindResolved => 'Isinara';

  @override
  String get rescueAssignedTitle => 'Paparating ang grupong tagasagip';

  @override
  String rescueAssignedBody(String unit) {
    return 'Ipinadala ang $unit sa lokasyon mo. Manatili po kung nasaan ka kung ligtas.';
  }

  @override
  String get rescueAssignedBodyNoUnit =>
      'Ipinadala ang grupong tagasagip sa lokasyon mo. Manatili po kung nasaan ka kung ligtas.';

  @override
  String get rescueOnSceneTitle => 'Dumating na ang grupong tagasagip';

  @override
  String rescueOnSceneBody(String unit) {
    return 'Nasa lokasyon mo ang $unit.';
  }

  @override
  String get rescueOnSceneBodyNoUnit =>
      'Nasa lokasyon mo ang grupong tagasagip.';

  @override
  String get rescueResolvedTitle => 'Isinara ang iyong SOS';

  @override
  String get rescueResolvedBody =>
      'Isinara ng MDRRMD ang SOS na ito. Kung kailangan mo pa ng tulong, magpadala ng bagong SOS.';

  @override
  String rescueRef(String id) {
    return 'SOS $id';
  }

  @override
  String get alertAllManila => 'Buong Manila';

  @override
  String get alertNew => 'Bago';

  @override
  String get sourcePagasa => 'PAGASA';

  @override
  String get sourcePhivolcs => 'PHIVOLCS';

  @override
  String get sourceEfcos => 'EFCOS';

  @override
  String get sourceMdrrmd => 'MDRRMD';

  @override
  String get levelInfo => 'Abiso';

  @override
  String get levelWarning => 'Babala';

  @override
  String get levelCritical => 'Panganib';

  @override
  String alertIssued(String time) {
    return 'Inilabas $time';
  }

  @override
  String get alertAffects => 'Mga apektadong lugar';

  @override
  String get alertWhatToDo => 'Ano ang gagawin';

  @override
  String get alertGone => 'Wala na ang alert na ito.';

  @override
  String unreadAlerts(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n bagong alert',
      one: '1 bagong alert',
    );
    return '$_temp0';
  }

  @override
  String get forecastTitle => 'Susunod na 72 oras';

  @override
  String get forecastExplain =>
      'Tsansang magkaroon ng kahit isang insidente sa iyong barangay.';

  @override
  String forecastValid(String time) {
    return 'May bisa hanggang $time';
  }

  @override
  String get forecastSimulated =>
      'Halimbawang pagtataya. Ginagayang data muna ang gamit ng modelo.';

  @override
  String get forecastEmpty =>
      'Wala pang pagtataya. Ina-update ang mga pagtataya araw-araw.';

  @override
  String get hazardFlood => 'Baha';

  @override
  String get hazardFire => 'Sunog';

  @override
  String get hazardSurge => 'Daluyong mula sa bagyo';

  @override
  String get riskLow => 'Mababa';

  @override
  String get riskModerate => 'Katamtaman';

  @override
  String get riskHigh => 'Mataas';

  @override
  String get tipsTitle => 'Maghanda';

  @override
  String get tipsLow =>
      'Mababa ang panganib sa iyong barangay. Maghanda ng bag para sa emergency at panatilihing may charge ang phone mo.';

  @override
  String get tipFlood1 =>
      'Ilipat sa mas mataas na lugar ang mga appliance at mahahalagang papeles.';

  @override
  String get tipFlood2 =>
      'Maghanda ng bag na may tubig, pagkain, gamot, at flashlight.';

  @override
  String get tipFlood3 =>
      'Alamin ang pinakaligtas na daan mula sa bahay mo papunta sa mas mataas na lugar.';

  @override
  String get tipFire1 =>
      'Patayin ang kalan at tanggalin sa saksakan ang mga appliance bago matulog.';

  @override
  String get tipFire2 =>
      'Panatilihing walang harang ang daan papunta sa pinto.';

  @override
  String get tipFire3 =>
      'Alamin kung nasaan ang pinakamalapit na fire extinguisher.';

  @override
  String get tipSurge1 => 'Lumayo sa baybayin ng look at sa Baywalk.';

  @override
  String get tipSurge2 =>
      'Maghandang lumipat palayo sa baybayin kung hihilingin ng MDRRMD.';

  @override
  String get tipSurge3 =>
      'Ilagay ang mahahalagang papeles sa bag na hindi pinapasok ng tubig.';

  @override
  String get vulnIntro =>
      'Sabihin sa MDRRMD kung sino sa bahay mo ang maaaring kailangang unahing sagipin.';

  @override
  String get vulnPrivacyNote =>
      'Mga dispatcher at administrador lang ng MDRRMD ang makakakita nito.';

  @override
  String vulnConsentGiven(String date) {
    return 'Ibinigay ang pahintulot $date';
  }

  @override
  String get vulnConsentNeeded =>
      'Kailangan ng MDRRMD ang pahintulot mo bago itago ang impormasyong ito.';

  @override
  String get vulnGiveConsent => 'Basahin at magbigay ng pahintulot';

  @override
  String get vulnWithdraw => 'Bawiin ang pahintulot';

  @override
  String get vulnWithdrawTitle => 'Bawiin ang pahintulot?';

  @override
  String get vulnWithdrawBody =>
      'Buburahin ang listahan ng mga kasama mo sa bahay. Hindi na ito makikita ng mga dispatcher.';

  @override
  String get vulnWithdrawConfirm => 'Bawiin at burahin';

  @override
  String get vulnWithdrawn =>
      'Nabawi ang pahintulot. Binura ang listahan ng mga kasama mo sa bahay.';

  @override
  String get vulnEmpty =>
      'Idagdag ang mga kasama sa bahay na maaaring kailangang unahing sagipin.';

  @override
  String get vulnAdd => 'Magdagdag ng kasama sa bahay';

  @override
  String vulnEditMember(String name) {
    return 'Baguhin si $name';
  }

  @override
  String vulnRemoveMember(String name) {
    return 'Alisin si $name';
  }

  @override
  String vulnRemoveTitle(String name) {
    return 'Alisin si $name?';
  }

  @override
  String get vulnRemoveBody =>
      'Hindi na makikita ng mga dispatcher ang taong ito sa listahan ng mga uunahin.';

  @override
  String get vulnRemoveConfirm => 'Alisin';

  @override
  String get vulnRemoved => 'Inalis sa iyong listahan.';

  @override
  String get vulnSaved => 'Na-save.';

  @override
  String get vulnOffline =>
      'Offline ka. Kumonekta para gumawa ng mga pagbabago.';

  @override
  String get vulnError => 'Hindi makuha ang iyong profile.';

  @override
  String get consentTitle => 'Pahintulot sa privacy ng data';

  @override
  String get consentIntro =>
      'Bago itago ng MDRRMD ang impormasyon tungkol sa mga kasama mo sa bahay na maaaring mangailangan ng dagdag na tulong, basahin po ito.';

  @override
  String get consentCollectTitle => 'Ano ang itinatago namin';

  @override
  String get consentCollectBody =>
      'Pangalan o paglalarawan ng bawat tao, ang uri ng tulong na maaaring kailangan nila (senior citizen, taong may kapansanan, buntis, o iba pa), at ang iyong mga tala.';

  @override
  String get consentWhyTitle => 'Bakit';

  @override
  String get consentWhyBody =>
      'Para maunang makapagpadala ng tulong sa kanila ang mga dispatcher kapag may sakuna.';

  @override
  String get consentWhoTitle => 'Sino ang makakakita nito';

  @override
  String get consentWhoBody =>
      'Mga dispatcher at administrador lang ng MDRRMD. Makikita ng mga tagasagip ang uri ng tulong na kailangan, hindi kailanman ang mga pangalan.';

  @override
  String get consentKeepTitle => 'Gaano katagal namin ito itatago';

  @override
  String get consentKeepBody =>
      'Hanggang alisin mo ang isang tao o bawiin ang pahintulot.';

  @override
  String get consentWithdrawTitle => 'Paano bawiin';

  @override
  String get consentWithdrawBody =>
      'Buksan ang Ako, pagkatapos ang Profile para sa dagdag na tulong, at pagkatapos ang Bawiin ang pahintulot. Agad na buburahin ang listahan.';

  @override
  String get consentLaw => 'Batas sa Privacy ng Data ng 2012 (RA 10173).';

  @override
  String get consentCheck =>
      'Pumapayag akong itago ng MDRRMD ang impormasyong ito';

  @override
  String get consentAgree => 'Pumapayag ako';

  @override
  String get consentNotNow => 'Huwag muna';

  @override
  String get consentSaving => 'Isine-save';

  @override
  String get consentOffline => 'Kumonekta para magbigay ng pahintulot.';

  @override
  String get consentSaved =>
      'Na-save ang pahintulot. Maaari ka nang magdagdag ng mga kasama sa bahay.';

  @override
  String get memberAddTitle => 'Magdagdag ng kasama sa bahay';

  @override
  String get memberEditTitle => 'Baguhin ang kasama sa bahay';

  @override
  String get memberLabel => 'Pangalan o paglalarawan';

  @override
  String get memberLabelHint => 'Halimbawa, Lola Rosa';

  @override
  String get memberLabelRequired => 'Maglagay ng pangalan o paglalarawan.';

  @override
  String get memberTypes => 'Piliin ang lahat ng naaangkop';

  @override
  String get memberTypesRequired => 'Pumili ng kahit isa.';

  @override
  String get memberNotes => 'Mga tala (opsyonal)';

  @override
  String get memberNotesHint => 'Halimbawa, gumagamit ng wheelchair';

  @override
  String memberWhere(String barangay) {
    return 'Gagamitin ng MDRRMD ang address ng bahay mo sa $barangay para sa taong ito.';
  }

  @override
  String get memberSave => 'I-save';

  @override
  String get memberSaving => 'Isine-save';

  @override
  String get memberOffline => 'Offline ka. Kumonekta para mag-save.';

  @override
  String get memberGone => 'Wala na sa iyong listahan ang taong ito.';

  @override
  String get historyTitle => 'Mga nakaraang atas';

  @override
  String get historyAll => 'Lahat';

  @override
  String get historyThisWeek => 'Ngayong linggo';

  @override
  String get historyLastWeek => 'Nakaraang linggo';

  @override
  String get historyEmpty => 'Wala pang natapos na atas.';

  @override
  String get historyEmptyFilter => 'Walang atas sa panahong ito.';

  @override
  String get historyError =>
      'Hindi ma-refresh. Ipinapakita ang naka-save na mga nakaraang atas.';

  @override
  String historyRowTitle(String id, String type) {
    return '$id ? $type';
  }

  @override
  String get errorGeneric => 'May nagkaproblema. Subukan muli.';

  @override
  String get retry => 'Subukan muli';

  @override
  String get safePlacesTitle => 'Mga ligtas na lugar';

  @override
  String get safePlacesWhat => 'Ano ang nangyayari?';

  @override
  String get safePlacesPick =>
      'Pumili ng isa para makita ang mga lugar na angkop dito.';

  @override
  String get safePlacesFromSos =>
      'Papunta ang tulong kung nasaan ka. Lumipat lang kung hindi ligtas manatili: susundan ng SOS mo ang phone mo.';

  @override
  String get safePlacesGoIfSafe =>
      'Pumunta lang kung ligtas kumilos. Sundin muna ang MDRRMD at ang mga opisyal ng barangay.';

  @override
  String get safeAdviceFlood =>
      'Kung tumataas ang tubig, umakyat muna sa mas mataas na palapag. Huwag lumusong sa tubig na lampas tuhod o umaagos.';

  @override
  String get safeAdviceFire =>
      'Lumayo sa usok. Mga bukas na lugar ito na hindi bababa sa 300 m mula sa sunog.';

  @override
  String get safeAdviceStructural =>
      'Lumayo sa mga pader, poste, at kawad. Mga bukas na lugar ito na malayo sa mga gusali.';

  @override
  String get safeAdviceMedical =>
      'Tawagan muna ang MDRRMD. Ito ang mga pinakamalapit na ospital.';

  @override
  String get safePlacesNoLocation =>
      'I-on ang GPS para makita ang mga ligtas na lugar na malapit sa iyo.';

  @override
  String get safePlacesNone =>
      'Walang nakitang angkop na lugar na malapit sa iyo. Tawagan ang MDRRMD.';

  @override
  String get safePlacesOffline =>
      'Offline: mula sa listahang naka-save sa phone mo. Hindi alam ang mga baha at sunog na naiulat mula noon.';

  @override
  String safePlaceWalk(int minutes, String distance) {
    return 'Mga $minutes minutong lakad ($distance) sa mga kalye';
  }

  @override
  String get safePlaceNoRoute =>
      'Walang nakitang daan sa kalye. Tuwid na layo ang distansya.';

  @override
  String get safePlaceOfficial => 'Opisyal na evacuation center';

  @override
  String safePlaceUnnamed(String kind, String barangay) {
    return '$kind, $barangay';
  }

  @override
  String get kindEvacuationCenter => 'Evacuation center';

  @override
  String get kindSchool => 'Paaralan';

  @override
  String get kindBarangayHall => 'Barangay hall';

  @override
  String get kindCoveredCourt => 'Covered court';

  @override
  String get kindBasketballCourt => 'Basketball court';

  @override
  String get kindOpenSpace => 'Parke o plaza';

  @override
  String get kindHospital => 'Ospital';

  @override
  String get sosSafePlacesTitle => 'Mga ligtas na lugar na malapit sa iyo';

  @override
  String sosSafePlacesNearest(String name, String distance) {
    return 'Pinakamalapit: $name, $distance';
  }

  @override
  String get sosSafePlacesButton => 'Tingnan ang mga ligtas na lugar';

  @override
  String get alertSafePlacesButton => 'Mga ligtas na lugar na malapit sa iyo';

  @override
  String get updateTitle => 'I-update ang S.A.G.I.P.';

  @override
  String get updateBody =>
      'Luma na ang bersyong ito ng app. I-download ang bago para patuloy itong magamit. Sa emergency, gumagana pa rin ang SOS at ang hotline ng MDRRMD.';

  @override
  String get updateDownload => 'I-download ang update';

  @override
  String updateLink(String url) {
    return 'O buksan ang $url sa iyong browser.';
  }

  @override
  String get updateOpenFailed =>
      'Hindi mabuksan ang link. I-type na lang ito sa iyong browser.';

  @override
  String get updateSosStill => 'Sa emergency, pindutin nang matagal ang SOS';

  @override
  String get photoAdd => 'Magdagdag ng larawan';

  @override
  String get photoAddOptional => 'Magdagdag ng larawan (opsyonal)';

  @override
  String get photoTake => 'Kumuha ng larawan';

  @override
  String get photoChoose => 'Pumili mula sa gallery';

  @override
  String get photoFailed => 'Hindi magamit ang larawang iyon. Subukan ang iba.';

  @override
  String get photoSaved =>
      'Naidagdag ang larawan. Ipapadala ito pagkatapos ng iyong SOS.';

  @override
  String get photoSosHint =>
      'Opsyonal. Nakatutulong ang larawan para makita ng MDRRMD ang nangyayari. Ipinapadala ito pagkatapos ng iyong SOS, hindi kailanman bago.';

  @override
  String photoSosCount(int count, int max) {
    return '$count sa $max larawan ang naidagdag. Ipapadala ang mga ito pagkatapos ng iyong SOS, kapag may internet.';
  }

  @override
  String get photoReportAdded =>
      'Naidagdag ang larawan. Ipapadala ito pagkatapos ng iyong ulat.';

  @override
  String get photoRemove => 'Alisin ang larawan';

  @override
  String get photoThumb => 'Ang larawang idinagdag mo';

  @override
  String get queueKindPhoto => 'Larawan';

  @override
  String photoDeliveredNotice(String time) {
    return 'Naihatid na ang iyong larawan mula $time.';
  }
}
