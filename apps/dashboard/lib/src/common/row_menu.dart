import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// One entry of a [RowMenu].
class RowAction {
  const RowAction({
    required this.key,
    required this.icon,
    required this.label,
    this.onSelected,
    this.note,
  });

  final Key key;
  final IconData icon;
  final String label;

  /// Null: shown greyed out, with [note] saying why.
  final VoidCallback? onSelected;
  final String? note;
}

/// The "More" button at the end of a table row (2026-11-11). Actions that
/// take something away (deactivate, retire, reset a password) sit here,
/// named, instead of as small icons beside Edit where a slip of the mouse
/// reached them.
class RowMenu extends StatelessWidget {
  const RowMenu({super.key, required this.actions});

  final List<RowAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return PopupMenuButton<int>(
      tooltip: l10n.moreActions,
      icon: const Icon(Symbols.more_vert_rounded),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
      onSelected: (i) => actions[i].onSelected?.call(),
      itemBuilder: (context) => [
        for (final (i, a) in actions.indexed)
          PopupMenuItem<int>(
            key: a.key,
            value: i,
            enabled: a.onSelected != null,
            child: Row(
              children: [
                Icon(a.icon, size: 20),
                const SizedBox(width: SagipSpace.md),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.label),
                      if (a.note != null && a.onSelected == null)
                        Text(
                          a.note!,
                          style: text.bodySmall!.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
