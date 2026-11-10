import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// The top bar: PAGASA's conditions; on the right
/// the board at a glance (waiting, responding, units free), the connection,
/// and the date and time. The mark, the name, and the account are in the
/// side menu (Joshua, 2026-11-10: the bar "feels empty").
class TopBar extends ConsumerWidget {
  const TopBar({super.key, this.showTallies = true});

  /// The board's counts; not for a unit's crew.
  final bool showTallies;

  // As tall as the side menu's head, so the two line up (Joshua,
  // 2026-11-10: "do the same with headings").
  static const double height = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = SagipPalette.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          const Expanded(child: _WeatherSummary()),
          if (showTallies) ...[
            const _Tallies(),
            const SizedBox(width: SagipSpace.xl),
          ],
          const _LinkIndicator(),
          const SizedBox(width: SagipSpace.xl),
          const _Clock(),
        ],
      ),
    );
  }
}

class _WeatherSummary extends ConsumerWidget {
  const _WeatherSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final weather = ref.watch(weatherProvider).value;
    if (weather == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final secondary = text.labelMedium!.copyWith(color: p.textSecondary);
    return Row(
      children: [
        SagipChip(
          label: weather.signalLevel > 0
              ? l10n.signalLevel(weather.signalLevel)
              : l10n.noSignal,
          tone: weather.signalLevel > 0 ? p.warning : p.neutral,
          icon: Symbols.cyclone_rounded,
          dense: false,
        ),
        const SizedBox(width: SagipSpace.md),
        // Where the reading comes from and when is in the tooltip: the bar
        // keeps to what a dispatcher reads at a glance.
        Flexible(
          child: Tooltip(
            message: l10n.pagasaAt(formatTime(weather.issuedAt, locale)),
            child: Text(
              _rainfallLine(l10n, weather.rainfallMmPerHour),
              style: secondary,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (weather.isSimulated) ...[
          const SizedBox(width: SagipSpace.md),
          Flexible(
            child: SagipChip(label: l10n.simulatedFeed, tone: p.neutral),
          ),
        ],
      ],
    );
  }
}

class _LinkIndicator extends ConsumerWidget {
  const _LinkIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final link = ref.watch(linkStateProvider).value ?? LinkState.live;
    final (color, label) = switch (link) {
      LinkState.live => (p.success.fill, l10n.linkLive),
      LinkState.reconnecting => (p.warning.fill, l10n.linkReconnecting),
      LinkState.offline => (p.critical.fill, l10n.linkOffline),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: SagipSpace.sm),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _Clock extends ConsumerWidget {
  const _Clock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatClock(now, locale),
          style: text.titleSmall!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.2,
          ),
        ),
        Text(
          formatDate(now, locale),
          style: text.labelSmall!.copyWith(
            color: SagipPalette.of(context).textSecondary,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The board at a glance, on every page: what waits for a unit, what is
/// being responded to, and how many units are free. Each opens its page.
class _Tallies extends ConsumerWidget {
  const _Tallies();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final incidents = ref.watch(activeIncidentsProvider).value;
    final units = ref.watch(unitsProvider).value;
    if (incidents == null || units == null) return const SizedBox.shrink();
    final waiting = incidents
        .where(
          (i) =>
              i.status == IncidentStatus.pendingVerification ||
              i.status == IncidentStatus.confirmed,
        )
        .length;
    final responding = incidents
        .where(
          (i) =>
              i.status == IncidentStatus.assigned ||
              i.status == IncidentStatus.enRoute ||
              i.status == IncidentStatus.onScene,
        )
        .length;
    final free = units.where((u) => u.status == UnitStatus.available).length;
    Widget tally(
      String key,
      String label,
      String tip,
      SagipTone tone,
      IconData icon,
      String route,
    ) => Tooltip(
      message: tip,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(SagipRadius.chip),
        onTap: () => context.go(route),
        child: SagipChip(label: label, tone: tone, icon: icon, dense: false),
      ),
    );
    return Row(
      children: [
        tally(
          'tally-waiting',
          l10n.barWaiting(waiting),
          l10n.barWaitingTip,
          waiting > 0 ? p.warning : p.neutral,
          Symbols.hourglass_top_rounded,
          Routes.board,
        ),
        const SizedBox(width: SagipSpace.sm),
        tally(
          'tally-responding',
          l10n.barResponding(responding),
          l10n.barRespondingTip,
          responding > 0 ? p.info : p.neutral,
          Symbols.emergency_rounded,
          Routes.board,
        ),
        const SizedBox(width: SagipSpace.sm),
        tally(
          'tally-units',
          l10n.barUnitsFree(free, units.length),
          l10n.barUnitsFreeTip,
          free > 0 ? p.success : p.critical,
          Symbols.ambulance_rounded,
          Routes.units,
        ),
      ],
    );
  }
}

enum _MenuAction {
  account,
  theme,
  offline,
  reconnecting,
  live,
  expire,
  signOut,
}

/// The account, at the foot of the side menu: who is signed in, My account,
/// the theme, and sign out. The circle, and beside it the name and role
/// while the side menu is [open] (Joshua, 2026-11-10).
class UserMenu extends ConsumerWidget {
  const UserMenu({super.key, this.open = false});

  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider).value;
    final backend = ref.watch(mockBackendProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final hold = ref.read(navMenuHeldProvider.notifier);
    if (user == null) return const SizedBox.shrink();

    final initials = user.displayName
        .split(RegExp(r'[\s.]+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join();

    // The circle, in a 44 px target; the name and role are in the menu and
    // the tooltip.
    final avatar = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: CircleAvatar(
          radius: 16,
          backgroundColor: p.panelRaised,
          child: Text(
            initials,
            style: text.labelSmall!.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    return PopupMenuButton<_MenuAction>(
      tooltip: l10n.userWithRole(user.displayName, l10n.role(user.role)),
      // From the foot of the side menu it opens over the button, upward.
      position: PopupMenuPosition.over,
      // From the side menu, the side menu stays open while this is showing,
      // and closes only after this has.
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 200),
        reverseDuration: accountMenuClose,
      ),
      onOpened: hold.hold,
      onCanceled: () => hold.release(accountMenuClose),
      onSelected: (action) {
        hold.release(accountMenuClose);
        switch (action) {
          case _MenuAction.account:
            context.go(Routes.account);
          case _MenuAction.theme:
            ref.read(themeModeProvider.notifier).toggle();
          case _MenuAction.offline:
            backend?.setLink(LinkState.offline);
          case _MenuAction.reconnecting:
            backend?.setLink(LinkState.reconnecting);
          case _MenuAction.live:
            backend?.setLink(LinkState.live);
          case _MenuAction.expire:
            backend?.expireSession();
          case _MenuAction.signOut:
            ref.read(authRepositoryProvider).signOut();
        }
      },
      // Compact and a little wider than its longest line, each line with
      // its icon (Joshua, 2026-11-10: "it feels elongated").
      constraints: const BoxConstraints(minWidth: 248, maxWidth: 280),
      menuPadding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.hairline),
      ),
      itemBuilder: (context) => [
        // Who is signed in: the circle, the name, and the role.
        PopupMenuItem(
          enabled: false,
          height: 56,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: p.panelRaised,
                child: Text(
                  initials,
                  style: text.labelSmall!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: SagipSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall!.copyWith(color: p.textPrimary),
                    ),
                    Text(
                      l10n.role(user.role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 9),
        _item(
          context,
          _MenuAction.account,
          Symbols.person_rounded,
          l10n.myAccount,
        ),
        _item(
          context,
          _MenuAction.theme,
          isDark ? Symbols.light_mode_rounded : Symbols.dark_mode_rounded,
          isDark ? l10n.switchToLight : l10n.switchToDark,
        ),
        if (backend != null) ...[
          const PopupMenuDivider(height: 9),
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              l10n.demoConnection,
              style: text.labelSmall!.copyWith(color: p.textSecondary),
            ),
          ),
          _item(
            context,
            _MenuAction.offline,
            Symbols.cloud_off_rounded,
            l10n.demoGoOffline,
          ),
          _item(
            context,
            _MenuAction.reconnecting,
            Symbols.sync_rounded,
            l10n.demoReconnecting,
          ),
          _item(
            context,
            _MenuAction.live,
            Symbols.wifi_rounded,
            l10n.demoGoLive,
          ),
          _item(
            context,
            _MenuAction.expire,
            Symbols.timer_off_rounded,
            l10n.demoExpireSession,
          ),
        ],
        const PopupMenuDivider(height: 9),
        _item(
          context,
          _MenuAction.signOut,
          Symbols.logout_rounded,
          l10n.signOut,
        ),
      ],
      child: _sideMenuFace(context, user, avatar),
    );
  }

  /// One line of the menu: its icon, then its name.
  PopupMenuItem<_MenuAction> _item(
    BuildContext context,
    _MenuAction value,
    IconData icon,
    String label,
  ) {
    final p = SagipPalette.of(context);
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.textSecondary),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  /// The circle in the side menu's icon column, the name and role beside it.
  Widget _sideMenuFace(BuildContext context, AppUser user, Widget avatar) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 10),
          avatar,
          if (open) ...[
            const SizedBox(width: SagipSpace.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    l10n.role(user.role),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall!.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SagipSpace.lg),
          ],
        ],
      ),
    );
  }
}

/// PAGASA's rainfall reading is its warning level, not a rain gauge
/// (ingest-pagasa: yellow 7.5, orange 15, red 30 mm/hr), so 0 means "no
/// warning", not "no rain" (Joshua, 2026-11-10). Other values come from
/// simulation mode and are shown as they are.
String _rainfallLine(AppLocalizations l10n, double mm) => switch (mm) {
  0 => l10n.rainfallNoWarning,
  30 => l10n.rainfallWarning(l10n.rainRed),
  15 => l10n.rainfallWarning(l10n.rainOrange),
  7.5 => l10n.rainfallWarning(l10n.rainYellow),
  _ => l10n.rainfall(mm.toStringAsFixed(mm % 1 == 0 ? 0 : 1)),
};
