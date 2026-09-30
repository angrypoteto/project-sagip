import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'features/auth/demo_sign_in_page.dart';
import 'features/me/me_page.dart';
import 'features/placeholder_page.dart';
import 'features/report/report_page.dart';
import 'features/responder/assignment_page.dart';
import 'features/responder/complete_page.dart';
import 'features/responder/incoming_page.dart';
import 'features/responder/navigate_page.dart';
import 'features/responder/offer_watcher.dart';
import 'features/responder/on_scene_page.dart';
import 'features/responder/responder_home_page.dart';
import 'features/shell/app_shell.dart';
import 'features/sos/home_page.dart';
import 'features/sos/sos_status_page.dart';
import 'features/sos/track_page.dart';
import 'providers.dart';

abstract final class Routes {
  static const signIn = '/sign-in';

  // Resident shell: Home, Report, Alerts, Me (plan 7.3).
  static const home = '/r/home';
  static const report = '/r/report';
  static const alerts = '/r/alerts';
  static const me = '/r/me';
  static String sos(String clientId) => '/r/sos/$clientId';
  static String track(String clientId) => '/r/sos/$clientId/track';

  // Responder shell: Home, History, Me.
  static const duty = '/f/home';
  static const history = '/f/history';
  static const responderMe = '/f/me';

  // Responder full-screen pages (F2 to F6), above the tabs.
  static const incoming = '/f/incoming';
  static const assignment = '/f/assignment';
  static const navigate = '/f/navigate';
  static const onScene = '/f/on-scene';
  static const complete = '/f/complete';
}

Page<void> _page(Widget child) => NoTransitionPage(child: child);

String? _homeFor(AppUser user) => switch (user.role) {
  UserRole.resident => Routes.home,
  UserRole.responder => Routes.duty,
  _ => null,
};

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the signed-in user changes.
  final authChanged = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authChanged,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider).value;
      final path = state.uri.path;
      final atSignIn = path == Routes.signIn;
      if (user == null) return atSignIn ? null : Routes.signIn;

      final home = _homeFor(user);
      // Dispatchers and admins use the web dashboard, not this app.
      if (home == null) return atSignIn ? null : Routes.signIn;
      if (atSignIn || path == '/') return home;
      final resident = user.role == UserRole.resident;
      if (resident && path.startsWith('/f/')) return home;
      if (!resident && path.startsWith('/r/')) return home;
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.signIn),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) => _page(const DemoSignInPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(
          shell: shell,
          destinations: const [
            ShellDestination.home,
            ShellDestination.report,
            ShellDestination.alerts,
            ShellDestination.me,
          ],
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (context, state) => _page(const HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.report,
                pageBuilder: (context, state) => _page(const ReportPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.alerts,
                pageBuilder: (context, state) => _page(
                  const PlaceholderPage(
                    screen: ComingScreen.alerts,
                    icon: Symbols.notifications_rounded,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.me,
                pageBuilder: (context, state) => _page(const MePage()),
              ),
            ],
          ),
        ],
      ),
      // R2 and R3 open full screen, above the tabs.
      GoRoute(
        path: '/r/sos/:id',
        builder: (context, state) =>
            SosStatusPage(clientId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'track',
            builder: (context, state) =>
                TrackPage(clientId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.incoming,
        builder: (context, state) => const IncomingPage(),
      ),
      GoRoute(
        path: Routes.assignment,
        builder: (context, state) => const AssignmentPage(),
      ),
      GoRoute(
        path: Routes.navigate,
        builder: (context, state) => const NavigatePage(),
      ),
      GoRoute(
        path: Routes.onScene,
        builder: (context, state) => const OnScenePage(),
      ),
      GoRoute(
        path: Routes.complete,
        builder: (context, state) => const CompletePage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => OfferWatcher(
          child: AppShell(
            shell: shell,
            destinations: const [
              ShellDestination.duty,
              ShellDestination.history,
              ShellDestination.me,
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.duty,
                pageBuilder: (context, state) =>
                    _page(const ResponderHomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                pageBuilder: (context, state) => _page(
                  const PlaceholderPage(
                    screen: ComingScreen.history,
                    icon: Symbols.history_rounded,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.responderMe,
                pageBuilder: (context, state) => _page(const MePage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
