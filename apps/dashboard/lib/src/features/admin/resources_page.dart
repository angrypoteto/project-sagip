import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// A2 Resources (admin): units (add, edit, retire, restore) and the roster
/// of responders on each unit (plan 7.4). The database checks every change
/// and writes it to the audit log (FR11).
class ResourcesPage extends ConsumerWidget {
  const ResourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(isOnlineProvider);
    return PageFrame(
      title: l10n.navResources,
      subtitle: l10n.resourcesSubtitle,
      headerTrailing: FilledButton.icon(
        onPressed: online ? () => showUnitDialog(context, ref) : null,
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.addUnit),
      ),
      child: AsyncBody(
        value: ref.watch(allUnitsProvider),
        isEmpty: (units) => units.isEmpty,
        empty: EmptyState(
          icon: Symbols.ambulance_rounded,
          title: l10n.noAvailableUnits,
        ),
        builder: (units) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!online) ...[
              Text(
                l10n.offlineActionsDisabled,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: SagipSpace.md),
            ],
            _UnitsTable(units: units, online: online),
            const SizedBox(height: SagipSpace.xxl),
            _Roster(units: units, online: online),
          ],
        ),
      ),
    );
  }
}

class _UnitsTable extends ConsumerWidget {
  const _UnitsTable({required this.units, required this.online});

