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

/// D7: real-time status of every unit (FR9).
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
              DataColumn(label: Text(l10n.colStation)),
              DataColumn(label: Text(l10n.colCrew), numeric: true),
              DataColumn(label: Text(l10n.colStatus)),
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
                    DataCell(Text(u.station)),
                    DataCell(Text('${u.crewSize}')),
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
