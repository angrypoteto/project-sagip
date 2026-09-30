import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import 'new_sos_toast.dart';
import 'top_bar.dart';

/// The frame around every signed-in page: top bar, navigation rail,
/// connection banner, and the new-SOS toast.
class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  @override
  void initState() {
    super.initState();
    // Demo only: start the live simulation once someone is signed in.
    ref.read(mockBackendProvider)?.startSimulation();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    return Scaffold(
      body: Column(
        children: [
          const TopBar(),
          const _ConnectionBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NavRail(
                  location: widget.location,
                  isAdmin: user?.isAdmin ?? false,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: widget.child),
                      const Positioned(
                        // Below the map's floating controls so it never
                        // covers the Map/List switch.
                        top: 76,
                        left: 0,
                        right: 0,
                        child: Center(child: NewSosToast()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.route, this.icon, this.label);

  final String route;
  final IconData icon;
  final String Function(AppLocalizations) label;
}

final _mainItems = [
  _NavItem(
    Routes.board,
    Symbols.space_dashboard_rounded,
    (l) => l.navCommandBoard,
  ),
  _NavItem(
    Routes.crowdReports,
    Symbols.groups_rounded,
    (l) => l.navCrowdReports,
  ),
  _NavItem(Routes.units, Symbols.ambulance_rounded, (l) => l.navUnits),
  _NavItem(Routes.forecast, Symbols.radar_rounded, (l) => l.navForecast),
  _NavItem(
    Routes.vulnerable,
    Symbols.accessible_rounded,
    (l) => l.navVulnerable,
  ),
  _NavItem(Routes.weather, Symbols.thunderstorm_rounded, (l) => l.navWeather),
];

final _adminItems = [
  _NavItem(Routes.analytics, Symbols.monitoring_rounded, (l) => l.navAnalytics),
  _NavItem(Routes.reports, Symbols.description_rounded, (l) => l.navReports),
  _NavItem(
    Routes.accounts,
    Symbols.manage_accounts_rounded,
    (l) => l.navAccounts,
  ),
  _NavItem(
    Routes.resources,
    Symbols.inventory_2_rounded,
    (l) => l.navResources,
  ),
  _NavItem(Routes.settings, Symbols.tune_rounded, (l) => l.navSettings),
  _NavItem(Routes.auditLog, Symbols.history_rounded, (l) => l.navAuditLog),
];

class _NavRail extends StatelessWidget {
  const _NavRail({required this.location, required this.isAdmin});

  final String location;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: p.canvas,
        border: Border(right: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.md),
      child: Column(
        children: [
          for (final item in _mainItems)
            _RailButton(item: item, location: location),
          // Admin items are hidden, not disabled, for dispatchers.
          if (isAdmin) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SagipSpace.lg,
                vertical: SagipSpace.sm,
              ),
              child: Divider(color: p.hairline),
            ),
            for (final item in _adminItems)
              _RailButton(item: item, location: location),
          ],
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.location});

  final _NavItem item;
  final String location;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final selected = location.startsWith(item.route);
    final label = item.label(AppLocalizations.of(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Material(
            color: selected ? p.info.tint : Colors.transparent,
            borderRadius: BorderRadius.circular(SagipRadius.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(SagipRadius.card),
              onTap: () => context.go(item.route),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  item.icon,
                  size: 20,
                  fill: selected ? 1 : 0,
                  color: selected ? p.info.text : p.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Offline or reconnecting: a slim bar, not an alarm. Actions are disabled
/// elsewhere through [isOnlineProvider].
class _ConnectionBanner extends ConsumerStatefulWidget {
  const _ConnectionBanner();

  @override
  ConsumerState<_ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends ConsumerState<_ConnectionBanner> {
  DateTime _lastLive = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final link = ref.watch(linkStateProvider).value ?? LinkState.live;
    if (link == LinkState.live) {
      _lastLive = DateTime.now();
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context).toString();
    final message = link == LinkState.offline
        ? l10n.offlineBanner(formatClock(_lastLive, locale))
        : l10n.reconnectingBanner;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SagipSpace.xl,
        vertical: SagipSpace.sm,
      ),
      color: p.warning.tint,
      child: Row(
        children: [
          Icon(
            link == LinkState.offline
                ? Symbols.cloud_off_rounded
                : Symbols.sync_rounded,
            size: 18,
            color: p.warning.text,
          ),
          const SizedBox(width: SagipSpace.sm),
          Expanded(
            child: Text(
              message,
              style: text.labelMedium!.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
