import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// The MDRRMD hotline, set at build time with
/// `--dart-define=MDRRMD_HOTLINE=...`. Empty until the Data role gets the
/// official number (plan section 6); the dialog says so instead of showing
/// a made-up number.
const mdrrmdHotline = String.fromEnvironment('MDRRMD_HOTLINE');

Future<void> showHotlineDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.hotlineTitle),
      content: mdrrmdHotline.isEmpty
          ? Text(l10n.hotlineMissing)
          : SelectableText(l10n.hotlineBody(mdrrmdHotline)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}

/// "In an emergency, call MDRRMD" with a call button (S3; plan: shown when
/// sign-in or SOS cannot work).
class HotlineCard extends StatelessWidget {
  const HotlineCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.hairlineStrong),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          children: [
            Icon(Symbols.emergency_rounded, color: p.critical.text),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Text(l10n.hotlineCardTitle, style: text.titleSmall),
            ),
            IconButton.filled(
              tooltip: l10n.callMdrrmd,
              // The app theme greys every icon button; this one sits on the
              // action fill, so it needs the light foreground.
              style: IconButton.styleFrom(
                backgroundColor: SagipColors.tideStrong,
                foregroundColor: SagipColors.porcelain,
              ),
              onPressed: () => showHotlineDialog(context),
              icon: const Icon(Symbols.call_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
