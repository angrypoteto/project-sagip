import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Screens that later build steps fill in.
enum ComingScreen { alerts, history }

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.screen, required this.icon});

  final ComingScreen screen;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = switch (screen) {
      ComingScreen.alerts => l10n.screenAlerts,
      ComingScreen.history => l10n.screenHistory,
    };
    return EmptyState(
      icon: icon,
      title: l10n.comingTitle(name),
      message: l10n.comingBody,
    );
  }
}
