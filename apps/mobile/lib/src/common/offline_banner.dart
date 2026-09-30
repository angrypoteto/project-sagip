import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../features/queue/queue_sheet.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';

/// The connectivity banner shown on every screen (plan 7.6). Hidden while
/// online with nothing waiting; "Back online" for 4 seconds after a
/// reconnect. Tapping it opens the offline queue (S6).
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  static const _backOnlineFor = Duration(seconds: 4);
  Timer? _backOnline;

  @override
  void dispose() {
    _backOnline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(signalProvider, (prev, next) {
      final was = prev?.value;
      if (next.value == SignalState.internet &&
          was != null &&
          was != SignalState.internet) {
        setState(() {
          _backOnline?.cancel();
          _backOnline = Timer(_backOnlineFor, () {
            if (mounted) setState(() => _backOnline = null);
          });
        });
      }
    });

    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final waiting = ref.watch(pendingQueueProvider).value?.length ?? 0;
    final justReconnected = _backOnline?.isActive ?? false;

    final (String? message, IconData icon, SagipTone? tone) = switch (signal) {
      SignalState.smsOnly => (
        waiting > 0 ? l10n.bannerOfflineWaiting(waiting) : l10n.bannerSmsOnly,
        Symbols.cloud_off_rounded,
        null,
      ),
      SignalState.noSignal => (
        waiting > 0 ? l10n.bannerOfflineWaiting(waiting) : l10n.bannerNoSignal,
        Symbols.signal_disconnected_rounded,
        null,
      ),
      SignalState.internet when waiting > 0 => (
        l10n.bannerSending(waiting),
        Symbols.cloud_upload_rounded,
        p.info,
      ),
      SignalState.internet when justReconnected => (
        l10n.bannerBackOnline,
        Symbols.cloud_done_rounded,
        p.success,
      ),
      SignalState.internet => (null, Symbols.cloud_done_rounded, null),
    };

    return AnimatedSize(
      duration: SagipMotion.base,
      curve: SagipMotion.enter,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : ConnectivityBanner(
              message: message,
              icon: icon,
              tone: tone,
              onTap: () => showQueueSheet(context),
            ),
    );
  }
}
