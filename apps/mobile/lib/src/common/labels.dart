import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Localized labels for domain enums. Keeps every visible word in the ARB
/// file so Filipino can be added without touching widgets.
extension MobileLabels on AppLocalizations {
  String delivery(DeliveryState s) => switch (s) {
    DeliveryState.savedOnPhone => deliverySaved,
    DeliveryState.sending => deliverySending,
    DeliveryState.sentBySms => deliverySms,
    DeliveryState.relaying => deliveryRelaying,
    DeliveryState.delivered => deliveryDelivered,
    DeliveryState.rejected => deliveryRejected,
  };

  String incidentType(IncidentType t) => switch (t) {
    IncidentType.flood => typeFlood,
    IncidentType.fire => typeFire,
    IncidentType.medical => typeMedical,
    IncidentType.structural => typeStructural,
  };

  String unitType(UnitType t) => switch (t) {
    UnitType.ambulance => unitAmbulance,
    UnitType.rescueBoat => unitRescueBoat,
    UnitType.rescueTeam => unitRescueTeam,
  };

  String queuedKind(QueuedKind k) => switch (k) {
    QueuedKind.sos => queueKindSos,
    QueuedKind.sosDetails => queueKindDetails,
    QueuedKind.crowdReport => queueKindReport,
    QueuedKind.statusUpdate => queueKindStatus,
    QueuedKind.completionReport => queueKindCompletion,
  };

  /// "Your SOS from 3:42 PM was delivered." (NFR1 delivery notice).
  String deliveredNotice(QueuedKind k, String time) => switch (k) {
    QueuedKind.sos => sosDeliveredNotice(time),
    QueuedKind.sosDetails => detailsDeliveredNotice(time),
    QueuedKind.crowdReport => reportDeliveredNotice(time),
    QueuedKind.statusUpdate => statusDeliveredNotice(time),
    QueuedKind.completionReport => completionDeliveredNotice(time),
  };

  String reportRejection(ReportRejection r) => switch (r) {
    ReportRejection.emptyDescription => reportEmpty,
    ReportRejection.outsideManila => reportOutsideManila,
    ReportRejection.rateLimited => reportRateLimited,
    ReportRejection.noLocation => reportNoLocation,
  };

  /// "40 s ago", "3 min ago", "2 h ago".
  String ago(DateTime then, DateTime now) {
    final d = now.difference(then);
    if (d.inSeconds < 60) return secondsAgo(d.inSeconds.clamp(0, 59));
    if (d.inMinutes < 60) return minutesAgo(d.inMinutes);
    return hoursAgo(d.inHours);
  }

  String unitStatus(UnitStatus s) => switch (s) {
    UnitStatus.available => unitAvailable,
    UnitStatus.enRoute => unitEnRoute,
    UnitStatus.onScene => unitOnScene,
  };

  String vulnerability(VulnerabilityType v) => switch (v) {
    VulnerabilityType.seniorCitizen => vulnSenior,
    VulnerabilityType.pwd => vulnPwd,
    VulnerabilityType.pregnant => vulnPregnant,
    VulnerabilityType.other => vulnOther,
  };

  /// "Reported by SMS", "Reported by the app".
  String reportedBy(ReportChannel c) => reportedVia(switch (c) {
    ReportChannel.app => channelApp,
    ReportChannel.sms => channelSms,
    ReportChannel.bleRelay => channelBle,
    ReportChannel.webForm => channelWeb,
  });

  String outcomeLabel(RescueOutcome o) => switch (o) {
    RescueOutcome.rescued => outcomeRescued,
    RescueOutcome.treated => outcomeTreated,
    RescueOutcome.transported => outcomeTransported,
    RescueOutcome.noOneFound => outcomeNoOne,
    RescueOutcome.falseReport => outcomeFalse,
  };

  String statusRejection(StatusRejection r) => switch (r) {
    StatusRejection.noAssignment => statusNoAssignment,
    StatusRejection.finishReportFirst => statusFinishReport,
    StatusRejection.alreadyOnScene => statusAlreadyOnScene,
  };

  String typeOrEmergency(IncidentType? t) =>
      t == null ? typeUnknown : incidentType(t);

  /// "Turn right onto España Boulevard", or "Turn right" on an unnamed road.
  String turnInstruction(RouteStep step) => step.street == null
      ? turnHere(step.turn.name)
      : turnOnto(step.turn.name, step.street!);

  /// "Head northeast" from a bearing in degrees.
  String heading(double degrees) {
    final points = [dirN, dirNE, dirE, dirSE, dirS, dirSW, dirW, dirNW];
    return headDirection(points[((degrees + 22.5) % 360 ~/ 45)]);
  }

