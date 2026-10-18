import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/safe_place.dart';
import '../theme/sagip_colors.dart';
import '../theme/sagip_palette.dart';

/// The icon for a kind of safe place (both apps).
IconData safePlaceIcon(SafePlaceKind kind) => switch (kind) {
  SafePlaceKind.evacuationCenter => Symbols.night_shelter_rounded,
  SafePlaceKind.school => Symbols.school_rounded,
  SafePlaceKind.barangayHall => Symbols.account_balance_rounded,
  SafePlaceKind.coveredCourt => Symbols.roofing_rounded,
  SafePlaceKind.basketballCourt => Symbols.sports_basketball_rounded,
  SafePlaceKind.openSpace => Symbols.park_rounded,
  SafePlaceKind.hospital => Symbols.local_hospital_rounded,
};

/// A safe place on a map: a verdant ring with the kind's icon, filled for
/// an evacuation center MDRRMD designated. Round, so it is never mistaken
/// for a unit (a square).
class SafePlaceMarker extends StatelessWidget {
  const SafePlaceMarker({
    super.key,
    required this.kind,
    required this.label,
    this.official = false,
    this.selected = false,
    this.size = 24,
  });

  final SafePlaceKind kind;

  /// What the place is called, read out and shown on hover.
  final String label;
  final bool official;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final filled = official || selected;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: filled ? p.success.fill : p.canvas,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled ? p.canvas : p.success.fill,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: p.success.fill.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            safePlaceIcon(kind),
            size: size * 0.6,
            color: filled ? SagipColors.bay : p.success.text,
          ),
        ),
      ),
    );
  }
}
