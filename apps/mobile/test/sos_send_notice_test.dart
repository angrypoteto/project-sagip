import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/features/sos/sos_send_notice.dart';
import 'package:sagip_mobile/src/l10n/app_localizations.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The phone notification for a waiting SOS (Joshua, 2026-10-19): one per
/// step, data, then SMS, then Bluetooth, and a last one when delivered.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final at = DateTime.utc(2026, 10, 19, 1, 0);
  late MockSosSendNotice notice;
  late SosSendNotifier notifier;

  QueuedRecord sos(
    SosSendSteps steps, {
    DeliveryState delivery = DeliveryState.savedOnPhone,
    bool waited = true,
  }) => QueuedRecord(
    id: 'sos-1',
    kind: QueuedKind.sos,
    capturedAt: at,
    delivery: delivery,
    waitedOffline: waited,
    steps: steps,
  );

  List<String> titles() => [for (final s in notice.shown) s.split(': ').first];

  setUp(() {
    notice = MockSosSendNotice();
    notifier = SosSendNotifier(notice);
  });

  test('one notification per step, not per data try', () {
    notifier.pendingChanged([sos(const SosSendSteps())], l10n);
    notifier.pendingChanged([sos(const SosSendSteps())], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(smsSent: true), delivery: DeliveryState.sending),
    ], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(smsSent: true), delivery: DeliveryState.sentBySms),
    ], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(smsSent: true, bluetooth: true)),
    ], l10n);
    notifier.pendingChanged(const [], l10n);
    notifier.delivered(
      sos(
        const SosSendSteps(smsSent: true, bluetooth: true),
        delivery: DeliveryState.delivered,
      ),
      l10n,
      '9:00 AM',
    );
    expect(titles(), [
      'No internet. Trying again over data',
      'SOS sent by SMS to MDRRMD',
      'Asking nearby phones to pass on your SOS',
      'Your SOS reached MDRRMD',
    ]);
    expect(notice.shown[2], contains('Your SMS went out'));
    expect(notice.shown.last, contains('Sent at 9:00 AM'));
  });

  test('a failed text says so, then Bluetooth', () {
    notifier.pendingChanged([sos(const SosSendSteps(smsFailed: true))], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(smsFailed: true, bluetooth: true)),
    ], l10n);
    expect(titles(), [
      'The SMS could not be sent',
      'Asking nearby phones to pass on your SOS',
    ]);
    expect(notice.shown.first, contains('Turn on Bluetooth'));
    expect(notice.shown.last, contains('The SMS could not be sent'));
  });

  test('an SOS that went out at once gets no notification', () {
    notifier.pendingChanged([sos(const SosSendSteps(), waited: false)], l10n);
    notifier.delivered(
      sos(
        const SosSendSteps(),
        delivery: DeliveryState.delivered,
        waited: false,
      ),
      l10n,
      '9:00 AM',
    );
    expect(notice.shown, isEmpty);
  });

  test('the gateway\'s reply: "received by SMS", and no second notice when '
      'data delivers the rest', () {
    notifier.pendingChanged([
      sos(const SosSendSteps(smsSent: true, bluetooth: true)),
    ], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(smsSent: true, smsReceivedAs: 'INC-0181')),
    ], l10n);
    notifier.delivered(
      sos(const SosSendSteps(), delivery: DeliveryState.delivered),
      l10n,
      '9:00 AM',
    );
    expect(titles(), [
      'Asking nearby phones to pass on your SOS',
      'MDRRMD received your SOS by SMS',
    ]);
    expect(notice.shown.last, contains('INC-0181'));
  });

  test('a refused SOS says so', () {
    notifier.pendingChanged([sos(const SosSendSteps())], l10n);
    notifier.pendingChanged([
      sos(const SosSendSteps(), delivery: DeliveryState.rejected),
    ], l10n);
    expect(titles().last, 'Your SOS was not accepted');
  });

  test('Filipino words for every step', () {
    final fil = lookupAppLocalizations(const Locale('fil'));
    for (final steps in const [
      SosSendSteps(),
      SosSendSteps(smsSent: true),
      SosSendSteps(smsFailed: true),
      SosSendSteps(smsFailed: true, bluetooth: true),
      SosSendSteps(smsSent: true, bluetooth: true),
    ]) {
      final en = sosSendWords(l10n, steps);
      final tl = sosSendWords(fil, steps);
      expect(tl.title, isNot(en.title));
      expect(tl.text, isNotEmpty);
    }
  });
}
