import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Localized labels for domain enums. Keeps every visible word in the ARB
/// files so Filipino can be added without touching widgets.
extension DomainLabels on AppLocalizations {
  String incidentStatus(IncidentStatus s) => switch (s) {
    IncidentStatus.pendingVerification => statusPendingVerification,
    IncidentStatus.unverified => statusUnverified,
    IncidentStatus.confirmed => statusConfirmed,
    IncidentStatus.assigned => statusAssigned,
    IncidentStatus.enRoute => statusEnRoute,
    IncidentStatus.onScene => statusOnScene,
    IncidentStatus.resolved => statusResolved,
  };

  String incidentType(IncidentType t) => switch (t) {
    IncidentType.flood => typeFlood,
    IncidentType.fire => typeFire,
    IncidentType.medical => typeMedical,
    IncidentType.structural => typeStructural,
  };

  String channel(ReportChannel c) => switch (c) {
    ReportChannel.app => channelApp,
    ReportChannel.sms => channelSms,
    ReportChannel.bleRelay => channelBle,
    ReportChannel.webForm => channelWeb,
  };

  String vulnerability(VulnerabilityType v) => switch (v) {
    VulnerabilityType.seniorCitizen => vulnSenior,
    VulnerabilityType.pwd => vulnPwd,
    VulnerabilityType.pregnant => vulnPregnant,
    VulnerabilityType.other => vulnOther,
  };

  String unitType(UnitType t) => switch (t) {
    UnitType.ambulance => unitAmbulance,
    UnitType.rescueBoat => unitRescueBoat,
    UnitType.rescueTeam => unitRescueTeam,
  };

  String unitStatus(UnitStatus s) => switch (s) {
    UnitStatus.available => unitAvailable,
    UnitStatus.enRoute => unitEnRoute,
    UnitStatus.onScene => unitOnScene,
  };

  String role(UserRole r) => switch (r) {
    UserRole.resident => roleResident,
    UserRole.responder => roleResponder,
    UserRole.dispatcher => roleDispatcher,
    UserRole.admin => roleAdmin,
    UserRole.system => roleSystem,
  };

  String severity(Severity s) => switch (s) {
    Severity.critical => severityCritical,
    Severity.high => severityHigh,
    Severity.normal => severityNormal,
  };

  String verificationMethod(VerificationMethod m) => switch (m) {
    VerificationMethod.callback => methodCallback,
    VerificationMethod.smsReply => methodSmsReply,
    VerificationMethod.onScene => methodOnScene,
  };

  String priorityFactor(PriorityFactorKind k) => switch (k) {
    PriorityFactorKind.sos => factorSos,
    PriorityFactorKind.cluster => factorCluster,
    PriorityFactorKind.vulnerable => factorVulnerable,
    PriorityFactorKind.waiting => factorWaiting,
    PriorityFactorKind.mockLocation => factorMockLocation,
  };

  String incidentEvent(IncidentEventKind k) => switch (k) {
    IncidentEventKind.received => eventReceived,
    IncidentEventKind.smsCheckSent => eventSmsCheckSent,
    IncidentEventKind.smsReplyReceived => eventSmsReply,
    IncidentEventKind.verified => eventVerified,
    IncidentEventKind.typeConfirmed => eventTypeConfirmed,
    IncidentEventKind.assigned => eventAssigned,
    IncidentEventKind.enRoute => eventEnRoute,
    IncidentEventKind.onScene => eventOnScene,
    IncidentEventKind.resolved => eventResolved,
    IncidentEventKind.markedFalseReport => eventFalseReport,
  };

