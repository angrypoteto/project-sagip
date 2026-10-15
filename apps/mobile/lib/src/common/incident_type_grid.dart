import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'labels.dart';

/// The four incident types as large buttons, two by two: one tap tells the
/// responders what kind of emergency it is (Joshua, 2026-10-16). Used right
/// after an SOS is sent and at the top of "Add details".
class IncidentTypeGrid extends StatelessWidget {
  const IncidentTypeGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final IncidentType? selected;

  /// The tapped type, or null when the selected one is tapped again.
  final ValueChanged<IncidentType?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    Widget tile(IncidentType t) {
      final on = selected == t;
      return Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? p.info.tint : p.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SagipRadius.card),
            side: BorderSide(
              color: on ? p.info.fill : p.hairlineStrong,
              width: on ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: ValueKey('type-${t.name}'),
            borderRadius: BorderRadius.circular(SagipRadius.card),
            onTap: () => onSelected(on ? null : t),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Padding(
                padding: const EdgeInsets.all(SagipSpace.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      incidentTypeIcon(t),
                      size: 30,
                      color: on ? p.info.text : p.textPrimary,
                      fill: on ? 1 : 0,
                    ),
                    const SizedBox(height: SagipSpace.xs),
                    Text(
                      l10n.incidentType(t),
                      textAlign: TextAlign.center,
                      style: text.titleSmall!.copyWith(
                        color: on ? p.info.text : p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    const types = IncidentType.values;
    return Column(
      children: [
        for (var row = 0; row < types.length; row += 2) ...[
          if (row > 0) const SizedBox(height: SagipSpace.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(types[row])),
                const SizedBox(width: SagipSpace.sm),
                Expanded(
                  child: row + 1 < types.length
                      ? tile(types[row + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
