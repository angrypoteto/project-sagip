import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

enum _Tab { alerts, forecast }

/// R7 Alerts and forecast. Shows the phone's last copy when offline, with
/// the time it was received. Pull down to check for new alerts.
class AlertsPage extends ConsumerStatefulWidget {
  const AlertsPage({super.key});

  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage> {
  var _tab = _Tab.alerts;

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(alertRepositoryProvider).refresh();
    } on ActionRejected {
      messenger.showSnackBar(SnackBar(content: Text(l10n.phoneOffline)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.alertsError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final feed = ref.watch(alertFeedProvider);
    final online =
        (ref.watch(signalProvider).value ?? SignalState.internet) ==
        SignalState.internet;
    final saved = feed.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            SagipSpace.xl,
            SagipSpace.xl,
            SagipSpace.md,
          ),
          child: Text(l10n.alertsTitle, style: text.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
          child: SegmentedButton<_Tab>(
            segments: [
              ButtonSegment(
                value: _Tab.alerts,
                label: Text(l10n.alertsTabAlerts),
              ),
              ButtonSegment(
                value: _Tab.forecast,
                label: Text(l10n.alertsTabForecast),
              ),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.single),
          ),
        ),
        if (!online && saved != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SagipSpace.xl,
              SagipSpace.md,
              SagipSpace.xl,
              0,
            ),
            child: Text(
              l10n.alertsOffline(formatTime(saved.updatedAt, locale)),
              style: text.bodySmall!.copyWith(color: p.warning.text),
            ),
          ),
        const SizedBox(height: SagipSpace.sm),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: saved == null
                ? _Scrollable(
                    child: feed.hasError
                        ? ErrorState(message: l10n.alertsError)
                        : const SkeletonList(rows: 3, rowHeight: 96),
                  )
                : switch (_tab) {
                    _Tab.alerts => _AlertList(feed: saved),
                    _Tab.forecast => _ForecastView(feed: saved),
                  },
          ),
        ),
      ],
    );
  }
}

/// Lets pull to refresh work on the loading, error, and empty states too.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: box.maxHeight, child: child)],
    ),
  );
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.feed});

  final AlertFeed feed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (feed.alerts.isEmpty) {
      return _Scrollable(
        child: EmptyState(
          icon: Symbols.notifications_off_rounded,
          title: l10n.alertsEmpty,
        ),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        SagipSpace.sm,
        SagipSpace.xl,
        SagipSpace.x3,
      ),
      itemCount: feed.alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: SagipSpace.md),
      itemBuilder: (context, i) => AlertCard(alert: feed.alerts[i]),
    );
  }
}

/// Icon and tone for an alert level: always icon, color, and label.
StatusVisual alertLevelVisual(AlertLevel level, SagipPalette p) =>
    switch (level) {
      AlertLevel.info => StatusVisual(p.info, Symbols.info_rounded),
      AlertLevel.warning => StatusVisual(p.warning, Symbols.warning_rounded),
      AlertLevel.critical => StatusVisual(
        p.critical,
        Symbols.emergency_home_rounded,
      ),
    };

/// "25 min ago" for today's alerts, the date and time for older ones.
String alertTime(
  AppLocalizations l10n,
  DateTime at,
  DateTime now,
  String locale,
) => now.difference(at) < const Duration(hours: 12)
    ? l10n.ago(at, now)
    : formatDateTime(at, locale);

class AlertCard extends ConsumerWidget {
  const AlertCard({super.key, required this.alert});

  final PublicAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final visual = alertLevelVisual(alert.level, p);
    final secondary = text.bodySmall!.copyWith(color: p.textSecondary);

    return Material(
      color: p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        side: BorderSide(color: p.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.alert(alert.id)),
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SagipChip.status(
                    label: l10n.alertLevel(alert.level),
                    visual: visual,
                  ),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(
                      l10n.alertSource(alert.source),
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium!.copyWith(color: p.textSecondary),
                    ),
                  ),
                  if (!alert.read) ...[
                    const SizedBox(width: SagipSpace.sm),
                    Semantics(
                      label: l10n.alertNew,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.info.fill,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: SagipSpace.md),
              Text(
                alert.title,
                style: text.titleMedium!.copyWith(
                  fontWeight: alert.read ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: SagipSpace.xs),
              Text(
                alert.barangays.isEmpty
                    ? l10n.alertAllManila
                    : alert.barangays.join(', '),
                style: secondary,
              ),
              Text(
                alertTime(l10n, alert.issuedAt, now, locale),
                style: secondary.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForecastView extends StatelessWidget {
  const _ForecastView({required this.feed});

  final AlertFeed feed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final f = feed.forecast;
    if (f == null) {
      return _Scrollable(
        child: EmptyState(
          icon: Symbols.query_stats_rounded,
          title: l10n.forecastEmpty,
        ),
      );
    }
    final top = f.topHazard;
    final secondary = text.bodySmall!.copyWith(color: p.textSecondary);

    Widget card(List<Widget> children) => DecoratedBox(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(SagipRadius.card),
        border: Border.all(color: p.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        SagipSpace.sm,
        SagipSpace.xl,
        SagipSpace.x3,
      ),
      children: [
        card([
          Text(l10n.forecastTitle, style: text.titleMedium),
          Text(
            l10n.place(f.barangay, f.district),
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: SagipSpace.xs),
          Text(l10n.forecastExplain, style: secondary),
          const SizedBox(height: SagipSpace.md),
          for (final h in ForecastHazard.values)
            _RiskRow(hazard: h, risk: f.risks[h] ?? RiskLevel.low),
          const SizedBox(height: SagipSpace.sm),
          Text(
            l10n.forecastValid(formatDateTime(f.validUntil, locale)),
            style: secondary.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (f.isSimulated) ...[
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.forecastSimulated, style: secondary),
          ],
        ]),
        const SizedBox(height: SagipSpace.md),
        card([
          Text(l10n.tipsTitle, style: text.titleMedium),
          const SizedBox(height: SagipSpace.sm),
          if (top == null)
            Text(l10n.tipsLow, style: text.bodyMedium)
          else
            for (final tip in l10n.tips(top)) BulletText(text: tip),
        ]),
      ],
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.hazard, required this.risk});

  final ForecastHazard hazard;
  final RiskLevel risk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final icon = switch (hazard) {
      ForecastHazard.flood => Symbols.flood_rounded,
      ForecastHazard.fire => Symbols.local_fire_department_rounded,
      ForecastHazard.stormSurge => Symbols.tsunami_rounded,
    };
    // Low is quiet; moderate and high use ember and signal, as on the
    // dashboard's forecast heatmap.
    final visual = switch (risk) {
      RiskLevel.low => StatusVisual(p.neutral, null, ChipLook.outline),
      RiskLevel.moderate => StatusVisual(
        p.warning,
        Symbols.trending_up_rounded,
      ),
      RiskLevel.high => StatusVisual(p.critical, Symbols.warning_rounded),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Icon(icon, color: p.textSecondary),
          const SizedBox(width: SagipSpace.md),
          Expanded(child: Text(l10n.hazard(hazard), style: text.bodyLarge)),
          SagipChip.status(
            label: l10n.risk(risk),
            visual: visual,
            dense: false,
          ),
        ],
      ),
    );
  }
}

/// One bullet point: a small dot and wrapped text (R7 tips, R8 guidance).
class BulletText extends StatelessWidget {
  const BulletText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    final p = SagipPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SagipSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: (style.fontSize! * (style.height ?? 1.5) - 6) / 2,
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: p.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: SagipSpace.md),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
