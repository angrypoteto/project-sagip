import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';
import 'advisory_dialog.dart';

/// D10: PAGASA conditions against the A3 alert thresholds, the log of
/// alerts sent with each channel's outcome (FR5, FR6), and the EFCOS and
/// PHIVOLCS feeds that are not connected yet (shown honestly as such).
class WeatherPage extends ConsumerWidget {
  const WeatherPage({super.key});

  static String _plain(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weatherAsync = ref.watch(weatherProvider);
    final thresholds = ref.watch(alertThresholdsProvider);

    String note(WeatherHazard h) => l10n.thresholdNote(
      _plain(thresholds.warningAt(h)),
      _plain(thresholds.criticalAt(h)),
    );

    return PageFrame(
      title: l10n.weatherTitle,
      headerTrailing: FilledButton.icon(
        key: const ValueKey('issue-advisory'),
        onPressed: ref.watch(isOnlineProvider)
            ? () => showAdvisoryDialog(context)
            : null,
        icon: const Icon(Symbols.campaign_rounded),
        label: Text(l10n.advisoryTitle),
      ),
      child: AsyncBody(
        value: weatherAsync,
        loading: const SkeletonBox(height: 160, radius: SagipRadius.card),
        builder: (w) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w.isSimulated) ...[
              Row(
                children: [
                  SagipChip(
                    label: l10n.simulatedFeed,
                    tone: p.neutral,
                    icon: Symbols.replay_rounded,
                  ),
                  const SizedBox(width: SagipSpace.md),
                  Expanded(
                    child: Text(
                      l10n.simulatedWeatherNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SagipSpace.lg),
            ],
            Wrap(
              spacing: SagipSpace.lg,
              runSpacing: SagipSpace.lg,
              children: [
                _StatCard(
                  id: 'signal',
                  icon: Symbols.cyclone_rounded,
                  label: l10n.signalCard,
                  value: w.signalLevel > 0
                      ? l10n.signalLevel(w.signalLevel)
                      : l10n.noSignal,
                  level: thresholds.levelIn(w, WeatherHazard.signal),
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                  threshold: note(WeatherHazard.signal),
                ),
                _StatCard(
                  id: 'rainfall',
                  icon: Symbols.rainy_rounded,
                  label: l10n.rainfallCard,
                  value: l10n.rainfallValue(
                    w.rainfallMmPerHour.toStringAsFixed(1),
                  ),
                  level: thresholds.levelIn(w, WeatherHazard.rainfall),
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                  threshold: note(WeatherHazard.rainfall),
                ),
                _StatCard(
                  id: 'surge',
                  icon: Symbols.tsunami_rounded,
                  label: l10n.stormSurgeCard,
                  value: w.stormSurgeMeters != null
                      ? l10n.stormSurgeMeters(_plain(w.stormSurgeMeters!))
                      : (w.stormSurgeAdvisory ?? l10n.noAdvisory),
                  level: thresholds.levelIn(w, WeatherHazard.surge),
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                  threshold: note(WeatherHazard.surge),
                  wide: w.stormSurgeMeters == null,
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.xxl),
            const _AlertLog(),
            const SizedBox(height: SagipSpace.xxl),
            const _PagasaFeed(),
            const SizedBox(height: SagipSpace.md),
            _FeedNotice(
              icon: Symbols.water_rounded,
              title: l10n.efcosTitle,
              message: l10n.efcosNotConnected,
            ),
            const SizedBox(height: SagipSpace.md),
            _FeedNotice(
              icon: Symbols.volcano_rounded,
              title: l10n.phivolcsTitle,
              message: l10n.phivolcsNotConnected,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.level,
    required this.footer,
    required this.threshold,
    this.wide = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final String value;

  /// Warning or critical when the reading is at or above its A3 threshold.
  final AlertLevel? level;
  final String footer;
  final String threshold;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final tone = switch (level) {
      AlertLevel.critical => p.critical,
      AlertLevel.warning => p.warning,
      _ => p.neutral,
    };
    return SizedBox(
      width: wide ? 420 : 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: tone.text),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(child: Text(label, style: text.labelMedium)),
                  if (level != null)
                    SagipChip(
                      key: ValueKey('level-$id'),
                      label: l10n.alertLevel(level!),
                      tone: tone,
                      icon: level == AlertLevel.critical
                          ? Symbols.warning_rounded
                          : Symbols.error_rounded,
                    ),
                ],
              ),
              const SizedBox(height: SagipSpace.md),
              Text(
                value,
                style: (wide ? text.titleMedium : text.displaySmall)!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: SagipSpace.sm),
              Text(footer, style: text.bodySmall),
              Text(
                threshold,
                style: text.bodySmall!.copyWith(
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

/// The log of alerts sent: each alert with its level, where it applies,
/// and what happened on every channel.
class _AlertLog extends ConsumerWidget {
  const _AlertLog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final log = ref.watch(alertLogProvider);
    final alerts = log.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.alertLogTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.xs),
        Text(l10n.alertLogNote, style: text.bodySmall),
        const SizedBox(height: SagipSpace.md),
        if (alerts != null)
          if (alerts.isEmpty)
            Card(
              child: EmptyState(
                icon: Symbols.campaign_rounded,
                title: l10n.alertLogEmpty,
              ),
            )
          else
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, a) in alerts.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _AlertRow(sent: a),
                  ],
                ],
              ),
            )
        else if (log.hasError)
          Card(
            child: ErrorState(
              message: l10n.alertLogFailed,
              onRetry: () => ref.invalidate(alertLogProvider),
              retryLabel: l10n.retry,
            ),
          )
        else
          const SkeletonList(rows: 3),
      ],
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.sent});

