import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/incident_type_grid.dart';
import '../../l10n/app_localizations.dart';

/// Right after an SOS is sent: one optional question, "What's happening?",
/// answered with one tap or skipped (Joshua, 2026-10-16). The SOS has
/// already gone, so it never slows the request for help; the type tells the
/// dispatcher what to send, and lets a flood, fire, or collapse go on the
/// MDRRMD Facebook Page once a unit is on the way. Returns the type, or
/// null when skipped.
Future<IncidentType?> showWhatsHappeningSheet(BuildContext context) =>
    showModalBottomSheet<IncidentType>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _WhatsHappeningSheet(),
    );

class _WhatsHappeningSheet extends StatelessWidget {
  const _WhatsHappeningSheet();

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
        SagipSpace.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.detailsType, style: text.titleLarge),
            const SizedBox(height: SagipSpace.xs),
            Text(
              l10n.whatsHappeningBody,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: SagipSpace.lg),
            IncidentTypeGrid(
              selected: null,
              onSelected: (t) => Navigator.pop(context, t),
            ),
            const SizedBox(height: SagipSpace.sm),
            TextButton(
              key: const ValueKey('whats-happening-skip'),
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.skip),
            ),
          ],
        ),
      ),
    );
  }
}
