import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

enum PlaceholderKind {
  forecast,
  analytics,
  reports,
  accounts,
  resources,
  settings,
}

/// Honest stand-in for screens that come in later phases (plan section 7.8,
/// Tier 3 and Phase 4). Says what the page will do and when.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.kind});

  final PlaceholderKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, title, message) = switch (kind) {
      PlaceholderKind.forecast => (
        Symbols.radar_rounded,
        l10n.navForecast,
        l10n.placeholderForecast,
      ),
      PlaceholderKind.analytics => (
        Symbols.monitoring_rounded,
        l10n.navAnalytics,
        l10n.placeholderAnalytics,
      ),
      PlaceholderKind.reports => (
        Symbols.description_rounded,
        l10n.navReports,
        l10n.placeholderReports,
      ),
      PlaceholderKind.accounts => (
        Symbols.manage_accounts_rounded,
        l10n.navAccounts,
        l10n.placeholderAccounts,
      ),
      PlaceholderKind.resources => (
        Symbols.inventory_2_rounded,
        l10n.navResources,
        l10n.placeholderResources,
      ),
      PlaceholderKind.settings => (
        Symbols.tune_rounded,
        l10n.navSettings,
        l10n.placeholderSettings,
      ),
    };
    return EmptyState(
      icon: icon,
      title: l10n.comingSoonFor(title),
      message: message,
    );
  }
}
