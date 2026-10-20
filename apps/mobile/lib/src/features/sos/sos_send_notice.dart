import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';

/// The words for the phone notification of a waiting SOS, one step at a
/// time: data, then SMS, then Bluetooth (Joshua, 2026-10-19).
({String title, String text}) sosSendWords(
  AppLocalizations l10n,
  SosSendSteps steps,
) => switch (steps.current) {
  SosSendStep.data => (
    title: l10n.sosSendDataTitle,
    text: l10n.sosSendDataText,
  ),
  SosSendStep.sms when steps.smsReceived => (
    title: l10n.sosSendReceivedTitle,
    text: l10n.sosSendReceivedText(steps.smsReceivedAs!),
  ),
  SosSendStep.sms when steps.smsSent => (
    title: l10n.sosSendSmsTitle,
    text: l10n.sosSendSmsText,
  ),
  SosSendStep.sms => (
    title: l10n.sosSendSmsFailedTitle,
    text: l10n.sosSendSmsFailedText,
  ),
  SosSendStep.bluetooth when steps.bluetoothOff => (
    title: l10n.sosSendBluetoothOffTitle,
    text: steps.smsSent
        ? l10n.sosSendBluetoothOffAfterSms
        : l10n.sosSendBluetoothOffText,
  ),
  SosSendStep.bluetooth => (
    title: l10n.sosSendBluetoothTitle,
    text: steps.smsSent
        ? l10n.sosSendBluetoothAfterSms
        : steps.smsFailed
        ? l10n.sosSendBluetoothText
        : l10n.sosSendBluetoothNoSms,
  ),
};

/// Keeps the one notification in step with the resident's waiting SOS. It
/// is shown again only when the step changes, so it does not ring on every
/// data try. An SOS that went out at once gets none: R2 already shows it.
class SosSendNotifier {
  SosSendNotifier(this._notice);

  final SosSendNotice _notice;
  String? _id;
  String? _shown;

  /// SOS the gateway's reply already said MDRRMD has: the later delivery
  /// over data is not announced again.
  final _received = <String>{};

  /// The resident's records still on the phone changed.
  void pendingChanged(List<QueuedRecord> pending, AppLocalizations l10n) {
    final sos = [
      for (final r in pending)
        if (r.kind == QueuedKind.sos && r.waitedOffline && r.steps != null) r,
    ];
    final open = sos.where((r) => r.delivery.isPending).lastOrNull;
    if (open != null) {
      final words = sosSendWords(l10n, open.steps!);
      final key = '${open.id} ${words.title} ${words.text}';
      if (key == _shown) return;
      _id = open.id;
      _shown = key;
      final received = open.steps!.smsReceived;
      if (received) _received.add(open.id);
      _notice.show(title: words.title, text: words.text, done: received);
      return;
    }
    final refused = sos
        .where((r) => r.id == _id && r.delivery == DeliveryState.rejected)
        .firstOrNull;
    if (refused != null) {
      _id = null;
      _shown = null;
      _notice.show(
        title: l10n.sosSendRejectedTitle,
        text: l10n.sosSendRejectedText,
        done: true,
      );
    }
  }

  /// The server confirmed a record; [time] is when it was captured.
  void delivered(QueuedRecord record, AppLocalizations l10n, String time) {
    if (record.kind != QueuedKind.sos || !record.waitedOffline) return;
    if (_received.remove(record.id)) return;
    _id = null;
    _shown = null;
    _notice.show(
      title: l10n.sosSendDeliveredTitle,
      text: l10n.sosSendDeliveredText(time),
      done: true,
    );
  }
}
