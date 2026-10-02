import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

enum PlaceholderKind { reports }

/// Honest stand-in for screens that come in later phases (plan section 7.8,
/// Tier 3 and Phase 4). Says what the page will do and when.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.kind});

  final PlaceholderKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, message) = switch (kind) {
      PlaceholderKind.reports => (
        Symbols.description_rounded,
        l10n.navReports,
        l10n.placeholderReports,
      ),
    };
    return EmptyState(
      icon: icon,
      title: l10n.comingSoonFor(title),
      message: message,
    );
  }
}
