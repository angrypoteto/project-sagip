import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// What a unit carries (unit inventory): shared by the Inventory page and
// the responder's own page.

/// Tone and icon for a supply's state. The icon and the word carry it;
/// color is never the only cue.
(SagipTone, IconData) supplyVisual(SupplyState state, SagipPalette p) =>
    switch (state) {
      SupplyState.ok => (p.success, Symbols.check_circle_rounded),
      SupplyState.low => (p.warning, Symbols.warning_rounded),
      SupplyState.out => (p.critical, Symbols.error_rounded),
    };

IconData supplyIcon(SupplyItem item) => switch (item) {
  SupplyItem.fuel => Symbols.local_gas_station_rounded,
  SupplyItem.tankWater => Symbols.water_rounded,
  SupplyItem.drinkingWater => Symbols.water_bottle_rounded,
  SupplyItem.medicalKits => Symbols.medical_services_rounded,
  SupplyItem.lifeVests => Symbols.pool_rounded,
  SupplyItem.rescueGear => Symbols.handyman_rounded,
};

/// One supply as a line: its name, how much, a bar, and its state.
class SupplyLine extends StatelessWidget {
  const SupplyLine({
    super.key,
    required this.supply,
    required this.lowPercent,
    required this.now,
  });

  final UnitSupply supply;
  final double lowPercent;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final state = supply.stateAt(lowPercent);
    final (tone, icon) = supplyVisual(state, p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(supplyIcon(supply.item), size: 18, color: p.textSecondary),
              const SizedBox(width: SagipSpace.sm),
              Expanded(
                child: Text(
                  l10n.supplyItem(supply.item),
                  style: text.titleSmall,
                ),
              ),
              Text(
                l10n.supplyAmount(supply),
                style: text.titleSmall!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: SagipSpace.md),
              SagipChip(label: l10n.supplyState(state), tone: tone, icon: icon),
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: supply.level,
              minHeight: 8,
              backgroundColor: p.panelRaised,
              color: tone.fill,
            ),
          ),
          const SizedBox(height: SagipSpace.xs),
          Text(
            [
              l10n.suppliesUpdated(
                formatDateTime(supply.updatedAt, locale),
                supply.updatedByName,
              ),
              if (supply.isStale(now)) l10n.suppliesOld,
            ].join(' · '),
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// One supply in an Inventory cell: how much, plain when enough, a chip
/// when low or out (icon and word, never color alone), a dash when the
/// crew has not reported it.
class SupplyAmount extends StatelessWidget {
  const SupplyAmount({
    super.key,
    required this.supply,
    required this.lowPercent,
  });

  final UnitSupply? supply;
  final double lowPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final s = supply;
    if (s == null) {
      return Semantics(
        label: l10n.suppliesNotReported,
        child: Text(
          '–',
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
      );
    }
    final state = s.stateAt(lowPercent);
    final amount = l10n.supplyAmount(s);
    if (state == SupplyState.ok) {
      return Text(
        amount,
        style: text.bodyMedium!.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    final (tone, icon) = supplyVisual(state, p);
    return SagipChip(
      label: '${l10n.supplyState(state)} · $amount',
      tone: tone,
      icon: icon,
    );
  }
}

/// Everything one unit carries, each with its level and when it was
/// reported. Read-only: only the unit's own crew changes it.
class SuppliesDialog extends ConsumerWidget {
  const SuppliesDialog({super.key, required this.unitId});

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
