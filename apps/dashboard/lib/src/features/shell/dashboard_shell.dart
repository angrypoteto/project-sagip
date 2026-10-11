import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

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
            child: _NavFrame(
              location: widget.location,
              isAdmin: user?.isAdmin ?? false,
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

/// The navigation menu beside the page. Closed, it is a rail of icons.
/// Pointing at it opens it over the page, with the names beside the icons,
/// and it closes again when the pointer leaves. The menu button at the top
/// keeps it open (the page then makes room for it) until pressed again.
class _NavFrame extends StatefulWidget {
  const _NavFrame({
    required this.location,
    required this.isAdmin,
    required this.child,
  });

  final String location;
  final bool isAdmin;
  final Widget child;

  static const double closedWidth = 64;
  static const double openWidth = 248;
  static const _slide = Duration(milliseconds: 160);

  @override
  State<_NavFrame> createState() => _NavFrameState();
}

class _NavFrameState extends State<_NavFrame> {
  /// Kept open with the menu button.
  var _pinned = false;

  /// The pointer is over the menu.
  var _hovered = false;

  bool get _open => _pinned || _hovered;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final open = _open;
    final width = open ? _NavFrame.openWidth : _NavFrame.closedWidth;
    return Stack(
      children: [
        // The page: beside the rail, or beside the whole menu when it is
        // kept open. A menu opened by pointing lies over the page instead,
        // so nothing jumps while the pointer passes.
        AnimatedPadding(
          duration: _NavFrame._slide,
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: _pinned ? _NavFrame.openWidth : _NavFrame.closedWidth,
          ),
          child: widget.child,
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              key: const ValueKey('nav-menu'),
              duration: _NavFrame._slide,
              curve: Curves.easeOut,
              width: width,
              decoration: BoxDecoration(
                color: p.canvas,
                border: Border(right: BorderSide(color: p.hairline)),
                boxShadow: [
                  if (open && !_pinned)
                    const BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 24,
                      offset: Offset(8, 0),
                    ),
                ],
              ),
              // Laid out at its final width and clipped while it slides, so
              // the names never wrap or overflow on the way.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: width,
                  maxWidth: width,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: SagipSpace.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RailRow(
                          key: const ValueKey('nav-menu-button'),
                          icon: _pinned
                              ? Symbols.menu_open_rounded
                              : Symbols.menu_rounded,
                          label: _pinned ? l10n.navMenuClose : l10n.navMenuKeep,
                          selected: false,
                          open: open,
                          onTap: () => setState(() => _pinned = !_pinned),
                        ),
                        for (final item in _mainItems)
                          _RailRow.item(item, widget.location, open, context),
                        // Admin items are hidden, not disabled, for
                        // dispatchers.
                        if (widget.isAdmin) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SagipSpace.lg,
                              vertical: SagipSpace.sm,
                            ),
                            child: Divider(color: p.hairline),
                          ),
                          for (final item in _adminItems)
                            _RailRow.item(item, widget.location, open, context),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of the menu: the icon, and its name while the menu is open.
/// Closed, the name is the tooltip.
class _RailRow extends StatelessWidget {
  const _RailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.open,
    required this.onTap,
  });

  factory _RailRow.item(
    _NavItem item,
    String location,
    bool open,
    BuildContext context,
  ) => _RailRow(
    icon: item.icon,
    label: item.label(AppLocalizations.of(context)),
    selected: location.startsWith(item.route),
    open: open,
    onTap: () => context.go(item.route),
  );

  final IconData icon;
  final String label;
  final bool selected;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final row = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? p.info.tint : Colors.transparent,
        borderRadius: BorderRadius.circular(SagipRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(SagipRadius.card),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisSize: open ? MainAxisSize.max : MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  child: Icon(
                    icon,
                    size: 20,
                    fill: selected ? 1 : 0,
                    color: selected ? p.info.text : p.textSecondary,
                  ),
                ),
                if (open)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: SagipSpace.md),
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge!.copyWith(
                            color: selected ? p.info.text : p.textPrimary,
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: SagipSpace.xs,
      ),
      child: open
          ? row
          : Tooltip(message: label, preferBelow: false, child: row),
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
