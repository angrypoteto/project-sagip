import 'package:material_ui/material_ui.dart';

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
