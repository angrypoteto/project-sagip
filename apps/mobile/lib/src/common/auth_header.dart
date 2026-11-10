import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// The head of the sign-in and sign-up screens (Joshua, 2026-11-10): MDRRMD's
/// seal, which eases in and pulses while [busy], then the name and the
/// city's motto, centered. [sealKey] lets [SealFlightLauncher] start the
/// flight from the seal once a sign-in is accepted.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.sealKey,
    this.busy = false,
    this.size = 64,
  });

  final GlobalKey sealKey;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SealEntrance(key: sealKey, busy: busy, size: size),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.brandName,
          style: text.titleMedium!.copyWith(letterSpacing: 0.5),
          textAlign: TextAlign.center,
        ),
        Text(
          l10n.cityMotto,
          style: text.labelMedium!.copyWith(
            color: p.textSecondary,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
