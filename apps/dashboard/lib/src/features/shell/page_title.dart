import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// The browser tab names the page that is open, for example
/// "S.A.G.I.P. Command Center - Command Board" (Joshua, 2026-10-16).
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.path, required this.child});

  /// The open page's path, for example `/board`.
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final page = pageName(path, l10n);
    return Title(
      title: page == null
          ? l10n.appTitle
          : l10n.pageTabTitle(l10n.appTitle, page),
      color: Theme.of(context).colorScheme.primary,
      child: child,
    );
  }
}

/// The name of the page at [path], as the menu shows it; null for none.
String? pageName(String path, AppLocalizations l10n) {
  bool at(String route) => path == route || path.startsWith('$route/');
  if (at(Routes.board)) return l10n.navCommandBoard;
  if (at(Routes.wall)) return l10n.pageWallMap;
  if (at(Routes.myUnit)) return l10n.myUnitTitle;
  if (at(Routes.account)) return l10n.myAccount;
  if (at(Routes.crowdReports)) return l10n.navCrowdReports;
  if (at(Routes.units)) return l10n.navUnits;
  if (at(Routes.forecast)) return l10n.navForecast;
  if (at(Routes.vulnerable)) return l10n.navVulnerable;
  if (at(Routes.weather)) return l10n.navWeather;
  if (at(Routes.analytics)) return l10n.navAnalytics;
  if (at(Routes.reports)) return l10n.navReports;
  if (at(Routes.accounts)) return l10n.navAccounts;
  if (at(Routes.resources)) return l10n.navResources;
  if (at(Routes.settings)) return l10n.navSettings;
  if (at(Routes.auditLog)) return l10n.navAuditLog;
  if (at(Routes.signIn) || at(Routes.sessionExpired)) return l10n.signInButton;
  return null;
}
