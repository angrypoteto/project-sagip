import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/enums.dart';
import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';

/// F1's three-way status control: Available, En route, On scene (FR9).
/// 56 dp tall so it works with gloves (design skill). The selected segment
/// uses the tone's tint and text colors, which pass WCAG AA. Moves the
/// phone refuses still call [onSelected]; the screen explains why.
class UnitStatusControl extends StatelessWidget {
  const UnitStatusControl({
    super.key,
    required this.value,
    required this.labels,
    required this.onSelected,
  });

  final UnitStatus value;

  /// From the app's l10n file.
  final Map<UnitStatus, String> labels;
  final ValueChanged<UnitStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: p.hairlineStrong),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in UnitStatus.values)
            Expanded(
              child: _Segment(
                status: s,
                label: labels[s] ?? s.name,
                selected: s == value,
                onTap: () => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.status,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final UnitStatus status;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final (tone, icon) = switch (status) {
      UnitStatus.available => (p.success, Symbols.check_circle_rounded),
      UnitStatus.enRoute => (p.info, Symbols.navigation_rounded),
      UnitStatus.onScene => (p.onScene, Symbols.location_on_rounded),
    };
    final color = selected ? tone.text : p.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? tone.tint : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: tone.text, width: 3),
                    ),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color, fill: selected ? 1 : 0),
                const SizedBox(width: SagipSpace.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge!.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero ETA (design skill: "hero number (ETA, counts) 48/700"): a small
/// label, a large tabular number, and an optional caption such as the unit.
class EtaHero extends StatelessWidget {
  const EtaHero({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone,
  });

  /// For example "Arriving in about".
  final String label;

  /// For example "7 min".
  final String value;

  /// For example "R-03 · Rescue boat".
  final String? caption;

  /// Draws a tinted card in this tone; null draws plain text.
  final SagipTone? tone;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final fg = tone?.text ?? p.textPrimary;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: text.bodyMedium!.copyWith(
            color: tone?.text ?? p.textSecondary,
          ),
        ),
        Text(
          value,
          style: text.displaySmall!.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null)
          Text(caption!, style: text.titleSmall!.copyWith(color: fg)),
      ],
    );
    if (tone == null) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone!.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}