  final SentAlert sent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final a = sent.alert;
    final ended = !a.activeAt(now);
    final tone = switch (a.level) {
      AlertLevel.critical => p.critical,
      AlertLevel.warning => p.warning,
      AlertLevel.info => p.info,
    };
    return Padding(
      key: ValueKey('alert-${a.id}'),
      padding: const EdgeInsets.all(SagipSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: SagipSpace.sm,
            runSpacing: SagipSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SagipChip(
                label: l10n.alertLevel(a.level),
                tone: tone,
                icon: switch (a.level) {
                  AlertLevel.critical => Symbols.warning_rounded,
                  AlertLevel.warning => Symbols.error_rounded,
                  AlertLevel.info => Symbols.info_rounded,
                },
              ),
              if (a.isSimulated)
                SagipChip(
                  label: l10n.alertSimulated,
                  tone: p.neutral,
                  icon: Symbols.replay_rounded,
                ),
              if (ended)
                SagipChip(
                  label: l10n.alertEnded,
                  tone: p.neutral,
                  look: ChipLook.outline,
                ),
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          Text(a.title, style: text.titleSmall),
          Text(
            l10n.alertFrom(
              l10n.alertSource(a.source),
              formatDateTime(a.issuedAt, locale),
            ),
            style: text.bodySmall!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            a.barangays.isEmpty ? l10n.alertAllManila : a.barangays.join(', '),
            style: text.bodySmall,
          ),
          if (a.hazard != null)
            Text(l10n.alertAutomatic, style: text.bodySmall),
          const SizedBox(height: SagipSpace.sm),
          Wrap(
            spacing: SagipSpace.lg,
            runSpacing: SagipSpace.xs,
            children: [
              for (final d in sent.deliveries)
                Text(
                  d.recipients != null && d.delivered != null
                      ? l10n.deliveryCounts(
                          l10n.alertChannel(d.channel),
                          d.delivered!,
                          d.recipients!,
                        )
                      : l10n.deliveryLine(
                          l10n.alertChannel(d.channel),
                          l10n.deliveryStatus(d.status),
                        ),
                  style: text.bodySmall!.copyWith(
                    color: switch (d.status) {
                      AlertDeliveryStatus.failed => p.critical.text,
                      AlertDeliveryStatus.queued ||
                      AlertDeliveryStatus.sending => p.warning.text,
                      AlertDeliveryStatus.sent => p.success.text,
                      _ => p.textSecondary,
                    },
                  ),
                ),
            ],
          ),
          if (!ended)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('end-${a.id}'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: ref.watch(isOnlineProvider)
                    ? () => confirmEndAlert(context, ref, a)
                    : null,
                child: Text(l10n.endAlert),
              ),
            ),
          // Why a channel did not go out in full (written by the sender).
          for (final d in sent.deliveries)
            if (d.detail != null && d.detail!.isNotEmpty)
              Text(
                l10n.deliveryLine(l10n.alertChannel(d.channel), d.detail!),
                style: text.bodySmall,
              ),
        ],
      ),
    );
  }
}

