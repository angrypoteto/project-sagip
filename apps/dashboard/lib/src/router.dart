import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'features/account/account_page.dart';
import 'features/admin/accounts_page.dart';
import 'features/admin/analytics_page.dart';
import 'features/admin/audit_log_page.dart';
import 'features/admin/configuration_page.dart';
import 'features/admin/resources_page.dart';
import 'features/auth/session_expired_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/board/board_page.dart';
import 'features/crowd_reports/crowd_reports_page.dart';
import 'features/placeholder_page.dart';
import 'features/shell/dashboard_shell.dart';
import 'features/shell/not_found_page.dart';
import 'features/units/units_page.dart';
import 'features/vulnerable/vulnerable_page.dart';
import 'features/weather/weather_page.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const sessionExpired = '/session-expired';
  static const account = '/account';
  static const board = '/board';
  static const crowdReports = '/crowd-reports';
  static const units = '/units';
  static const forecast = '/forecast';
  static const vulnerable = '/vulnerable';
  static const weather = '/weather';
  static const analytics = '/admin/analytics';
  static const reports = '/admin/reports';
  static const accounts = '/admin/accounts';
  static const resources = '/admin/resources';
  static const settings = '/admin/settings';
  static const auditLog = '/admin/audit-log';
  static const notFound = '/not-found';

  /// The board with an incident open, optionally in list view.
  static String incident(String id, {bool list = false}) => Uri(
    path: board,
    queryParameters: {'incident': id, if (list) 'view': 'list'},
  ).toString();
}

Page<void> _page(Widget child) => NoTransitionPage(child: child);

/// "Leave without saving?" Stay is the safe answer and what closing the
/// dialog means.
Future<bool> confirmLeaveUnsaved(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.unsavedTitle),
      content: Text(l10n.unsavedBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.unsavedStay),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.unsavedLeave),
        ),
      ],
    ),
  );
  return leave ?? false;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the signed-in user changes.
  final authChanged = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (_, next) {
    if (next.value != null) {
      ref.read(sessionExpiredProvider.notifier).set(false);
    }
    authChanged.value++;
  });
  ref.listen(sessionExpiredEventsProvider, (_, next) {
    if (next.hasValue) ref.read(sessionExpiredProvider.notifier).set(true);
  });
  ref.listen(sessionExpiredProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  final router = GoRouter(
    initialLocation: Routes.board,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider).value;
      final path = state.uri.path;
      final atSignIn = path == Routes.signIn;

      final atExpired = path == Routes.sessionExpired;
      if (user == null) {
        // G2: say the session expired, then return to the same page.
        if (ref.read(sessionExpiredProvider) && !atExpired) {
          return Uri(
            path: Routes.sessionExpired,
            queryParameters: {
              'from': atSignIn
                  ? (state.uri.queryParameters['from'] ?? Routes.board)
                  : state.uri.toString(),
            },
          ).toString();
        }
        if (atSignIn || atExpired) return null;
        return Uri(
          path: Routes.signIn,
          queryParameters: {'from': state.uri.toString()},
        ).toString();
      }
      if (atExpired) return Routes.board;
      if (!user.canDispatch) return atSignIn ? null : Routes.signIn;
      if (atSignIn) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/')) ? from : Routes.board;
      }
      // Admin pages are hidden, not disabled, for dispatchers.
      if (path.startsWith('/admin') && !user.isAdmin) return Routes.notFound;
      return null;
    },
    errorPageBuilder: (context, state) => _page(const NotFoundPage()),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.board),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) => _page(const SignInPage()),
      ),
      GoRoute(
        path: Routes.sessionExpired,
        pageBuilder: (context, state) =>
            _page(SessionExpiredPage(from: state.uri.queryParameters['from'])),
      ),
      ShellRoute(
        pageBuilder: (context, state, child) =>
            _page(DashboardShell(location: state.uri.path, child: child)),
        routes: [
          GoRoute(
            path: Routes.board,
            pageBuilder: (context, state) => _page(
              BoardPage(
                selectedId: state.uri.queryParameters['incident'],
                listView: state.uri.queryParameters['view'] == 'list',
              ),
            ),
          ),
          GoRoute(
            path: Routes.account,
            pageBuilder: (context, state) => _page(const AccountPage()),
          ),
          GoRoute(
            path: Routes.crowdReports,
            pageBuilder: (context, state) => _page(const CrowdReportsPage()),
          ),
          GoRoute(
            path: Routes.units,
            pageBuilder: (context, state) => _page(const UnitsPage()),
          ),
          GoRoute(
            path: Routes.forecast,
            pageBuilder: (context, state) =>
                _page(const PlaceholderPage(kind: PlaceholderKind.forecast)),
          ),
          GoRoute(
            path: Routes.vulnerable,
            pageBuilder: (context, state) => _page(const VulnerablePage()),
          ),
          GoRoute(
            path: Routes.weather,
            pageBuilder: (context, state) => _page(const WeatherPage()),
          ),
          GoRoute(
            path: Routes.analytics,
            pageBuilder: (context, state) => _page(const AnalyticsPage()),
          ),
          GoRoute(
            path: Routes.reports,
            pageBuilder: (context, state) =>
                _page(const PlaceholderPage(kind: PlaceholderKind.reports)),
          ),
          GoRoute(
            path: Routes.accounts,
            pageBuilder: (context, state) => _page(const AccountsPage()),
          ),
          GoRoute(
            path: Routes.resources,
            pageBuilder: (context, state) => _page(const ResourcesPage()),
          ),
          GoRoute(
            path: Routes.settings,
            // A3 guards against leaving with unsaved changes (plan 7.4).
            onExit: (context, state) async {
              final unsaved = ref.read(unsavedChangesProvider);
              if (!unsaved.any) return true;
              final leave = await confirmLeaveUnsaved(context);
              if (leave) unsaved.clear();
              return leave;
            },
            pageBuilder: (context, state) => _page(const ConfigurationPage()),
          ),
          GoRoute(
            path: Routes.auditLog,
            pageBuilder: (context, state) => _page(const AuditLogPage()),
          ),
          GoRoute(
            path: Routes.notFound,
            pageBuilder: (context, state) => _page(const NotFoundPage()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
