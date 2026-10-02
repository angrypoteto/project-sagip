import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../common_page.dart';

/// Draft is quiet; final is settled (verdant, with a check).
StatusVisual reportStatusVisual(ReportStatus status, SagipPalette p) =>
    switch (status) {
      ReportStatus.draft => StatusVisual(
        p.neutral,
        Symbols.edit_note_rounded,
        ChipLook.outline,
      ),
      ReportStatus.finalized => StatusVisual(
        p.success,
        Symbols.check_circle_rounded,
      ),
    };

/// A5: every NDRRMC report, newest first (Objective 4). Admins only.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final reportsAsync = ref.watch(reportsProvider);
    final online = ref.watch(isOnlineProvider);

    return PageFrame(
      title: l10n.reportsTitle,
      subtitle: l10n.reportsSubtitle,
      headerTrailing: FilledButton.icon(
        key: const ValueKey('report-new'),
        onPressed: online ? () => context.go(Routes.newReport) : null,
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.reportNew),
      ),
      child: AsyncBody(
        value: reportsAsync,
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(
          icon: Symbols.description_rounded,
          title: l10n.reportsEmpty,
          message: l10n.reportsEmptyHint,
        ),
        onRetry: () => ref.invalidate(reportsProvider),
        builder: (reports) => TableCard(
          table: DataTable(
            showCheckboxColumn: false,
            columns: [
              DataColumn(label: Text(l10n.colReport)),
              DataColumn(label: Text(l10n.colPeriod)),
              DataColumn(label: Text(l10n.colStatus)),
              DataColumn(label: Text(l10n.colMadeBy)),
              DataColumn(label: Text(l10n.colMadeOn)),
            ],
            rows: [
              for (final r in reports)
                DataRow(
                  key: ValueKey('report-${r.id}'),
                  onSelectChanged: (_) => context.go(Routes.report(r.id)),
                  cells: [
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: text.titleSmall),
                          Text(r.id, style: text.bodySmall),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        l10n.reportPeriod(
                          formatDateTime(r.periodStart, locale),
                          formatDateTime(r.periodEnd, locale),
                        ),
                      ),
                    ),
                    DataCell(
                      SagipChip.status(
                        label: r.isFinal
                            ? l10n.reportStatusFinal
                            : l10n.reportStatusDraft,
                        visual: reportStatusVisual(r.status, p),
                      ),
                    ),
                    DataCell(Text(r.createdByName)),
                    DataCell(Text(formatDateTime(r.createdAt, locale))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
