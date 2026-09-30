import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'alerts_page.dart';

/// R8 Alert detail: the full text, affected areas, and what to do (FR14).
/// Opening it marks the alert read. Works from the phone's saved copy.
class AlertDetailPage extends ConsumerStatefulWidget {
  const AlertDetailPage({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<AlertDetailPage> createState() => _AlertDetailPageState();
}

class _AlertDetailPageState extends ConsumerState<AlertDetailPage> {
  @override
  void initState() {
    super.initState();
    ref.read(alertRepositoryProvider).markRead(widget.alertId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(alertFeedProvider);
    PublicAlert? alert;
    for (final a in feed.value?.alerts ?? const <PublicAlert>[]) {
      if (a.id == widget.alertId) alert = a;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          alert == null ? l10n.alertsTitle : l10n.alertSource(alert.source),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfflineBanner(),
          Expanded(
            child: feed.value == null && !feed.hasError
                ? const SkeletonList(rows: 4)
                : alert == null
                ? ErrorState(message: l10n.alertGone)
                : _Body(alert: alert),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.alert});

  final PublicAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: SagipSpace.xl, bottom: SagipSpace.sm),
      child: Text(title, style: text.titleMedium),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        SagipSpace.lg,
        SagipSpace.xl,
        SagipSpace.x3,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SagipChip.status(
            label: l10n.alertLevel(alert.level),
            visual: alertLevelVisual(alert.level, p),
            dense: false,
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        Text(alert.title, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.alertIssued(formatDateTime(alert.issuedAt, locale)),
          style: text.bodySmall!.copyWith(
            color: p.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(alert.body, style: text.bodyLarge),
        section(l10n.alertAffects),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.location_on_rounded, color: p.textSecondary),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Text(
                alert.barangays.isEmpty
                    ? l10n.alertAllManila
                    : alert.barangays.join(', '),
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
        if (alert.guidance.isNotEmpty) ...[
          section(l10n.alertWhatToDo),
          for (final g in alert.guidance) BulletText(text: g),
        ],
      ],
    );
  }
}
