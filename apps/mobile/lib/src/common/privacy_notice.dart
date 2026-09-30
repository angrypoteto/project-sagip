import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// The plain-language privacy notice (RA 10173), shown from S4, S7, and
/// R10. The wording is a draft for the team and MDRRMD to review.
class PrivacyNotice extends StatelessWidget {
  const PrivacyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final sections = [
      (l10n.privacyCollectTitle, l10n.privacyCollectBody),
      (l10n.privacyWhyTitle, l10n.privacyWhyBody),
      (l10n.privacyWhoTitle, l10n.privacyWhoBody),
      (l10n.privacyKeepTitle, l10n.privacyKeepBody),
      (l10n.privacyRightsTitle, l10n.privacyRightsBody),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, body) in sections) ...[
          Text(title, style: text.titleSmall),
          const SizedBox(height: SagipSpace.xs),
          Text(body, style: text.bodyMedium),
          const SizedBox(height: SagipSpace.lg),
        ],
      ],
    );
  }
}

Future<void> showPrivacyNotice(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            0,
            SagipSpace.xl,
            SagipSpace.xl,
          ),
          children: [
            Text(
              AppLocalizations.of(context).privacyTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: SagipSpace.lg),
            const PrivacyNotice(),
          ],
        ),
      ),
    );
