import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';
import 'supply_widgets.dart';

/// Inventory (Joshua, 2026-11-01: separated from Units "so that there will
/// be a proper separation"): what each unit carries, as its crew last
/// reported it, one column per supply. Units keeps status, duty, and crew.
/// Read-only for dispatchers and admins; only a unit's own crew reports
/// its supplies (My unit). A row opens the unit's full report.
class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final unitsAsync = ref.watch(unitsProvider);
    final units = [...?unitsAsync.value]
      ..sort((a, b) => a.callSign.compareTo(b.callSign));
    final all = ref.watch(unitSuppliesProvider).value ?? const <UnitSupply>[];
    final lowPercent = ref.watch(inventoryLowPercentProvider);
    final supplies = {for (final u in units) u.id: suppliesOf(u.id, all)};
    final short = units
        .where((u) => shortSupplies(supplies[u.id]!, lowPercent).isNotEmpty)
        .length;

    return PageFrame(
      title: l10n.inventoryTitle,
      subtitle: l10n.inventoryIntro,
      headerTrailing: short > 0
          ? SagipChip(
              key: const ValueKey('inventory-short'),
              label: l10n.countLowSupplies(short),
              tone: p.warning,
              icon: Symbols.inventory_2_rounded,
              dense: false,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsyncBody(
            value: unitsAsync,
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(
              icon: Symbols.inventory_2_rounded,
              title: l10n.unitsEmpty,
              message: l10n.unitsEmptyMessage,
            ),
            onRetry: () => ref.invalidate(unitsProvider),
            builder: (_) => TableCard(
              table: DataTable(
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: Text(l10n.colCallSign)),
                  for (final item in SupplyItem.values)
                    DataColumn(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            supplyIcon(item),
                            size: 16,
                            color: p.textSecondary,
                          ),
                          const SizedBox(width: SagipSpace.xs),
                          Text(l10n.supplyItem(item)),
                        ],
                      ),
                    ),
                  DataColumn(label: Text(l10n.colLastReport)),
                ],
                rows: [
                  for (final u in units)
                    _row(
                      context,
                      u,
                      supplies[u.id]!,
                      lowPercent: lowPercent,
                      now: now,
                      locale: locale,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SagipSpace.md),
          Text(
            l10n.suppliesLowRule(lowPercent.round()),
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    ResponseUnit u,
    List<UnitSupply> supplies, {
    required double lowPercent,
    required DateTime now,
    required String locale,
  }) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final byItem = {for (final s in supplies) s.item: s};
    final latest = supplies.isEmpty
        ? null
        : supplies.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);
    return DataRow(
      key: ValueKey('inventory-row-${u.id}'),
      onSelectChanged: (_) => showDialog<void>(
        context: context,
        builder: (context) => SuppliesDialog(unitId: u.id),
      ),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(unitTypeIcon(u.type), size: 18),
              const SizedBox(width: SagipSpace.sm),
              Text(u.callSign, style: text.titleSmall),
            ],
          ),
        ),
        for (final item in SupplyItem.values)
          DataCell(
            SupplyAmount(
              key: ValueKey('inventory-${u.id}-${item.name}'),
              supply: byItem[item],
              lowPercent: lowPercent,
            ),
          ),
        DataCell(
          Text(
            latest == null
                ? l10n.suppliesNotReported
                : [
                    l10n.ago(latest.updatedAt, now),
                    latest.updatedByName,
                    if (latest.isStale(now)) l10n.suppliesOld,
                  ].where((s) => s.isNotEmpty).join(' · '),
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}
