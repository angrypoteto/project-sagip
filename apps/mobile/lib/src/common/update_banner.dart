import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// "A newer S.A.G.I.P. is out" on every tab (Joshua, 2026-10-19), under the
/// offline banner. Update opens the download; Later hides it until the app
/// is opened again. Hidden in an emergency ([newerBuildProvider]).
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Someone may have installed the update and come back.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(latestBuildProvider.notifier).check(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _download() async {
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

  @override
  Widget build(BuildContext context) {
    final newer = ref.watch(newerBuildProvider);
    return AnimatedSize(
      duration: SagipMotion.base,
      curve: SagipMotion.enter,
      alignment: Alignment.topCenter,
      child: newer == null
          ? const SizedBox(width: double.infinity)
          : _Bar(
              newer: newer,
              onUpdate: _download,
              onLater: () =>
                  ref.read(updateLaterProvider.notifier).later(newer),
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.newer,
    required this.onUpdate,
    required this.onLater,
  });

  final int newer;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('update-banner'),
      color: p.info.tint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SagipSpace.xl,
          SagipSpace.md,
          SagipSpace.sm,
          SagipSpace.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.system_update_rounded,
                  size: 20,
                  color: p.info.text,
                ),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.updateNewerTitle,
                        style: text.bodyMedium!.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.updateNewerText(newer, appBuild),
                        style: text.bodySmall!.copyWith(
                          color: p.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('update-later'),
                  onPressed: onLater,
                  child: Text(l10n.updateLater),
                ),
                TextButton(
                  key: const ValueKey('update-now'),
                  onPressed: onUpdate,
                  child: Text(l10n.updateNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