  String phoneAuthFailure(PhoneAuthFailure f) => switch (f) {
    PhoneAuthFailure.invalidNumber => phoneInvalid,
    PhoneAuthFailure.notRegistered => phoneNotRegistered,
    PhoneAuthFailure.numberTaken => phoneTaken,
    PhoneAuthFailure.wrongCode => phoneWrongCode,
    PhoneAuthFailure.tooManyAttempts => phoneTooMany,
    PhoneAuthFailure.offline => phoneOffline,
    PhoneAuthFailure.unavailable => phoneUnavailable,
  };

  String signal(SignalState s) => switch (s) {
    SignalState.internet => signalInternet,
    SignalState.smsOnly => signalSms,
    SignalState.noSignal => signalNone,
  };

  String authFailure(AuthFailure f) => switch (f) {
    AuthFailure.wrongCredentials => signInWrongCredentials,
    AuthFailure.accountDisabled => signInDisabled,
    AuthFailure.notStaff => signInNotStaff,
    AuthFailure.offline => signInOffline,
  };

  /// The big label on R2: delivery until the server has it, then status.
  String sosState(SosRequest s) {
    if (s.delivery == DeliveryState.rejected) return sosStateRejected;
    if (!s.isDelivered) {
      return switch (s.delivery) {
        DeliveryState.sending => sosStateSending,
        DeliveryState.sentBySms => sosStateSms,
        DeliveryState.relaying => sosStateRelaying,
        _ => sosStateSaved,
      };
    }
    return switch (s.status) {
      IncidentStatus.confirmed => sosStateVerified,
      IncidentStatus.assigned => sosStateAssigned,
      IncidentStatus.enRoute => sosStateEnRoute,
      IncidentStatus.onScene => sosStateOnScene,
      IncidentStatus.resolved => sosStateResolved,
      _ => sosStatePending,
    };
  }

  /// Short status names for chips (design skill status mapping).
  String incidentStatus(IncidentStatus s) => switch (s) {
    IncidentStatus.pendingVerification => incPending,
    IncidentStatus.unverified => incUnverified,
    IncidentStatus.confirmed => incConfirmed,
    IncidentStatus.assigned => incAssigned,
    IncidentStatus.enRoute => incEnRoute,
    IncidentStatus.onScene => incOnScene,
    IncidentStatus.resolved => incResolved,
  };

  String reportStage(ReportStage s) => switch (s) {
    ReportStage.received => stageReceived,
    ReportStage.checking => stageChecking,
    ReportStage.confirmed => stageConfirmed,
    ReportStage.notConfirmed => stageNotConfirmed,
    ReportStage.resolved => stageResolved,
  };

  String alertSource(AlertSource s) => switch (s) {
    AlertSource.pagasa => sourcePagasa,
    AlertSource.phivolcs => sourcePhivolcs,
    AlertSource.efcos => sourceEfcos,
    AlertSource.mdrrmd => sourceMdrrmd,
  };

  String alertLevel(AlertLevel l) => switch (l) {
    AlertLevel.info => levelInfo,
    AlertLevel.warning => levelWarning,
    AlertLevel.critical => levelCritical,
  };

  String hazard(ForecastHazard h) => switch (h) {
    ForecastHazard.flood => hazardFlood,
    ForecastHazard.fire => hazardFire,
    ForecastHazard.stormSurge => hazardSurge,
  };

  String risk(RiskLevel r) => switch (r) {
    RiskLevel.low => riskLow,
    RiskLevel.moderate => riskModerate,
    RiskLevel.high => riskHigh,
  };

  /// Preparation tips for the riskiest hazard (R7 Forecast tab).
  List<String> tips(ForecastHazard h) => switch (h) {
    ForecastHazard.flood => [tipFlood1, tipFlood2, tipFlood3],
    ForecastHazard.fire => [tipFire1, tipFire2, tipFire3],
    ForecastHazard.stormSurge => [tipSurge1, tipSurge2, tipSurge3],
  };

  /// The caption under the SOS button on R1.
  String sosCaption(SosButtonPhase phase) => switch (phase) {
    SosButtonPhase.ready => sosHoldCaption,
    SosButtonPhase.sending => sosCaptionSending,
    SosButtonPhase.savedOnPhone => sosCaptionSaved,
    SosButtonPhase.sentBySms => sosCaptionSms,
    SosButtonPhase.relaying => sosCaptionRelaying,
    SosButtonPhase.delivered => sosCaptionDelivered,
  };
}

/// What the SOS button shows for the active SOS, if any.
SosButtonPhase sosPhase(SosRequest? active) => switch (active?.delivery) {
  null => SosButtonPhase.ready,
  DeliveryState.sending => SosButtonPhase.sending,
  DeliveryState.sentBySms => SosButtonPhase.sentBySms,
  DeliveryState.relaying => SosButtonPhase.relaying,
  DeliveryState.delivered => SosButtonPhase.delivered,
  DeliveryState.savedOnPhone ||
  DeliveryState.rejected => SosButtonPhase.savedOnPhone,
};
