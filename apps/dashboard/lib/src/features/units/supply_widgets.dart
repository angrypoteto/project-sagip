import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';

// What a unit carries (unit inventory): shared by the dispatcher's Units
// page and the responder's own page.

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
