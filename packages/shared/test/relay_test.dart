import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Records adverts; the test plays the packets other phones send.
class FakeRadio implements RelayRadio {
  final adverts = <String, Uint8List>{};
  final _heard = StreamController<Uint8List>.broadcast();
  var supported = true;

  void hear(Uint8List packet) => _heard.add(packet);

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
  Stream<Uint8List> heard() => _heard.stream;
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

void main() {
  final now = DateTime.utc(2026, 10, 3, 5, 30, 12);
  const id = '3f2a9c1e-7b4d-4e0a-9c2f-1a2b3c4d5e6f';
  const other = '9b1d2e3f-4a5b-4c6d-8e7f-0a1b2c3d4e5f';

  SosRequest sos(String clientId) => SosRequest(
    clientId: clientId,
    capturedAt: now,
    delivery: DeliveryState.savedOnPhone,
    location: const GeoPoint(14.60917, 120.99251),
    accuracyMeters: 8,
    mockLocationSuspected: true,
  );

  group('the 24-byte packet', () {
    test('round trip, to about a metre and a second', () {
      final bytes = SosRelayPacket.of(sos(id)).encode();
      expect(bytes, hasLength(24));
      final back = SosRelayPacket.decode(
        bytes,
        now.add(const Duration(hours: 5)),
      );
      expect(back.clientId, id);
      expect(back.capturedAt, now);
      expect(back.location, const GeoPoint(14.60917, 120.99251));
      expect(back.mockLocation, isTrue);
      expect(back.hops, 0);
    });

    test('the capture time is found again weeks later', () {
      final bytes = SosRelayPacket.of(sos(id)).encode();
      final back = SosRelayPacket.decode(
        bytes,
        now.add(const Duration(days: 60)),
      );
      expect(back.capturedAt, now);
    });

    test('hops count up and stop at the limit', () {
      var p = SosRelayPacket.of(sos(id));
      for (var i = 0; i < SosRelayPacket.maxHops; i++) {
        expect(p.canHop, isTrue);
        p = p.nextHop();
      }
      expect(p.hops, SosRelayPacket.maxHops);
      expect(p.canHop, isFalse);
      expect(
        SosRelayPacket.decode(p.encode(), now).hops,
        SosRelayPacket.maxHops,
      );
    });

    test('no location, or one outside the box, goes as no location', () {
      final none = SosRelayPacket(clientId: id, capturedAt: now);
      expect(SosRelayPacket.decode(none.encode(), now).location, isNull);
      final far = SosRelayPacket(
        clientId: id,
        capturedAt: now,
        location: const GeoPoint(10.3157, 123.8854), // Cebu
      );
      expect(SosRelayPacket.decode(far.encode(), now).location, isNull);
    });

    test('anything else on the service is refused', () {
      expect(
        () => SosRelayPacket.decode(Uint8List(10), now),
        throwsFormatException,
      );
      final wrong = SosRelayPacket.of(sos(id)).encode()..[0] = 0x20;
      expect(() => SosRelayPacket.decode(wrong, now), throwsFormatException);
    });
  });

  group('tier 3 for the phone\'s own SOS', () {
    late FakeRadio radio;
    late FakeSender sender;
    late StreamController<bool> online;
    late StreamController<bool> relayOk;
    late MemoryLocalStore store;
    late SyncEngine engine;

    SyncEngine make() => SyncEngine(
      store: store,
      sender: sender,
      online: online.stream,
      account: () => 'res-001',
      clock: () => now,
      retryDelay: (_) => const Duration(milliseconds: 10),
      relay: RelayTier(radio: radio, available: relayOk.stream),
    );

    setUp(() {
      radio = FakeRadio();
      sender = FakeSender();
      online = StreamController<bool>.broadcast();
      relayOk = StreamController<bool>.broadcast();
      store = MemoryLocalStore();
      engine = make();
    });

    tearDown(() => engine.dispose());

    OutboxEntry entry(String clientId) => OutboxEntry(
      id: clientId,
      action: OutboxAction.sos,
      accountId: 'res-001',
      capturedAt: now,
      payload: sos(clientId).toJson(),
    );

    test(
      'no internet, no signal: advertised; delivered later, advert stopped',
      () async {
        online.add(false);
        relayOk.add(true);
        await pumpEventQueue();
        await engine.add(entry(id));
        await pumpEventQueue();

        expect(engine.entries.single.delivery, DeliveryState.relaying);
        final advert = radio.adverts[RelayTier.ownKey(id)]!;
        expect(SosRelayPacket.decode(advert, now).clientId, id);
        // The phone shows it as relaying.
        expect(
          OutboxSosRepository.mergeSos(
            null,
            engine.entries,
            'res-001',
          ).single.delivery,
          DeliveryState.relaying,
        );

        // Internet again: it still goes to the server itself, and the advert ends.
        sender.reachable = true;
        online.add(true);
        relayOk.add(false);
        await pumpEventQueue();
        expect(sender.sent, [id]);
        expect(engine.entries.single.delivery, DeliveryState.delivered);
        expect(radio.adverts, isEmpty);
      },
    );

    test('Bluetooth off: the SOS waits on the phone', () async {
      radio.supported = false;
      online.add(false);
      relayOk.add(true);
      await pumpEventQueue();
      await engine.add(entry(id));
      await pumpEventQueue();
      expect(engine.entries.single.delivery, DeliveryState.savedOnPhone);
    });

    test('after a restart, a relaying SOS is advertised again', () async {
      online.add(false);
      relayOk.add(true);
      await pumpEventQueue();
      await engine.add(entry(id));
      await pumpEventQueue();
      await engine.dispose();
      radio.adverts.clear(); // the advert died with the app

      engine = make();
      online.add(false);
      relayOk.add(true);
      await pumpEventQueue();
      expect(radio.adverts.keys, [RelayTier.ownKey(id)]);
      expect(engine.entries.single.delivery, DeliveryState.relaying);
    });
  });

  group('passing on SOS heard from other phones', () {
    late FakeRadio radio;
    late StreamController<bool> online;
    late MemoryLocalStore store;
    late List<SosRelayPacket> uploaded;
    late ActionRejected? refuse;
    late RelayNode node;

    RelayNode make() => RelayNode(
      radio: radio,
      store: store,
      online: online.stream,
      upload: (p) async {
        if (refuse != null) throw refuse!;
        uploaded.add(p);
      },
      ownIds: () => {id},
      clock: () => now,
    );

    setUp(() async {
      radio = FakeRadio();
      online = StreamController<bool>.broadcast();
      store = MemoryLocalStore();
      uploaded = [];
      refuse = null;
      node = make();
      await node.start();
    });

    tearDown(() => node.dispose());

    test('offline: kept and passed on one hop further', () async {
      online.add(false);
      await pumpEventQueue();
      radio.hear(SosRelayPacket.of(sos(other)).encode());
      await pumpEventQueue();

      final carried = await node.watch().first;
      expect(carried.single.packet.clientId, other);
      final passed = SosRelayPacket.decode(radio.adverts['relay:$other']!, now);
      expect(passed.hops, 1);

      // Online: uploaded once, and the advert ends.
      online.add(true);
      await pumpEventQueue();
      expect(uploaded.map((p) => p.clientId), [other]);
      expect(radio.adverts, isEmpty);
      expect((await node.watch().first).single.uploaded, isTrue);
      radio.hear(SosRelayPacket.of(sos(other)).encode());
      await pumpEventQueue();
      expect(uploaded, hasLength(1), reason: 'not sent twice');
    });

    test('the phone\'s own SOS heard back is ignored', () async {
      online.add(false);
      await pumpEventQueue();
      radio.hear(SosRelayPacket.of(sos(id)).encode());
      await pumpEventQueue();
      expect(await node.watch().first, isEmpty);
      expect(radio.adverts, isEmpty);
    });

    test('at the hop limit it is kept but not passed on', () async {
      online.add(false);
      await pumpEventQueue();
      var p = SosRelayPacket.of(sos(other));
      for (var i = 0; i < SosRelayPacket.maxHops; i++) {
        p = p.nextHop();
      }
      radio.hear(p.encode());
      await pumpEventQueue();
      expect(
        (await node.watch().first).single.packet.hops,
        SosRelayPacket.maxHops,
      );
      expect(radio.adverts, isEmpty);
    });

    test('a refusal is kept so it is not sent again; offline waits', () async {
      online.add(false);
      await pumpEventQueue();
      radio.hear(SosRelayPacket.of(sos(other)).encode());
      await pumpEventQueue();
      refuse = const ActionRejected(ActionRejection.offline);
      online.add(true);
      await pumpEventQueue();
      expect((await node.watch().first).single.done, isFalse);

      refuse = const ActionRejected(ActionRejection.notAllowed);
      await node.uploadAll();
      final h = (await node.watch().first).single;
      expect(h.dropped, 'notAllowed');
      refuse = null;
      await node.uploadAll();
      expect(uploaded, isEmpty);
    });

    test('what it carries survives a restart', () async {
      online.add(false);
      await pumpEventQueue();
      radio.hear(SosRelayPacket.of(sos(other)).encode());
      await pumpEventQueue();
      await node.dispose();

      node = make();
      await node.start();
      expect((await node.watch().first).single.packet.clientId, other);
      online.add(true);
      await pumpEventQueue();
      expect(uploaded.map((p) => p.clientId), [other]);
    });
  });
}
