import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'web_frame.dart';
import 'web_providers.dart';
import 'web_router.dart';

/// W3 Report received and recent reports: the reference of the report just
/// sent, a reminder that one report is never confirmed on its own (FR7,
/// FR15), and the account's recent reports with where each one stands.
class WebReportsPage extends ConsumerWidget {
  const WebReportsPage({super.key, this.sentId});

  /// The report just sent, for example "rep-301".
  final String? sentId;

  /// How many reports the list shows.
  static const shown = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reports = ref.watch(myWebReportsProvider);
    final list = reports.value;

    return WebFrame(
      trailing: [
        TextButton(onPressed: () => webSignOut(ref), child: Text(l10n.signOut)),
      ],
      children: [
        if (sentId != null) ...[
          _Received(id: sentId!),
          const SizedBox(height: SagipSpace.x3),
        ],
        Text(l10n.webRecentTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.md),
        if (list != null)
          if (list.isEmpty)
            EmptyState(icon: Symbols.inbox_rounded, title: l10n.webNoReports)
          else
            Card(
              child: Column(
                children: [
                  for (final (i, r) in list.take(shown).indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _ReportRow(report: r),
                  ],
                ],
              ),
            )
        else if (reports.hasError)
          ErrorState(
            message: l10n.webReportsFailed,
            onRetry: () => ref.invalidate(myWebReportsProvider),
            retryLabel: l10n.retry,
          )
        else
          const SkeletonList(rows: 3),
        const SizedBox(height: SagipSpace.xxl),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => context.go(WebRoutes.report),
            child: Text(
              sentId == null ? l10n.webReportTitle : l10n.webSendAnother,
            ),
          ),
        ),
        const SizedBox(height: SagipSpace.x3),
        const SosNotice(),
      ],
    );
  }
}

class _Received extends StatelessWidget {
  const _Received({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Symbols.check_circle_rounded,
          size: 40,
          fill: 1,
          color: p.success.text,
        ),
        const SizedBox(height: SagipSpace.md),
        Text(l10n.webReceivedTitle, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.xs),
        SelectableText(
          l10n.webReference(id),
          style: text.titleSmall!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.webReceivedBody,
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});

  final HazardReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final muted = text.bodySmall!.copyWith(color: p.textSecondary);
    final stage = report.stage ?? ReportStage.received;
    final barangay = report.barangay;
    final district = report.district;
    return Padding(
      padding: const EdgeInsets.all(SagipSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.description,
                  style: text.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SagipSpace.xs),
                Text(
                  l10n.webReportWhen(
                    formatDate(report.capturedAt, l10n.localeName),
                    formatTime(report.capturedAt, l10n.localeName),
                  ),
                  style: muted.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (barangay != null && district != null)
                  Text(l10n.webPlace(barangay, district), style: muted),
                if (report.source != null)
                  Text(
                    report.source == ReportChannel.webForm
                        ? l10n.webSentFromWeb
                        : l10n.webSentFromApp,
                    style: muted,
                  ),
              ],
            ),
          ),
          const SizedBox(width: SagipSpace.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 148),
            child: SagipChip.status(
              label: switch (stage) {
                ReportStage.received => l10n.webStageReceived,
                ReportStage.checking => l10n.webStageChecking,
                ReportStage.confirmed => l10n.webStageConfirmed,
                ReportStage.notConfirmed => l10n.webStageNotConfirmed,
                ReportStage.resolved => l10n.webStageResolved,
              },
              visual: reportStageVisual(stage, p),
            ),
          ),
        ],
      ),
    );
  }
}
