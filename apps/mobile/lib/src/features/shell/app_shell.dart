import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

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
    final p = SagipPalette.of(context);
    // New alerts show as a count on the Alerts tab, in tide, not red: an
    // unread alert is not an emergency on its own.
    final unread = destinations.contains(ShellDestination.alerts)
        ? ref.watch(alertFeedProvider).value?.unread ?? 0
        : 0;
    Widget icon(ShellDestination d, {bool selected = false}) {
      final base = Icon(_icon(d), fill: selected ? 1 : 0);
      if (d != ShellDestination.alerts || unread == 0) return base;
      return Badge(
        label: Text('$unread'),
        backgroundColor: p.info.fill,
        textColor: SagipColors.porcelain,
        child: Semantics(label: l10n.unreadAlerts(unread), child: base),
      );
    }

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
                icon: icon(d),
                selectedIcon: icon(d, selected: true),
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
