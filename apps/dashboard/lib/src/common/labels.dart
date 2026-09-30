import 'package:intl/intl.dart';
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
  };

  String actionRejection(ActionRejection r) => switch (r) {
    ActionRejection.offline => errorOffline,
    ActionRejection.unitNotAvailable => errorUnitTaken,
    ActionRejection.alreadyAssigned => errorAlreadyAssigned,
    ActionRejection.incidentClosed => errorIncidentClosed,
    ActionRejection.notAllowed => errorNotAllowed,
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

/// Wait timers: "04:12", or "1:04:12" past an hour. Tabular in the UI.
String formatWait(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// intl puts a narrow no-break space (U+202F) before AM/PM, which Plus Jakarta
// Sans does not draw ("7:44:12AM"). Use an ordinary no-break space instead.
String _spaced(String s) => s.replaceAll(' ', ' ');

String formatClock(DateTime t, String locale) =>
    _spaced(DateFormat.jms(locale).format(t));

String formatTime(DateTime t, String locale) =>
    _spaced(DateFormat.jm(locale).format(t));

String formatDateTime(DateTime t, String locale) =>
    _spaced(DateFormat.yMMMd(locale).add_jm().format(t));

String formatCoordinates(GeoPoint p) =>
    '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}';
