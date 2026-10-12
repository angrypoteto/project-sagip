import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../common_page.dart';
import 'supply_widgets.dart';

/// D7: real-time status of every unit (FR9), with what each carries as its
/// crew last reported it: a unit that is low on something says so here,
/// before a dispatcher sends it.
class UnitsPage extends ConsumerWidget {
  const UnitsPage({super.key});

  /// GPS older than this is flagged as stale.
  static const staleAfter = Duration(minutes: 3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final unitsAsync = ref.watch(unitsProvider);
    final units = [...?unitsAsync.value]
      ..sort((a, b) => a.callSign.compareTo(b.callSign));
    final allSupplies = ref.watch(unitSuppliesProvider).value ?? const [];
    final lowPercent = ref.watch(inventoryLowPercentProvider);
    final supplies = {
      for (final u in units) u.id: suppliesOf(u.id, allSupplies),
    };
    final lowUnits = units
        .where((u) => shortSupplies(supplies[u.id]!, lowPercent).isNotEmpty)
        .length;

    int count(bool Function(ResponseUnit) test) => units.where(test).length;

    return PageFrame(
      title: l10n.unitsTitle,
      headerTrailing: Wrap(
        spacing: SagipSpace.sm,
        children: [
          SagipChip(
            label: l10n.countAvailable(count((u) => u.isDispatchable)),
            tone: p.success,
            icon: Symbols.check_circle_rounded,
            dense: false,
          ),
          SagipChip(
            label: l10n.countEnRoute(
              count((u) => u.status == UnitStatus.enRoute),
            ),
            tone: p.info,
            icon: Symbols.navigation_rounded,
            dense: false,
          ),
          SagipChip(
            label: l10n.countOnScene(
              count((u) => u.status == UnitStatus.onScene),
            ),
            tone: p.onScene,
            icon: Symbols.location_on_rounded,
            dense: false,
          ),
          if (lowUnits > 0)
            SagipChip(
              key: const ValueKey('units-low-supplies'),
              label: l10n.countLowSupplies(lowUnits),
              tone: p.warning,
              icon: Symbols.inventory_2_rounded,
              dense: false,
            ),
        ],
      ),
      child: AsyncBody(
        value: unitsAsync,
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(
          icon: Symbols.ambulance_rounded,
          title: l10n.unitsEmpty,
          message: l10n.unitsEmptyMessage,
        ),
        builder: (_) => TableCard(
          table: DataTable(
            showCheckboxColumn: false,
            columns: [
              DataColumn(label: Text(l10n.colCallSign)),
              DataColumn(label: Text(l10n.colUnitType)),
              DataColumn(label: Text(l10n.colAgency)),
              DataColumn(label: Text(l10n.colStation)),
              DataColumn(label: Text(l10n.colCrew), numeric: true),
              DataColumn(label: Text(l10n.colStatus)),
              DataColumn(label: Text(l10n.colSupplies)),
              DataColumn(label: Text(l10n.colIncident)),
              DataColumn(label: Text(l10n.colLastGps)),
            ],
            rows: [
              for (final u in units)
                DataRow(
                  onSelectChanged: u.currentIncidentId == null
                      ? null
                      : (_) =>
                            context.go(Routes.incident(u.currentIncidentId!)),
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Icon(unitTypeIcon(u.type), size: 18),
                          const SizedBox(width: SagipSpace.sm),
                          Text(u.callSign, style: text.titleSmall),
                        ],
                      ),
                    ),
                    DataCell(Text(l10n.unitType(u.type))),
                    DataCell(Text(l10n.unitAgency(u.agency))),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(u.station, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    DataCell(Text('${u.crewSize ?? '–'}')),
                    DataCell(
                      u.status == UnitStatus.available && !u.isDispatchable
                          ? SagipChip.status(
                              label: l10n.assignedNotStarted,
                              visual: incidentStatusVisual(
                                IncidentStatus.assigned,
                                p,
                              ),
                            )
                          : SagipChip.status(
                              label: l10n.unitStatus(u.status),
                              visual: unitStatusVisual(u.status, p),
                            ),
                    ),
                    DataCell(
                      _SuppliesCell(
                        key: ValueKey('supplies-${u.id}'),
                        supplies: supplies[u.id]!,
                        lowPercent: lowPercent,
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => _SuppliesDialog(unitId: u.id),
                      ),
                    ),
                    DataCell(Text(u.currentIncidentId ?? '')),
                    DataCell(
                      u.lastLocationAt == null
                          ? const Text('')
                          : Row(
                              children: [
                                Text(l10n.ago(u.lastLocationAt!, now)),
                                if (now.difference(u.lastLocationAt!) >
                                    staleAfter) ...[
                                  const SizedBox(width: SagipSpace.sm),
                                  SagipChip(
                                    label: l10n.staleGps,
                                    tone: p.warning,
                                    icon: Symbols.gps_off_rounded,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Units table's summary of what a unit carries: what is short, or
/// that all is enough, or that nothing was reported.
class _SuppliesCell extends StatelessWidget {
  const _SuppliesCell({
    super.key,
    required this.supplies,
    required this.lowPercent,
  });

  final List<UnitSupply> supplies;
  final double lowPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    if (supplies.isEmpty) {
      return Text(
        l10n.suppliesNotReported,
        style: text.bodySmall!.copyWith(color: p.textSecondary),
      );
    }
    String names(SupplyState state) => [
      for (final s in supplies)
        if (s.stateAt(lowPercent) == state) l10n.supplyItem(s.item),
    ].join(', ');
    final out = names(SupplyState.out);
    final low = names(SupplyState.low);
    if (out.isEmpty && low.isEmpty) {
      final (tone, icon) = supplyVisual(SupplyState.ok, p);
      return SagipChip(label: l10n.suppliesAllGood, tone: tone, icon: icon);
    }
    return Wrap(
      spacing: SagipSpace.xs,
      runSpacing: SagipSpace.xs,
      children: [
        for (final (state, list) in [
          (SupplyState.out, out),
          (SupplyState.low, low),
        ])
          if (list.isNotEmpty)
            SagipChip(
              label: l10n.suppliesShort(l10n.supplyState(state), list),
              tone: supplyVisual(state, p).$1,
              icon: supplyVisual(state, p).$2,
            ),
      ],
    );
  }
}

/// Everything one unit carries, each with its level and when it was
/// reported. Read-only: only the unit's own crew changes it.
class _SuppliesDialog extends ConsumerWidget {
  const _SuppliesDialog({required this.unitId});

  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final lowPercent = ref.watch(inventoryLowPercentProvider);
    final unit = (ref.watch(unitsProvider).value ?? const <ResponseUnit>[])
        .where((u) => u.id == unitId)
        .firstOrNull;
    final supplies = suppliesOf(
      unitId,
      ref.watch(unitSuppliesProvider).value ?? const [],
    );
    return AlertDialog(
      title: Text(l10n.suppliesOf(unit?.callSign ?? unitId)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unit != null)
                Text(
                  '${l10n.unitType(unit.type)} · '
                  '${l10n.unitAgency(unit.agency)} · ${unit.station}',
                  style: text.bodyMedium,
                ),
              if (unit?.source != null) ...[
                const SizedBox(height: SagipSpace.xs),
                Text(
                  l10n.unitSourceNote(unit!.source!),
                  style: text.bodySmall!.copyWith(color: p.textSecondary),
                ),
              ],
              const SizedBox(height: SagipSpace.md),
              if (supplies.isEmpty)
                Text(l10n.suppliesNone, style: text.bodyMedium)
              else
                for (final s in supplies)
                  SupplyLine(supply: s, lowPercent: lowPercent, now: now),
              const SizedBox(height: SagipSpace.sm),
              Text(
                l10n.suppliesLowRule(lowPercent.round()),
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
