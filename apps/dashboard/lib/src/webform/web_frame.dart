import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'browser/browser.dart';
import 'report_draft.dart';
import 'web_providers.dart';

/// The page frame of the resident web form: one narrow column (most
/// residents open it on a phone), the brand, and an offline line.
class WebFrame extends ConsumerWidget {
  const WebFrame({super.key, required this.children, this.trailing});

  final List<Widget> children;

  /// Header actions for a signed-in resident.
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final online = ref.watch(webIsOnlineProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!online) _OfflineLine(text: l10n.webOffline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(SagipSpace.xl),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const SagipMark(size: 32),
                              const SizedBox(width: SagipSpace.md),
                              Expanded(
                                child: Text(
                                  l10n.brandName,
                                  style: text.titleMedium,
                                ),
                              ),
                              ...?trailing,
                            ],
                          ),
                          const SizedBox(height: SagipSpace.xxl),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineLine extends StatelessWidget {
  const _OfflineLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: Color.alphaBlend(p.warning.tint, p.canvas),
        padding: const EdgeInsets.symmetric(
          horizontal: SagipSpace.xl,
          vertical: SagipSpace.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.cloud_off_rounded, size: 20, color: p.warning.text),
            const SizedBox(width: SagipSpace.sm),
            Flexible(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: p.warning.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on every page of the web form (plan 7.2 W1, W2): an SOS cannot be
/// sent here, and where to turn in an emergency.
class SosNotice extends ConsumerWidget {
  const SosNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final config = ref.watch(webConfigProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.hairlineStrong),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.emergency_rounded, color: p.critical.text),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    config.hotline.isEmpty
                        ? l10n.webSosNotice
                        : l10n.webSosNoticeHotline(config.hotline),
                    style: text.bodyMedium,
                  ),
                  if (config.appDownloadUrl.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => openLink(config.appDownloadUrl),
                      child: Text(l10n.webGetApp),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline message under a form: what happened and what to do.
class WebMessage extends StatelessWidget {
  const WebMessage({
    super.key,
    required this.text,
    required this.tone,
    this.icon = Symbols.error_rounded,
  });

  final String text;
  final SagipTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone.text),
          const SizedBox(width: SagipSpace.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: tone.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signs out and leaves nothing of the resident's in the browser.
Future<void> webSignOut(WidgetRef ref) async {
  ref.read(reportDraftProvider.notifier).clear();
  await ref.read(webAuthProvider).signOut();
}
