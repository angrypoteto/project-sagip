import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// R6 report detail: what happened to one hazard report. It follows the
/// live list, so a stage change shows while the sheet is open.
Future<void> showReportDetail(BuildContext context, String clientId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ReportDetailSheet(clientId: clientId),
    );

class ReportDetailSheet extends ConsumerWidget {
  const ReportDetailSheet({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    HazardReport? report;
    for (final r in ref.watch(myReportsProvider).value ?? const []) {
      if (r.clientId == clientId) report = r;
    }
    if (report == null) return const SizedBox(height: 120);
    final r = report;
    final stage = r.stage;

    // Received, Checking, then Confirmed and Resolved. The last step done;
    // the one after it is current. A report no one else made stops after
    // Checking (FR7).
    final reached = switch (stage) {
      null => -1,
      ReportStage.received || ReportStage.checking => 0,
      ReportStage.notConfirmed => 1,
      ReportStage.confirmed => 2,
      ReportStage.resolved => 3,
    };
    final steps = [
      l10n.reportStepReceived,
      l10n.reportStepChecking,
      if (stage != ReportStage.notConfirmed) ...[
        l10n.reportStepConfirmed,
        l10n.reportStepResolved,
      ],
    ];
    final note = switch (stage) {
      null => l10n.reportNoteWaiting,
      ReportStage.received => l10n.reportNoteReceived,
      ReportStage.checking => l10n.reportNoteChecking,
      ReportStage.confirmed => l10n.reportNoteConfirmed(r.incidentId ?? ''),
      ReportStage.notConfirmed => l10n.reportNoteNotConfirmed,
      ReportStage.resolved => l10n.reportNoteResolved(r.incidentId ?? ''),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        0,
        SagipSpace.xl,
        SagipSpace.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reportDetailTitle, style: text.titleLarge),
          const SizedBox(height: SagipSpace.sm),
          Wrap(
            spacing: SagipSpace.sm,
            runSpacing: SagipSpace.sm,
            children: [
              if (r.type != null)
                SagipChip(
                  label: l10n.incidentType(r.type!),
                  tone: p.neutral,
                  icon: incidentTypeIcon(r.type),
                  look: ChipLook.outline,
                ),
              DeliveryBadge(
                state: r.delivery,
                label: l10n.delivery(r.delivery),
              ),
            ],
          ),
          const SizedBox(height: SagipSpace.lg),
          Text(r.description, style: text.bodyLarge),
          const SizedBox(height: SagipSpace.sm),
          Text(
            [
              l10n.capturedAt(formatDateTime(r.capturedAt, locale)),
              if (r.barangay != null && r.district != null)
                l10n.place(r.barangay!, r.district!),
            ].join('\n'),
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: SagipSpace.xl),
          for (var i = 0; i < steps.length; i++)
            TimelineStep(
              label: steps[i],
              time: i == 0 && r.deliveredAt != null
                  ? formatTime(r.deliveredAt!, locale)
                  : null,
              state: i <= reached
                  ? TimelineState.done
                  : (i == reached + 1 && stage != ReportStage.notConfirmed
                        ? TimelineState.current
                        : TimelineState.later),
              last: i == steps.length - 1,
            ),
          Text(note, style: text.bodyMedium!.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}
