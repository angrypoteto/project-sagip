import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// S6: what is saved on the phone and not yet confirmed by the server.
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => const QueueSheet(),
);

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final records = ref.watch(pendingQueueProvider).value ?? const [];
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final caps = ref.watch(capabilitiesProvider);
    final locale = Localizations.localeOf(context).toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xl,
        0,
        SagipSpace.xl,
        SagipSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.queueTitle, style: text.titleLarge),
          const SizedBox(height: SagipSpace.sm),
          Text(switch (signal) {
            SignalState.internet => l10n.queueNextInternet,
            SignalState.smsOnly =>
              caps.smsTier ? l10n.queueNextSms : l10n.queueNextWait,
            SignalState.noSignal =>
              caps.relayTier ? l10n.queueNextNone : l10n.queueNextWait,
          }, style: text.bodyMedium!.copyWith(color: p.textSecondary)),
          const SizedBox(height: SagipSpace.lg),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SagipSpace.xxl),
              child: EmptyState(
                icon: Symbols.cloud_done_rounded,
                title: l10n.queueEmpty,
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: records.length,
                separatorBuilder: (_, _) => Divider(color: p.hairline),
                itemBuilder: (context, i) {
                  final r = records[i];
                  return _QueueRow(record: r, locale: locale);
                },
              ),
            ),
          const SizedBox(height: SagipSpace.lg),
          if (records.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => ref.read(offlineQueueProvider).retryNow(),
              icon: const Icon(Symbols.refresh_rounded),
              label: Text(l10n.queueTryNow),
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.record, required this.locale});

  final QueuedRecord record;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final rejected = record.delivery == DeliveryState.rejected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            record.kind == QueuedKind.sos
                ? Symbols.sos_rounded
                : Symbols.description_rounded,
            color: record.kind == QueuedKind.sos
                ? p.critical.text
                : p.textSecondary,
          ),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.queuedKind(record.kind), style: text.titleSmall),
                const SizedBox(height: SagipSpace.xs),
                Text(
                  l10n.queueCaptured(formatTime(record.capturedAt, locale)),
                  style: text.bodySmall!.copyWith(color: p.textSecondary),
                ),
                if (rejected && record.rejectReason != null) ...[
                  const SizedBox(height: SagipSpace.xs),
                  Text(
                    record.rejectReason!,
                    style: text.bodySmall!.copyWith(color: p.critical.text),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: SagipSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DeliveryBadge(
                state: record.delivery,
                label: l10n.delivery(record.delivery),
              ),
              if (rejected)
                TextButton(
                  onPressed: () =>
                      ref.read(offlineQueueProvider).remove(record.id),
                  child: Text(l10n.queueRemove),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
