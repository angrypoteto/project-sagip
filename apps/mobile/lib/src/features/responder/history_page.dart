import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../activity/activity_page.dart';

enum _Range { all, thisWeek, lastWeek }

/// F7 Assignment history: finished assignments, newest first, with the
/// outcome and whether the completion report has reached the server.
/// Read from the phone's copy, so it works offline.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  var _range = _Range.all;

  /// Weeks start on Monday.
  bool _inRange(DateTime at, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final lastMonday = monday.subtract(const Duration(days: 7));
    return switch (_range) {
      _Range.all => true,
      _Range.thisWeek => !at.isBefore(monday),
      _Range.lastWeek => !at.isBefore(lastMonday) && at.isBefore(monday),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final history = ref.watch(responderHistoryProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();

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
          child: Text(l10n.historyTitle, style: text.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
          child: Wrap(
            spacing: SagipSpace.sm,
            children: [
              for (final (range, label) in [
                (_Range.all, l10n.historyAll),
                (_Range.thisWeek, l10n.historyThisWeek),
                (_Range.lastWeek, l10n.historyLastWeek),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _range == range,
                  onSelected: (_) => setState(() => _range = range),
                ),
            ],
          ),
        ),
        const SizedBox(height: SagipSpace.sm),
        Expanded(child: _list(context, history, now)),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    AsyncValue<List<CompletedAssignment>> history,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final all = history.value;
    if (all == null) {
      return history.hasError
          ? ErrorState(
              message: l10n.historyError,
              onRetry: () => ref.invalidate(responderHistoryProvider),
              retryLabel: l10n.retry,
            )
          : const SkeletonList(rows: 4, rowHeight: 88);
    }
    if (all.isEmpty) {
      return EmptyState(
        icon: Symbols.history_rounded,
        title: l10n.historyEmpty,
      );
    }
    final shown = [
      for (final a in all)
        if (_inRange(a.completedAt, now)) a,
    ];
    if (shown.isEmpty) {
      return EmptyState(
        icon: Symbols.date_range_rounded,
        title: l10n.historyEmptyFilter,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: SagipSpace.x3),
      children: [
        if (history.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.xl,
              vertical: SagipSpace.sm,
            ),
            child: Text(
              l10n.historyError,
              style: text.bodySmall!.copyWith(color: p.warning.text),
            ),
          ),
        for (final (i, a) in shown.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: SagipSpace.xl + 40 + SagipSpace.lg,
              endIndent: SagipSpace.xl,
            ),
          ActivityRow(
            icon: incidentTypeIcon(a.type),
            title: l10n.historyRowTitle(
              a.incidentId,
              l10n.typeOrEmergency(a.type),
            ),
            titleLines: 2,
            detail: a.place,
            subtitle: formatDateTime(a.completedAt, locale),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SagipChip(
                  label: l10n.outcomeLabel(a.outcome),
                  tone: p.neutral,
                  look: ChipLook.outline,
                ),
                if (a.reportDelivery != DeliveryState.delivered) ...[
                  const SizedBox(height: SagipSpace.xs),
                  DeliveryBadge(
                    state: a.reportDelivery,
                    label: l10n.delivery(a.reportDelivery),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
