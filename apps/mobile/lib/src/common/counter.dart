import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// A large minus/plus counter, usable with gloves. The buttons carry
/// tooltips so screen readers can name them.
class Counter extends StatelessWidget {
  const Counter({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.minimum = 0,
  });

  final int value;

  /// The value in words, for example "3 people".
  final String label;
  final ValueChanged<int> onChanged;
  final int minimum;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton.outlined(
          iconSize: 28,
          tooltip: l10n.fewerPeople,
          onPressed: value > minimum ? () => onChanged(value - 1) : null,
          icon: const Icon(Symbols.remove_rounded),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: text.titleLarge!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton.outlined(
          iconSize: 28,
          tooltip: l10n.morePeople,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Symbols.add_rounded),
        ),
      ],
    );
  }
}