  String auditAction(AuditAction a) => switch (a) {
    AuditAction.verified => actionVerified,
    AuditAction.markedFalseReport => actionFalseReport,
    AuditAction.typeConfirmed => actionTypeConfirmed,
    AuditAction.unitAssigned => actionAssigned,
    AuditAction.unitReassigned => actionReassigned,
    AuditAction.statusChanged => actionStatusChanged,
    AuditAction.resolved => actionResolved,
    AuditAction.smsCheckSent => actionSmsCheck,
    AuditAction.contactViewed => actionContactViewed,
    AuditAction.settingChanged => actionSettingChanged,
    AuditAction.unitAdded => actionUnitAdded,
    AuditAction.unitEdited => actionUnitEdited,
    AuditAction.unitRetired => actionUnitRetired,
    AuditAction.unitRestored => actionUnitRestored,
    AuditAction.rosterChanged => actionRosterChanged,
    AuditAction.accountCreated => actionAccountCreated,
    AuditAction.accountUpdated => actionAccountUpdated,
    AuditAction.accountDeactivated => actionAccountDeactivated,
    AuditAction.accountReactivated => actionAccountReactivated,
    AuditAction.passwordReset => actionPasswordReset,
    AuditAction.residentSuspended => actionResidentSuspended,
    AuditAction.residentRestored => actionResidentRestored,
    AuditAction.weatherSimulated => actionWeatherSimulated,
    AuditAction.alertIssued => actionAlertIssued,
    AuditAction.alertEnded => actionAlertEnded,
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

  String alertLevel(AlertLevel level) => switch (level) {
    AlertLevel.info => levelInfo,
    AlertLevel.warning => levelWarning,
    AlertLevel.critical => levelCritical,
  };

  String alertSource(AlertSource source) => switch (source) {
    AlertSource.pagasa => sourcePagasa,
    AlertSource.phivolcs => sourcePhivolcs,
    AlertSource.efcos => sourceEfcos,
    AlertSource.mdrrmd => sourceMdrrmd,
  };

  String alertChannel(AlertChannel channel) => switch (channel) {
    AlertChannel.app => alertChannelApp,
    AlertChannel.push => alertChannelPush,
    AlertChannel.sms => alertChannelSms,
    AlertChannel.facebook => alertChannelFacebook,
  };

  String deliveryStatus(AlertDeliveryStatus status) => switch (status) {
    AlertDeliveryStatus.queued => deliveryQueued,
    AlertDeliveryStatus.sending => deliverySending,
    AlertDeliveryStatus.sent => deliverySent,
    AlertDeliveryStatus.failed => deliveryFailed,
    AlertDeliveryStatus.off => deliveryOff,
    AlertDeliveryStatus.simulated => deliverySimulated,
    AlertDeliveryStatus.notSetUp => deliveryNotSetUp,
    AlertDeliveryStatus.ended => deliveryEnded,
  };

  String actionRejection(ActionRejection r) => switch (r) {
    ActionRejection.offline => errorOffline,
    ActionRejection.unitNotAvailable => errorUnitTaken,
    ActionRejection.alreadyAssigned => errorAlreadyAssigned,
    ActionRejection.incidentClosed => errorIncidentClosed,
    ActionRejection.notAllowed => errorNotAllowed,
    ActionRejection.invalidValue => errorInvalidValue,
    ActionRejection.notFound => errorNotFound,
    ActionRejection.alreadyExists => errorAlreadyExists,
    ActionRejection.ownAccount => errorOwnAccount,
    ActionRejection.lastAdmin => errorLastAdmin,
  };

  String authFailure(AuthFailure f) => switch (f) {
    AuthFailure.wrongCredentials => signInWrongCredentials,
    AuthFailure.accountDisabled => signInDisabled,
    AuthFailure.notStaff => signInNotStaff,
    AuthFailure.offline => signInOffline,
  };

  /// "SOS, flood", "Flood, 4 reports", or "SOS".
  String incidentTitle(Incident i) {
    final type = i.type == null ? null : incidentType(i.type!);
    if (i.origin == IncidentOrigin.crowdCluster) {
      final count = i.crowdReportIds.length;
      return type == null ? clusterUntyped(count) : clusterTitle(type, count);
    }
    return type == null ? sosTitle : sosWithType(type.toLowerCase());
  }

  /// "40 s ago", "3 min ago", "2 h ago".
  String ago(DateTime then, DateTime now) {
    final d = now.difference(then);
    if (d.inSeconds < 60) return secondsAgo(d.inSeconds.clamp(0, 59));
    if (d.inMinutes < 60) return minutesAgo(d.inMinutes);
    return hoursAgo(d.inHours);
  }
}
