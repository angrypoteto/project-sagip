import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'web_providers.dart';
import 'web_report_page.dart';
import 'web_reports_page.dart';
import 'web_sign_in_page.dart';

abstract final class WebRoutes {
  /// Shown while the saved session is checked.
  static const start = '/';
  static const signIn = '/sign-in';
  static const report = '/report';
  static const reports = '/reports';

  /// W3 with the confirmation for the report just sent.
  static String received(String id) =>
      Uri(path: reports, queryParameters: {'sent': id}).toString();
}

Page<void> _page(Widget child) => NoTransitionPage(child: child);

final webRouterProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the signed-in resident changes.
  final authChanged = ValueNotifier<int>(0);
  ref.listen(webUserProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);

  final router = GoRouter(
    initialLocation: WebRoutes.start,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final user = ref.read(webUserProvider);
      final path = state.uri.path;
      if (user.isLoading && !user.hasValue) {
        return path == WebRoutes.start ? null : WebRoutes.start;
      }
      // Only residents use the web form; anyone else signs in again.
      if (user.value?.role != UserRole.resident) {
        return path == WebRoutes.signIn ? null : WebRoutes.signIn;
      }
      if (path == WebRoutes.start || path == WebRoutes.signIn) {
        return WebRoutes.report;
      }
      return null;
    },
    errorPageBuilder: (context, state) => _page(const _Starting()),
    routes: [
      GoRoute(
        path: WebRoutes.start,
        pageBuilder: (context, state) => _page(const _Starting()),
      ),
      GoRoute(
        path: WebRoutes.signIn,
        pageBuilder: (context, state) => _page(const WebSignInPage()),
      ),
      GoRoute(
        path: WebRoutes.report,
        pageBuilder: (context, state) => _page(const WebReportPage()),
      ),
      GoRoute(
        path: WebRoutes.reports,
        pageBuilder: (context, state) =>
            _page(WebReportsPage(sentId: state.uri.queryParameters['sent'])),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The brand mark while the saved session loads.
class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: SagipMark(size: 72)));
}
