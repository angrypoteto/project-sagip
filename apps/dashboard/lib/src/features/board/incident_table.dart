import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'queue_panel.dart';

/// D3 list view: the same queue as a table.
class IncidentTable extends ConsumerWidget {
  const IncidentTable({
    super.key,
    required this.selectedId,
    required this.onSelect,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final rules = ref.watch(priorityRulesProvider);
    final units = ref.watch(unitsByIdProvider);
    final queue = ref.watch(visibleQueueProvider);
    final tabular = text.bodyMedium!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (queue.isEmpty) {
      return EmptyState(
        icon: Symbols.inbox_rounded,
        title: l10n.queueEmpty,
        message: l10n.queueEmptyMessage,
      );
    }

    return ColoredBox(
      color: p.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SagipSpace.xxl,
          72,
          SagipSpace.xxl,
          SagipSpace.xxl,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: [
                DataColumn(label: Text(l10n.colPriority)),
                DataColumn(label: Text(l10n.colWaiting), numeric: true),
                DataColumn(label: Text(l10n.colStatus)),
                DataColumn(label: Text(l10n.colType)),
                DataColumn(label: Text(l10n.colPlace)),
                DataColumn(label: Text(l10n.colChannel)),
                DataColumn(label: Text(l10n.colVerified)),
                DataColumn(label: Text(l10n.colVulnerable)),
                DataColumn(label: Text(l10n.colUnit)),
              ],
              rows: [
                for (final i in queue)
                  _row(context, i, now, rules, units, l10n, p, tabular),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    Incident i,
    DateTime now,
    PriorityRules rules,
    Map<String, ResponseUnit> units,
    AppLocalizations l10n,
    SagipPalette p,
    TextStyle tabular,
  ) {
    final score = rules.score(i, now);
    final visual = incidentStatusVisual(i.status, p);
    return DataRow(
      selected: i.id == selectedId,
      onSelectChanged: (_) => onSelect(i.id),
      cells: [
        DataCell(
          Row(
            children: [
              Container(
                width: 3,
                height: 20,
                color: severityColor(score.severity, p),
              ),
              const SizedBox(width: SagipSpace.sm),
              Text('${score.total.round()}', style: tabular),
              const SizedBox(width: SagipSpace.sm),
              Text(l10n.severity(score.severity)),
            ],
          ),
        ),
        DataCell(
          Text(formatWait(now.difference(i.capturedAt)), style: tabular),
        ),
        DataCell(
          SagipChip.status(
            label: l10n.incidentStatus(i.status),
            visual: visual,
          ),
        ),
        DataCell(Text(l10n.incidentTitle(i))),
        DataCell(Text(i.place)),
        DataCell(Text(l10n.channel(i.channel))),
        DataCell(Text(i.isVerified ? l10n.yes : l10n.no)),
        DataCell(Text(i.vulnerable.map(l10n.vulnerability).join(', '))),
        DataCell(Text(units[i.assignedUnitId]?.callSign ?? '')),
      ],
    );
  }
}
