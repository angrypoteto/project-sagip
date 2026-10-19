import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_version.dart';
import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// "Update S.A.G.I.P." (Joshua, 2026-10-19): this app is older than the
/// server allows (A3, `app.min_build`). Everything else waits for the
/// update, except an emergency: a signed-in resident can still send an
/// SOS from here, and anyone can call MDRRMD.
class UpdatePage extends ConsumerWidget {
  const UpdatePage({super.key});

  Future<void> _download(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(appDownloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.updateOpenFailed)));
    }
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fix = ref.read(locationProvider).value?.lastFix;
      final sos = await ref.read(sosRepositoryProvider).send(fix: fix);
      if (context.mounted) context.go(Routes.sosJustSent(sos.clientId));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.sosSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final user = ref.watch(currentUserProvider).value;
    final resident = user?.role == UserRole.resident;
    final active = resident ? ref.watch(activeSosProvider) : null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            SagipSpace.x3,
            SagipSpace.xl,
            SagipSpace.xl,
          ),
          children: [
            Icon(Symbols.system_update_rounded, size: 48, color: p.info.text),
            const SizedBox(height: SagipSpace.lg),
            Text(l10n.updateTitle, style: text.headlineMedium),
            const SizedBox(height: SagipSpace.sm),
            Text(l10n.updateBody, style: text.bodyLarge),
            const SizedBox(height: SagipSpace.xl),
            FilledButton.icon(
              key: const ValueKey('update-download'),
              onPressed: () => _download(context),
              icon: const Icon(Symbols.download_rounded),
              label: Text(l10n.updateDownload),
            ),
            const SizedBox(height: SagipSpace.sm),
            SelectableText(
              l10n.updateLink(appDownloadUrl),
              style: text.bodySmall!.copyWith(color: p.textSecondary),
            ),
            if (resident) ...[
              const SizedBox(height: SagipSpace.x3),
              Text(
                l10n.updateSosStill,
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SagipSpace.lg),
              Center(
                child: SosButton(
                  phase: sosPhase(active),
                  semanticLabel: active == null
                      ? l10n.sosSemantic
                      : l10n.sosOpenSemantic,
                  onSend: () => _send(context, ref),
                  onOpen: active == null
                      ? null
                      : () => context.go(Routes.sos(active.clientId)),
                ),
              ),
            ],
            const SizedBox(height: SagipSpace.xl),
            OutlinedButton.icon(
              onPressed: () => showHotlineDialog(context),
              icon: const Icon(Symbols.call_rounded),
              label: Text(l10n.callMdrrmd),
            ),
          ],
        ),
      ),
    );
  }
}
