import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Records adverts; [supported] false is Bluetooth off.
class FakeRadio implements RelayRadio {
  final adverts = <String, Uint8List>{};
  var supported = true;

  @override
  Future<void> keepRunning(bool on) async {}

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> advertise(String key, Uint8List packet) async {
    if (!supported) return false;
    adverts[key] = packet;
    return true;
  }

  @override
  Future<void> stop(String key) async => adverts.remove(key);

  @override
  Stream<Uint8List> heard() => const Stream.empty();

  @override
  Future<void> showStatus({required int carrying, required int sent}) async {}
}

/// Sends nothing while [reachable] is false.
class FakeSender implements OutboxSender {
  var reachable = false;
  final sent = <String>[];

  @override
  Future<String?> send(OutboxEntry entry) async {
    if (!reachable) throw const ActionRejected(ActionRejection.offline);
    sent.add(entry.id);
    return 'INC-0300';
  }
}

/// [works] false is no cell service.
class FakeSms implements SmsSender {
  var works = true;
  final sent = <String>[];

  @override
  Future<bool> send(String number, String text) async {
    if (!works) return false;
    sent.add(text);
    return true;
  }
}

/// The order an SOS that could not go out is tried in (Joshua, 2026-10-19):
/// data first, then SMS, then Bluetooth.
void main() {
  final start = DateTime.utc(2026, 10, 19, 9, 0, 0);
  const id = '3f2a9c1e-7b4d-4e0a-9c2f-1a2b3c4d5e6f';
  late DateTime now;
  late FakeRadio radio;
  late FakeSender sender;
  late FakeSms sms;
  late MemoryLocalStore store;
  late StreamController<bool> online;
  late StreamController<bool> texting;
  late StreamController<bool> relayOk;
  late SyncEngine engine;

  SyncEngine make({
    DateTime Function()? clock,
    Duration dataWindow = const Duration(seconds: 20),
  }) => SyncEngine(
    store: store,
    sender: sender,
    online: online.stream,
    account: () => 'res-001',
    clock: clock ?? () => now,
    retryDelay: (_) => const Duration(hours: 1),
    sms: SmsTier(
      sender: sms,
      gatewayNumber: () => '09170000000',
      available: texting.stream,
      retryAfter: const Duration(hours: 1),
    ),
    relay: RelayTier(radio: radio, available: relayOk.stream),
    dataWindow: dataWindow,
  );

  OutboxEntry entry(DateTime at) => OutboxEntry(
    id: id,
    action: OutboxAction.sos,
    accountId: 'res-001',
    capturedAt: at,
    payload: SosRequest(
      clientId: id,
      capturedAt: at,
      delivery: DeliveryState.savedOnPhone,
      location: const GeoPoint(14.60917, 120.99251),
      accuracyMeters: 8,
    ).toJson(),
  );

  Future<void> signal({required bool internet}) async {
    online.add(internet);
    texting.add(!internet);
    relayOk.add(!internet);
    await pumpEventQueue();
  }

  Future<void> at(Duration after) async {
    now = start.add(after);
    await engine.retryNow();
    await pumpEventQueue();
  }

  OutboxEntry sosEntry() => engine.entries.single;

  setUp(() {
    now = start;
    radio = FakeRadio();
    sender = FakeSender();
    sms = FakeSms();
    store = MemoryLocalStore();
    online = StreamController<bool>.broadcast();
    texting = StreamController<bool>.broadcast();
    relayOk = StreamController<bool>.broadcast();
    engine = make();
  });

  tearDown(() => engine.dispose());

  test('no internet: data for 20 s, then SMS and Bluetooth at once; data '
      'keeps reconnecting; delivered later, the advert ends', () async {
    await signal(internet: false);
    await engine.add(entry(start));
    await pumpEventQueue();
    expect(sosEntry().steps!.current, SosSendStep.data);
    expect(sosEntry().waited, isTrue, reason: 'it could not go at once');
    expect(sms.sent, isEmpty);

    await at(const Duration(seconds: 19));
    expect(sms.sent, isEmpty, reason: 'still the data window');

    await at(const Duration(seconds: 20));
    expect(sms.sent, hasLength(1));
    expect(radio.adverts.keys, [
      RelayTier.ownKey(id),
    ], reason: 'no wait after the text');
    expect(sosEntry().steps!.current, SosSendStep.bluetooth);
    expect(sosEntry().steps!.smsSent, isTrue);
    expect(sosEntry().delivery, DeliveryState.sentBySms);

    await at(const Duration(minutes: 3));
    expect(sms.sent, hasLength(1), reason: 'a text that went is not repeated');
    expect(radio.adverts, hasLength(1));

    sender.reachable = true;
    await signal(internet: true);
    expect(sender.sent, [id]);
    expect(sosEntry().delivery, DeliveryState.delivered);
    expect(radio.adverts, isEmpty);
  });

  test('the text fails (no cell service): Bluetooth at once', () async {
    sms.works = false;
    await signal(internet: false);
    await engine.add(entry(start));
    await at(const Duration(seconds: 20));
    final steps = sosEntry().steps!;
    expect(steps.smsFailed, isTrue);
    expect(steps.current, SosSendStep.bluetooth);
    expect(sosEntry().delivery, DeliveryState.relaying);
    expect(radio.adverts.keys, [RelayTier.ownKey(id)]);
  });

  test('Bluetooth off too: the SOS waits, and the steps say so', () async {
    sms.works = false;
    radio.supported = false;
    await signal(internet: false);
    await engine.add(entry(start));
    await at(const Duration(seconds: 20));
    final steps = sosEntry().steps!;
    expect(steps.smsFailed, isTrue);
    expect(steps.bluetooth, isFalse);
    expect(sosEntry().delivery, DeliveryState.savedOnPhone);

    // Bluetooth turned on: the next try advertises it.
    radio.supported = true;
    await at(const Duration(seconds: 50));
    expect(radio.adverts.keys, [RelayTier.ownKey(id)]);
  });

  test(
    'while nearby phones are asked, data comes back and delivers it',
    () async {
      sms.works = false;
      await signal(internet: false);
      await engine.add(entry(start));
      await at(const Duration(seconds: 20));
      expect(sosEntry().steps!.current, SosSendStep.bluetooth);
      sender.reachable = true;
      await signal(internet: true);
      expect(sender.sent, [id]);
      expect(sosEntry().delivery, DeliveryState.delivered);
      expect(radio.adverts, isEmpty);
    },
  );

  test('online, but every send fails: after 20 s it is texted too', () async {
    await signal(internet: true);
    await engine.add(entry(start));
    await pumpEventQueue();
    expect(sosEntry().attempts, 1);
    expect(sosEntry().steps!.current, SosSendStep.data);

    await at(const Duration(seconds: 20));
    expect(sms.sent, hasLength(1), reason: 'data failing counts as no data');
    expect(sosEntry().attempts, 2, reason: 'data is still tried as well');
  });

  test('a failed data try does not undo "relaying"', () async {
    sms.works = false;
    await signal(internet: false);
    await engine.add(entry(start));
    await at(const Duration(seconds: 20));
    expect(sosEntry().delivery, DeliveryState.relaying);
    online.add(true);
    await pumpEventQueue();
    expect(sosEntry().attempts, 1);
    expect(sosEntry().delivery, DeliveryState.relaying);
  });

  test('the steps move on by themselves', () async {
    await engine.dispose();
    engine = make(
      clock: DateTime.now,
      dataWindow: const Duration(milliseconds: 40),
    );
    await signal(internet: false);
    await engine.add(entry(DateTime.now()));
    await pumpEventQueue();
    expect(sms.sent, isEmpty);
    expect(radio.adverts, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await pumpEventQueue();
    expect(sms.sent, hasLength(1));
    expect(radio.adverts.keys, [RelayTier.ownKey(id)]);
  });

  test('after a restart the steps taken are kept, and the advert comes '
      'back', () async {
    sms.works = false;
    await signal(internet: false);
    await engine.add(entry(start));
    await at(const Duration(seconds: 20));
    await engine.dispose();
    radio.adverts.clear(); // the advert died with the app

    engine = make();
    expect(sosEntry().steps!.smsFailed, isTrue);
    expect(sosEntry().steps!.bluetooth, isTrue);
    await signal(internet: false);
    expect(radio.adverts.keys, [RelayTier.ownKey(id)]);
    final back = OutboxEntry.fromJson(sosEntry().toJson());
    expect(back.steps, sosEntry().steps);
    expect(engine.entries.single.toQueued().steps, sosEntry().steps);
  });

  test('anything but an SOS has no steps and is never texted', () async {
    final report = OutboxEntry(
      id: 'r-1',
      action: OutboxAction.crowdReport,
      accountId: 'res-001',
      capturedAt: start,
      payload: const {},
    );
    expect(report.steps, isNull);
    await signal(internet: false);
    await engine.add(report);
    await at(const Duration(minutes: 5));
    expect(sms.sent, isEmpty);
    expect(radio.adverts, isEmpty);
  });
}