/// Whether the PAGASA feed is reading PAGASA's pages, and what it read
/// last (FR5). When a page cannot be read, dispatchers relay by hand.
class _PagasaFeed extends ConsumerWidget {
  const _PagasaFeed();

  String _what(AppLocalizations l10n, FeedStatus f) {
    final seen = f.seen;
    final number = (seen['number'] as num?)?.toInt() ?? 0;
    return switch (f.source) {
      FeedSource.pagasaRainfall => switch (seen['state']) {
        'warning' => switch (seen['level']) {
          final String level => l10n.feedWarningManila(number, switch (level) {
            'red' => l10n.rainLevelRed,
            'orange' => l10n.rainLevelOrange,
            _ => l10n.rainLevelYellow,
          }),
          _ => l10n.feedWarningElsewhere(number),
        },
        _ => l10n.feedNoWarning,
      },
      FeedSource.pagasaCyclone => switch (seen['state']) {
        'bulletin' => l10n.feedBulletin(
          number,
          (seen['name'] as String?) ?? '-',
          ((seen['signal'] as num?)?.toInt() ?? 0) > 0
              ? l10n.signalLevel((seen['signal']! as num).toInt())
              : l10n.feedNoSignalManila,
        ),
        _ => l10n.feedNoCyclone,
      },
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final feeds = ref.watch(feedStatusProvider).value;

    Widget line(FeedStatus f) {
      final label = f.source == FeedSource.pagasaRainfall
          ? l10n.feedRainfall
          : l10n.feedCyclone;
      final lastGood = f.lastSuccessAt;
      return Padding(
        key: ValueKey('feed-${f.source.name}'),
        padding: const EdgeInsets.only(top: SagipSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              f.ok ? Symbols.check_circle_rounded : Symbols.error_rounded,
              size: 18,
              color: f.ok ? p.success.text : p.critical.text,
            ),
            const SizedBox(width: SagipSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label · ${l10n.feedChecked(formatTime(f.checkedAt, locale))}',
                    style: text.bodySmall,
                  ),
                  Text(
                    f.ok
                        ? _what(l10n, f)
                        : lastGood == null
                        ? l10n.feedDownNever
                        : l10n.feedDown(
                            f.failures,
                            formatTime(lastGood, locale),
                          ),
                    style: text.bodyMedium!.copyWith(
                      color: f.ok ? null : p.critical.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Symbols.rss_feed_rounded, size: 22),
            const SizedBox(width: SagipSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.feedTitle, style: text.titleSmall),
                  if (feeds == null)
                    const SizedBox.shrink()
                  else if (feeds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: SagipSpace.xs),
                      child: Text(l10n.feedNotConnected, style: text.bodySmall),
                    )
                  else
                    for (final f in feeds) line(f),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedNotice extends StatelessWidget {
  const _FeedNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: SagipSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const SizedBox(height: SagipSpace.xs),
                  Text(message, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
