import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// Slim top bar: brand, PAGASA conditions, connection, clock, and user menu.
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = SagipPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          Text(
            l10n.brandName,
            style: text.titleMedium!.copyWith(letterSpacing: 0.5),
          ),
          const SizedBox(width: SagipSpace.x4),
          const Expanded(child: _WeatherSummary()),
          const _LinkIndicator(),
          const SizedBox(width: SagipSpace.xl),
          const _Clock(),
          const SizedBox(width: SagipSpace.lg),
          const _UserMenu(),
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
        Flexible(
          child: Text(
            l10n.rainfall(weather.rainfallMmPerHour.toStringAsFixed(0)),
            style: text.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: SagipSpace.md),
        Flexible(
          child: Text(
            l10n.pagasaAt(formatTime(weather.issuedAt, locale)),
            style: secondary,
            overflow: TextOverflow.ellipsis,
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
    return Text(
      formatClock(now, Localizations.localeOf(context).toString()),
      style: Theme.of(context).textTheme.titleSmall!
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
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

class _UserMenu extends ConsumerWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider).value;
    final backend = ref.watch(mockBackendProvider);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    if (user == null) return const SizedBox.shrink();

    final initials = user.displayName
        .split(RegExp(r'[\s.]+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join();

    return PopupMenuButton<_MenuAction>(
      tooltip: l10n.userWithRole(user.displayName, l10n.role(user.role)),
      position: PopupMenuPosition.under,
      onSelected: (action) => switch (action) {
        _MenuAction.account => context.go(Routes.account),
        _MenuAction.theme => ref.read(themeModeProvider.notifier).toggle(),
        _MenuAction.offline => backend?.setLink(LinkState.offline),
        _MenuAction.reconnecting => backend?.setLink(LinkState.reconnecting),
        _MenuAction.live => backend?.setLink(LinkState.live),
        _MenuAction.expire => backend?.expireSession(),
        _MenuAction.signOut => ref.read(authRepositoryProvider).signOut(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: _MenuAction.account, child: Text(l10n.myAccount)),
        PopupMenuItem(
          value: _MenuAction.theme,
          child: Text(isDark ? l10n.switchToLight : l10n.switchToDark),
        ),
        if (backend != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, child: Text(l10n.demoConnection)),
          PopupMenuItem(
            value: _MenuAction.offline,
            child: Text(l10n.demoGoOffline),
          ),
          PopupMenuItem(
            value: _MenuAction.reconnecting,
            child: Text(l10n.demoReconnecting),
          ),
          PopupMenuItem(value: _MenuAction.live, child: Text(l10n.demoGoLive)),
          PopupMenuItem(
            value: _MenuAction.expire,
            child: Text(l10n.demoExpireSession),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(value: _MenuAction.signOut, child: Text(l10n.signOut)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SagipSpace.sm),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: p.panelRaised,
              child: Text(
                initials,
                style: text.labelSmall!.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: SagipSpace.sm),
            Text(
              l10n.userWithRole(user.displayName, l10n.role(user.role)),
              style: text.labelMedium!.copyWith(color: p.textSecondary),
            ),
            Icon(Symbols.expand_more_rounded, size: 18, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}