  final List<ResponseUnit> units;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final crew = ref.watch(respondersProvider).value ?? const [];
    // In service first, then retired; each by call sign.
    final sorted = [...units]
      ..sort((a, b) {
        final byRetired = (a.retired ? 1 : 0).compareTo(b.retired ? 1 : 0);
        return byRetired != 0 ? byRetired : a.callSign.compareTo(b.callSign);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.unitsTitleA2, style: text.titleMedium),
        const SizedBox(height: SagipSpace.sm),
        TableCard(
          table: DataTable(
            columnSpacing: SagipSpace.xl,
            columns: [
              DataColumn(label: Text(l10n.colCallSign)),
              DataColumn(label: Text(l10n.colUnitType)),
              DataColumn(label: Text(l10n.colStation)),
              DataColumn(label: Text(l10n.colCrew), numeric: true),
              DataColumn(label: Text(l10n.colStatus)),
              DataColumn(label: Text(l10n.colResponders)),
              const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final u in sorted)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        u.callSign,
                        style: text.bodyMedium!.copyWith(
                          color: u.retired ? p.textSecondary : null,
                        ),
                      ),
                    ),
                    DataCell(Text(l10n.unitType(u.type))),
                    DataCell(Text(u.station)),
                    DataCell(Text('${u.crewSize}')),
                    DataCell(
                      u.retired
                          ? SagipChip(
                              label: l10n.retiredChip,
                              tone: p.neutral,
                              icon: Symbols.inventory_2_rounded,
                            )
                          : SagipChip.status(
                              label: l10n.unitStatus(u.status),
                              visual: unitStatusVisual(u.status, p),
                            ),
                    ),
                    DataCell(
                      Text(
                        [
                          for (final s in crew)
                            if (s.unitId == u.id) s.displayName,
                        ].join(', '),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('edit-${u.id}'),
                            tooltip: l10n.edit,
                            onPressed: online && !u.retired
                                ? () => showUnitDialog(context, ref, unit: u)
                                : null,
                            icon: const Icon(Symbols.edit_rounded),
                          ),
                          if (u.retired)
                            IconButton(
                              key: ValueKey('restore-${u.id}'),
                              tooltip: l10n.restore,
                              onPressed: online
                                  ? () => runAction(
                                      context,
                                      () => ref
                                          .read(resourceRepositoryProvider)
                                          .restoreUnit(u.id),
                                      success: l10n.unitRestoredSnack(
                                        u.callSign,
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Symbols.undo_rounded),
                            )
                          else
                            IconButton(
                              key: ValueKey('retire-${u.id}'),
                              // Disabled buttons show no tooltip, so the
                              // reason goes in the one shown when enabled.
                              tooltip: u.isDispatchable
                                  ? l10n.retire
                                  : l10n.retireBusy,
                              onPressed: online && u.isDispatchable
                                  ? () => _retire(context, ref, u)
                                  : null,
                              icon: const Icon(Symbols.inventory_2_rounded),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _retire(
    BuildContext context,
    WidgetRef ref,
    ResponseUnit u,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.retireTitle(u.callSign)),
        content: SizedBox(width: 420, child: Text(l10n.retireBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.retire),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runAction(
      context,
      () => ref.read(resourceRepositoryProvider).retireUnit(u.id),
      success: l10n.unitRetiredSnack(u.callSign),
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({required this.units, required this.online});

  final List<ResponseUnit> units;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final inService = [
      for (final u in units)
        if (!u.retired) u,
    ]..sort((a, b) => a.callSign.compareTo(b.callSign));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.rosterTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.xs),
        Text(l10n.rosterNote, style: text.bodySmall),
        const SizedBox(height: SagipSpace.sm),
        AsyncBody(
          value: ref.watch(respondersProvider),
          isEmpty: (list) => list.isEmpty,
          empty: EmptyState(
            icon: Symbols.groups_rounded,
            title: l10n.rosterEmpty,
          ),
          builder: (responders) => TableCard(
            table: DataTable(
              columns: [
                DataColumn(label: Text(l10n.colAccount)),
                DataColumn(label: Text(l10n.colEmail)),
                DataColumn(label: Text(l10n.colUnit)),
              ],
              rows: [
                for (final s in responders)
                  DataRow(
                    cells: [
                      DataCell(Text(s.displayName)),
                      DataCell(Text(s.email)),
                      DataCell(
                        DropdownButton<String?>(
                          key: ValueKey('roster-${s.id}'),
                          value: inService.any((u) => u.id == s.unitId)
                              ? s.unitId
                              : null,
                          underline: const SizedBox.shrink(),
                          onChanged: online
                              ? (unitId) => runAction(
                                  context,
                                  () => ref
                                      .read(resourceRepositoryProvider)
                                      .setResponderUnit(s.id, unitId),
                                  success: l10n.rosterSaved,
                                )
                              : null,
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(l10n.noUnit),
                            ),
                            for (final u in inService)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text(u.callSign),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Add ([unit] null) or edit a unit. Checks the fields the way `save_unit`
/// does, so most mistakes are explained before anything is sent.
Future<void> showUnitDialog(
  BuildContext context,
  WidgetRef ref, {
  ResponseUnit? unit,
}) => showDialog<void>(
  context: context,
  builder: (context) => _UnitDialog(unit: unit, ref: ref),
);

class _UnitDialog extends StatefulWidget {
  const _UnitDialog({required this.unit, required this.ref});

  final ResponseUnit? unit;
  final WidgetRef ref;

  @override
  State<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<_UnitDialog> {
  late final _callSign = TextEditingController(text: widget.unit?.callSign);
  late final _station = TextEditingController(text: widget.unit?.station);
  late final _crew = TextEditingController(
    text: widget.unit == null ? '' : '${widget.unit!.crewSize}',
  );
  late UnitType _type = widget.unit?.type ?? UnitType.rescueTeam;
  var _tried = false;
  var _busy = false;

  static final _callSignPattern = RegExp(r'^[A-Z0-9][A-Z0-9-]{0,11}$');

  @override
  void dispose() {
    _callSign.dispose();
    _station.dispose();
    _crew.dispose();
    super.dispose();
  }

  String? _callSignError(AppLocalizations l10n) =>
      _callSignPattern.hasMatch(_callSign.text.trim().toUpperCase())
      ? null
      : l10n.fieldCallSignError;

  String? _stationError(AppLocalizations l10n) {
    final s = _station.text.trim();
    return s.isEmpty || s.length > 80 ? l10n.fieldStationError : null;
  }

  String? _crewError(AppLocalizations l10n) {
    final n = int.tryParse(_crew.text.trim());
    return n == null || n < 1 || n > 50 ? l10n.fieldCrewError : null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _tried = true);
    if (_callSignError(l10n) != null ||
        _stationError(l10n) != null ||
        _crewError(l10n) != null) {
      return;
    }
    setState(() => _busy = true);
    final callSign = _callSign.text.trim().toUpperCase();
    final ok = await runAction(
      context,
      () => widget.ref
          .read(resourceRepositoryProvider)
          .saveUnit(
            id: widget.unit?.id,
            callSign: callSign,
            type: _type,
            station: _station.text.trim(),
            crewSize: int.parse(_crew.text.trim()),
          ),
      success: l10n.unitSaved(callSign),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.unit == null ? l10n.addUnit : l10n.editUnit),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('unit-call-sign'),
              controller: _callSign,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.fieldCallSign,
                hintText: l10n.fieldCallSignHint,
                errorText: _tried ? _callSignError(l10n) : null,
              ),
            ),
            const SizedBox(height: SagipSpace.md),
            DropdownButtonFormField<UnitType>(
              key: const ValueKey('unit-type'),
              initialValue: _type,
              decoration: InputDecoration(labelText: l10n.fieldUnitType),
              items: [
                for (final t in UnitType.values)
                  DropdownMenuItem(value: t, child: Text(l10n.unitType(t))),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
            const SizedBox(height: SagipSpace.md),
            TextField(
              key: const ValueKey('unit-station'),
              controller: _station,
              decoration: InputDecoration(
                labelText: l10n.fieldStation,
                hintText: l10n.fieldStationHint,
                errorText: _tried ? _stationError(l10n) : null,
              ),
            ),
            const SizedBox(height: SagipSpace.md),
            TextField(
              key: const ValueKey('unit-crew'),
              controller: _crew,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.fieldCrew,
                errorText: _tried ? _crewError(l10n) : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
