import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Screens that later build steps fill in.
enum ComingScreen { alerts, history, activity, vulnerability }

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.screen,
    required this.icon,
    this.standalone = false,
  });

  final ComingScreen screen;
  final IconData icon;

  /// Opened on its own (not as a tab), so it needs a Scaffold and a way back.
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = switch (screen) {
      ComingScreen.alerts => l10n.screenAlerts,
      ComingScreen.history => l10n.screenHistory,
      ComingScreen.activity => l10n.myActivity,
      ComingScreen.vulnerability => l10n.vulnerabilityProfile,
    };
    final body = EmptyState(
      icon: icon,
      title: l10n.comingTitle(name),
      message: l10n.comingBody,
    );
    return standalone
        ? Scaffold(
            appBar: AppBar(title: Text(name)),
            body: body,
          )
        : body;
  }
}
