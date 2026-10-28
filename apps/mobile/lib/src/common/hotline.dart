import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

/// What every "Call MDRRMD" button does (Joshua, 2026-10-28: call, not only
/// show the number): calls the hotline at once (the first tap asks for the
/// phone-call permission; refused, the dialer opens with the number typed).
/// With no hotline set yet, or on a device that cannot call, it shows
/// [showHotlineDialog] instead.
Future<void> callMdrrmd(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final number = container.read(hotlineProvider);
  if (number.isEmpty) return showHotlineDialog(context);
  final outcome = await container
      .read(phoneCallerProvider)
      .call(dialable(number));
  if (outcome == CallOutcome.unavailable && context.mounted) {
    await showHotlineDialog(context);
  }
}

/// The MDRRMD hotline: the number an administrator set on A3 (or one fixed
/// at build time with `--dart-define=MDRRMD_HOTLINE=...`). Until MDRRMD's
/// number is set the dialog says so instead of showing a made-up number.
Future<void> showHotlineDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final mdrrmdHotline = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(hotlineProvider);
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
              onPressed: () => callMdrrmd(context),
              icon: const Icon(Symbols.call_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
