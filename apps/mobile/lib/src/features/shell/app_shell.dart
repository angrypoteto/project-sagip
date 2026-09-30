import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';

/// Bottom-bar destinations. Residents get Home, Report, Alerts, Me;
/// responders get Home, History, Me (plan 7.3).
enum ShellDestination { home, report, alerts, me, duty, history }

/// The tab shell: the offline banner on top of every tab, then the page,
/// then the bottom bar. Android Back on another tab returns to Home first
/// instead of closing the app.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.destinations});

  final StatefulNavigationShell shell;
  final List<ShellDestination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final onHome = shell.currentIndex == 0;
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: shell),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(_icon(d)),
                selectedIcon: Icon(_icon(d), fill: 1),
                label: _label(l10n, d),
              ),
          ],
        ),
      ),
    );
  }

  IconData _icon(ShellDestination d) => switch (d) {
    ShellDestination.home || ShellDestination.duty => Symbols.home_rounded,
    ShellDestination.report => Symbols.report_rounded,
    ShellDestination.alerts => Symbols.notifications_rounded,
    ShellDestination.me => Symbols.person_rounded,
    ShellDestination.history => Symbols.history_rounded,
  };

  String _label(AppLocalizations l10n, ShellDestination d) => switch (d) {
    ShellDestination.home || ShellDestination.duty => l10n.navHome,
    ShellDestination.report => l10n.navReport,
    ShellDestination.alerts => l10n.navAlerts,
    ShellDestination.me => l10n.navMe,
    ShellDestination.history => l10n.navHistory,
  };
}
