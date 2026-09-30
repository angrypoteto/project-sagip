import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// G1: also shown when a dispatcher opens an admin URL, so admin pages stay
/// hidden rather than visibly locked.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: SagipPalette.of(context).canvas,
      child: EmptyState(
        icon: Symbols.explore_off_rounded,
        title: l10n.notFoundTitle,
        message: l10n.notFoundBody,
        action: OutlinedButton(
          onPressed: () => context.go(Routes.board),
          child: Text(l10n.backToBoard),
        ),
      ),
    );
  }
}
