import 'package:sagip_shared/sagip_shared.dart';

import '../../router.dart';

/// Where a tapped notification takes the person (plan part 7).
///
/// - An alert opens it (R8). Responders have no alert pages; they land on
///   their home screen.
/// - A rescue confirmation opens that SOS (R2), or the Alerts tab where the
///   confirmation is listed when the SOS is not on this phone.
/// - A new assignment opens the responder's home, which shows the offer
///   and its full-screen alert (F1, F2).
///
/// [push] is true for a page that opens above the tabs (Back returns).
({String location, bool push}) pushDestination(
  PushOpen open,
  AppUser user,
  List<SosRequest> mySos,
) {
  final resident = user.role == UserRole.resident;
  final home = resident ? Routes.home : Routes.duty;
  switch (open.kind) {
    case PushKind.alert:
      return resident
          ? (location: Routes.alert(open.alertId!), push: true)
          : (location: home, push: false);
    case PushKind.rescue:
      if (!resident) return (location: home, push: false);
      for (final s in mySos) {
        if (s.incidentId == open.incidentId) {
          return (location: Routes.sos(s.clientId), push: true);
        }
      }
      return (location: Routes.alerts, push: false);
    case PushKind.assignment:
      return (location: home, push: false);
  }
}
