import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// D10: PAGASA conditions, plus the EFCOS and PHIVOLCS feeds that are not
/// connected yet (shown honestly as such).
class WeatherPage extends ConsumerWidget {
  const WeatherPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weatherAsync = ref.watch(weatherProvider);

    return PageFrame(
      title: l10n.weatherTitle,
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
                  icon: Symbols.cyclone_rounded,
                  label: l10n.signalCard,
                  value: w.signalLevel > 0
                      ? l10n.signalLevel(w.signalLevel)
                      : l10n.noSignal,
                  tone: w.signalLevel > 0 ? p.warning : p.neutral,
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                ),
                _StatCard(
                  icon: Symbols.rainy_rounded,
                  label: l10n.rainfallCard,
                  value: l10n.rainfallValue(
                    w.rainfallMmPerHour.toStringAsFixed(1),
                  ),
                  tone: p.info,
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                ),
                _StatCard(
                  icon: Symbols.tsunami_rounded,
                  label: l10n.stormSurgeCard,
                  value: w.stormSurgeAdvisory ?? l10n.noAdvisory,
                  tone: w.stormSurgeAdvisory == null ? p.neutral : p.warning,
                  footer: l10n.issuedAt(formatTime(w.issuedAt, locale)),
                  wide: true,
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.xxl),
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
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.footer,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final SagipTone tone;
  final String footer;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
                  Text(label, style: text.labelMedium),
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
            ],
          ),
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
