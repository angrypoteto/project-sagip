import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';

/// R2 "Cancel SOS": the resident says why. Returns the reason, or null if
/// the sheet was closed. The SOS is closed by MDRRMD, never by this sheet.
Future<SosCancelReason?> showCancelSosSheet(BuildContext context) =>
    showModalBottomSheet<SosCancelReason>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _CancelSosSheet(),
    );

class _CancelSosSheet extends StatefulWidget {
  const _CancelSosSheet();

  @override
  State<_CancelSosSheet> createState() => _CancelSosSheetState();
}

class _CancelSosSheetState extends State<_CancelSosSheet> {
  SosCancelReason? _reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        0,
        SagipSpace.xl,
        SagipSpace.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.cancelSheetTitle, style: text.titleLarge),
            const SizedBox(height: SagipSpace.xs),
            Text(
              l10n.cancelSheetBody,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: SagipSpace.lg),
            for (final r in SosCancelReason.values)
              ListTile(
                key: ValueKey('cancel-${r.name}'),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 56,
                leading: Icon(
                  _reason == r
                      ? Symbols.radio_button_checked_rounded
                      : Symbols.radio_button_unchecked_rounded,
                  color: _reason == r ? p.info.text : p.textSecondary,
                ),
                title: Text(l10n.cancelReason(r)),
                selected: _reason == r,
                onTap: () => setState(() => _reason = r),
              ),
            const SizedBox(height: SagipSpace.lg),
            FilledButton(
              onPressed: _reason == null
                  ? null
                  : () => Navigator.pop(context, _reason),
              child: Text(l10n.cancelAsk),
            ),
            const SizedBox(height: SagipSpace.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancelKeep),
            ),
          ],
        ),
      ),
    );
  }
}
