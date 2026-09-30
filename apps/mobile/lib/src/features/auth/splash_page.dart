import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/brand.dart';
import '../../l10n/app_localizations.dart';

/// S1 Splash: shown while the saved session is checked. The router moves on
/// as soon as it knows who is signed in.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SagipMark(size: 96),
            const SizedBox(height: SagipSpace.xl),
            Text(l10n.appTitle, style: text.headlineSmall),
            const SizedBox(height: SagipSpace.sm),
            Text(
              l10n.starting,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
