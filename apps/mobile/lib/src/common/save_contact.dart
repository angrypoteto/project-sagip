import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';

// Texts from the gateway SIM show its number: a SIM cannot send under a
// name. Saved to the phone's contacts, they show "Project S.A.G.I.P."
// instead (Joshua, 2026-10-28).

/// Opens the phone's contacts app with the gateway SIM (mobile) and the
/// hotline (work) filled in. Does nothing while the gateway number is
/// unknown.
Future<void> saveSagipContact(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final gateway = ref.read(smsGatewayProvider);
  if (gateway.isEmpty) return;
  final hotline = ref.read(hotlineProvider);
  final opened = await ref
      .read(contactSaverProvider)
      .save(
        name: l10n.contactName,
        company: l10n.contactCompany,
        mobile: dialable(gateway),
        otherNumber: hotline.isEmpty ? null : dialable(hotline),
      );
  if (opened) {
    ref.read(contactOfferedProvider.notifier).done(gateway);
  } else {
    messenger.showSnackBar(SnackBar(content: Text(l10n.contactOpenFailed)));
  }
}

/// The offer at the top of Alerts, until it is saved or put off ("Not
/// now"); again when A3's gateway number changes. Nothing while the number
/// is unknown.
class SaveContactCard extends ConsumerWidget {
  const SaveContactCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(smsGatewayProvider);
    if (gateway.isEmpty || ref.watch(contactOfferedProvider) == gateway) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SagipSpace.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.panelRaised,
          border: Border.all(color: p.hairline),
          borderRadius: BorderRadius.circular(SagipRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.lg,
            SagipSpace.lg,
            SagipSpace.sm,
            SagipSpace.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.contact_phone_rounded, color: p.info.text),
                  const SizedBox(width: SagipSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.contactCardTitle, style: text.titleSmall),
                        const SizedBox(height: SagipSpace.xs),
                        Text(
                          l10n.contactCardBody,
                          style: text.bodyMedium!.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Side by side when they fit; stacked on a narrow phone or
              // with large text.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        ref.read(contactOfferedProvider.notifier).done(gateway),
                    child: Text(l10n.contactNotNow),
                  ),
                  TextButton(
                    onPressed: () => saveSagipContact(context, ref),
                    child: Text(l10n.contactSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
