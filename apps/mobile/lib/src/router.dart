import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'features/activity/activity_page.dart';
import 'features/alerts/alert_detail_page.dart';
import 'features/alerts/alerts_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/auth/splash_page.dart';
import 'features/auth/staff_sign_in_page.dart';
import 'features/auth/verify_page.dart';
import 'features/auth/welcome_page.dart';
import 'features/me/me_page.dart';
import 'features/report/location_picker_page.dart';
import 'features/report/report_page.dart';
import 'features/responder/assignment_page.dart';
import 'features/responder/complete_page.dart';
import 'features/responder/history_page.dart';
import 'features/responder/incoming_page.dart';
import 'features/responder/navigate_page.dart';
import 'features/responder/offer_watcher.dart';
import 'features/responder/on_scene_page.dart';
import 'features/responder/responder_home_page.dart';
import 'features/shell/app_shell.dart';
import 'features/sos/home_page.dart';
import 'features/sos/sos_status_page.dart';
import 'features/sos/track_page.dart';
import 'features/vulnerability/consent_page.dart';
import 'features/vulnerability/member_page.dart';
import 'features/vulnerability/vulnerability_page.dart';
import 'providers.dart';

abstract final class Routes {
  // Signed out (S1 to S5).
  static const splash = '/';
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const staffSignIn = '/sign-in/staff';
  static const register = '/register';
  static const verify = '/verify';
  static String verifyFor(String phone) =>
      Uri(path: verify, queryParameters: {'phone': phone}).toString();

  /// Pages anyone may open without signing in.
  static const public = {welcome, signIn, staffSignIn, register, verify};

  // Resident shell: Home, Report, Alerts, Me (plan 7.3).
  static const home = '/r/home';
  static const report = '/r/report';
  static const alerts = '/r/alerts';
  static const me = '/r/me';
  static String sos(String clientId) => '/r/sos/$clientId';
  static String track(String clientId) => '/r/sos/$clientId/track';
  static String alert(String id) => '/r/alert/$id';
  static const pickLocation = '/r/location';
  static const activity = '/r/activity';
  static const vulnerability = '/r/vulnerability';
  static const consent = '/r/vulnerability/consent';
  static const memberNew = '/r/vulnerability/member';
  static String member(String id) => '/r/vulnerability/member/$id';

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
      final session = ref.read(currentUserProvider);
      final path = state.uri.path;
      // S1 stays up while the saved session is checked.
      if (session.isLoading && !session.hasValue) {
        return path == Routes.splash ? null : Routes.splash;
      }
      final user = session.value;
      final public = Routes.public.contains(path);
      if (user == null) {
        if (public) return null;
        return ref.read(welcomeSeenProvider) ? Routes.signIn : Routes.welcome;
      }

      final home = _homeFor(user);
      // Dispatchers and admins use the web dashboard, not this app.
      if (home == null) return path == Routes.signIn ? null : Routes.signIn;
      if (public || path == Routes.splash) return home;
      final resident = user.role == UserRole.resident;
      if (resident && path.startsWith('/f/')) return home;
      if (!resident && path.startsWith('/r/')) return home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (context, state) => _page(const SplashPage()),
      ),
      GoRoute(
        path: Routes.welcome,
        pageBuilder: (context, state) => _page(const WelcomePage()),
      ),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) => _page(const SignInPage()),
      ),
      GoRoute(
        path: Routes.staffSignIn,
        builder: (context, state) => const StaffSignInPage(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: Routes.verify,
        builder: (context, state) =>
            VerifyPage(phone: state.uri.queryParameters['phone'] ?? ''),
      ),
      // Resident pages that open full screen, above the tabs (R5, R6, R8
      // to R11).
      GoRoute(
        path: Routes.pickLocation,
        builder: (context, state) =>
            LocationPickerPage(initial: state.extra as GeoPoint?),
      ),
      GoRoute(
        path: Routes.activity,
        builder: (context, state) => const ActivityPage(),
      ),
      GoRoute(
        path: '/r/alert/:id',
        builder: (context, state) =>
            AlertDetailPage(alertId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.vulnerability,
        builder: (context, state) => const VulnerabilityPage(),
        routes: [
          GoRoute(
            path: 'consent',
            builder: (context, state) => const ConsentPage(),
          ),
          GoRoute(
            path: 'member',
            builder: (context, state) => const MemberPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    MemberPage(memberId: state.pathParameters['id']),
              ),
            ],
          ),
        ],
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
                pageBuilder: (context, state) => _page(const AlertsPage()),
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
                pageBuilder: (context, state) => _page(const HistoryPage()),
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
