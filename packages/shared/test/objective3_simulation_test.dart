// Objective 3 simulation for Chapter 4: SOS transmission during simulated
// internet outages (at least 95%), through the app's real offline code.
//
// What is real here: the phone's queue and its escalation (SyncEngine:
// data, then SMS, then Bluetooth), the SAGIP1 text the gateway decodes
// (SosSms, the same format as the sms-intake function, checked against
// shared vectors), the 24-byte Bluetooth packet (SosRelayPacket), and the
// relaying phone's logic (RelayNode: keep, pass on, upload once).
// What is simulated: the radios, the SIM, the gateway phone, and the server
// (one record per SOS id, as the database keeps one incident per SOS).
// It shows the logic delivers every SOS it should; it does not replace the
// field trial on real phones (docs/testing/objective3/FIELD-TRIAL.md).
//
// Skipped in normal runs (it writes files). Run it with:
//   cd packages/shared
//   SAGIP_EVAL=1 flutter test test/objective3_simulation_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

const _out = '../../docs/testing/objective3';
const _gateway = '09170000000';
const _attempts = 100;

/// The server: the first copy of each SOS makes the incident; later copies
/// (the same id by another tier) join it.
class Ledger {
  final first = <String, ({String tier, DateTime capturedAt, GeoPoint? at})>{};
  var copies = 0;

  void receive(String id, String tier, DateTime capturedAt, GeoPoint? at) {
    copies++;
    first.putIfAbsent(id, () => (tier: tier, capturedAt: capturedAt, at: at));
  }
}

/// Tier 1: the app's own upload, while the phone has internet.
class AppSender implements OutboxSender {
  AppSender(this.ledger);
  final Ledger ledger;
  var reachable = false;

  @override
  Future<String?> send(OutboxEntry entry) async {
    if (!reachable) throw const ActionRejected(ActionRejection.offline);
    if (entry.action == OutboxAction.sos) {
      final sos = SosRequest.fromJson(entry.payload);
      ledger.receive(sos.clientId, 'app', sos.capturedAt, sos.location);
    }
    return 'INC-0300';
  }
}

/// Tier 2: the phone's SIM. With signal and load the text reaches the
/// gateway, which decodes it and replies.
class Sim implements SmsSender {
  Sim(this.ledger);
  final Ledger ledger;
  var signal = false;
  var hasLoad = true;
  final replies = <String>[];
  var decodeFailures = 0;

  @override
  Future<bool> send(String number, String text) async {
    if (!signal || !hasLoad) return false;
    try {
      final r = SosSms.decode(text);
      ledger.receive(r.clientId, 'sms', r.capturedAt, r.location);
      replies.add(
        'S.A.G.I.P.: Your SOS was received (INC-0300, ref '
        '${SosSms.ackRef(r.clientId)}). Stay where you are if safe.',
      );
    } on FormatException {
      decodeFailures++;
    }
    return true;
  }
}

/// A Bluetooth radio. What one phone advertises is heard by the phones in
/// range.
class Radio implements RelayRadio {
  final adverts = <String, Uint8List>{};
  final listeners = <Radio>[];
  final _heard = StreamController<Uint8List>.broadcast();
  var inRange = true;

  @override
  Future<bool> isSupported() async => true;
  @override
  Future<void> keepRunning(bool on) async {}
  @override
  Future<void> showStatus({required int carrying, required int sent}) async {}

  @override
  Future<bool> advertise(String key, Uint8List packet) async {
    adverts[key] = packet;
    if (inRange) {
      for (final l in listeners) {
        l._heard.add(packet);
      }
    }
    return true;
  }

  @override
  Future<void> stop(String key) async => adverts.remove(key);

  @override
  Stream<Uint8List> heard() => _heard.stream;
}

/// One outage condition, run for [_attempts] SOS.
class Condition {
  const Condition({
    required this.key,
    required this.label,
    this.internet = false,
    this.signal = false,
    this.hasLoad = true,
    this.neighbour = false,
    this.neighbourOnline = false,
    this.neighbourOnlineLater = false,
  });

  final String key;
  final String label;
  final bool internet;
  final bool signal;
  final bool hasLoad;
  final bool neighbour;
  final bool neighbourOnline;

  /// The nearby phone has no internet either, and finds it after the
  /// outage (store and forward).
  final bool neighbourOnlineLater;
}

const _conditions = [
  Condition(key: 'C0', label: 'Internet available (control)', internet: true),
  Condition(
    key: 'C1',
    label: 'No mobile data, cell signal: SMS to the gateway (Tier 2)',
    signal: true,
  ),
  Condition(
    key: 'C2',
    label: 'No data, no signal, a nearby phone with internet (Tier 3)',
    neighbour: true,
    neighbourOnline: true,
  ),
  Condition(
    key: 'C3',
    label: 'Signal but no load (text fails), a nearby phone with internet',
    signal: true,
    hasLoad: false,
    neighbour: true,
    neighbourOnline: true,
  ),
  Condition(
    key: 'C4',
    label:
        'No data, no signal, the nearby phone is offline too and '
        'reaches the internet later',
    neighbour: true,
    neighbourOnlineLater: true,
  ),
  Condition(
    key: 'C5',
    label:
        'No data, no signal, nobody nearby (Tier 1 only, until the '
        'internet returns)',
  ),
];

String _uuid(math.Random r) {
  String hex(int n) =>
      [for (var i = 0; i < n; i++) r.nextInt(16).toRadixString(16)].join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  final run = Platform.environment['SAGIP_EVAL'] != null;

  test(
    'Objective 3 simulation',
    () async {
      Directory(_out).createSync(recursive: true);
      final places = [
        for (final b in manilaBarangays)
          if (b.center != null) b.center!,
      ];
      final rows = <List<Object?>>[];
      final summary = <String, Object?>{
        'ran_at': DateTime.now().toIso8601String(),
        'attempts_per_condition': _attempts,
        'conditions': <Object?>[],
      };
      var allAttempts = 0, allDuringOutage = 0, allFinal = 0;

      for (final c in _conditions) {
        final rng = math.Random(c.key.hashCode);
        final ledger = Ledger();
        final appSender = AppSender(ledger)..reachable = c.internet;
        final sim = Sim(ledger)
          ..signal = c.signal
          ..hasLoad = c.hasLoad;
        final phone = Radio();
        final neighbourRadio = Radio();
        if (c.neighbour) phone.listeners.add(neighbourRadio);

        final online = StreamController<bool>.broadcast();
        final texting = StreamController<bool>.broadcast();
        final bluetooth = StreamController<bool>.broadcast();
        var now = DateTime.utc(2026, 11, 12, 6);
        final engine = SyncEngine(
          store: MemoryLocalStore(),
          sender: appSender,
          online: online.stream,
          account: () => 'res-001',
          clock: () => now,
          retryDelay: (_) => const Duration(milliseconds: 5),
          sms: SmsTier(
            sender: sim,
            gatewayNumber: () => _gateway,
            available: texting.stream,
            retryAfter: const Duration(milliseconds: 5),
          ),
          relay: RelayTier(radio: phone, available: bluetooth.stream),
          dataWindow: Duration.zero,
        );

        final neighbourOnline = StreamController<bool>.broadcast();
        var neighbourReachable = c.neighbourOnline;
        final node = RelayNode(
          radio: neighbourRadio,
          store: MemoryLocalStore(),
          online: neighbourOnline.stream,
          upload: (p) async {
            if (!neighbourReachable) {
              throw const ActionRejected(ActionRejection.offline);
            }
            ledger.receive(p.clientId, 'bleRelay', p.capturedAt, p.location);
          },
          ownIds: () => const {},
          clock: () => now,
        );
        await node.start();

        online.add(c.internet);
        texting.add(!c.internet && c.signal);
        bluetooth.add(!c.internet);
        neighbourOnline.add(c.neighbourOnline);
        await _settle();

        // The outage: one SOS pressed at a time, a minute apart.
        final sent = <SosRequest>[];
        for (var i = 0; i < _attempts; i++) {
          now = now.add(const Duration(minutes: 1));
          final base = places[rng.nextInt(places.length)];
          final sos = SosRequest(
            clientId: _uuid(rng),
            capturedAt: now,
            delivery: DeliveryState.savedOnPhone,
            location: GeoPoint(
              base.lat + (rng.nextDouble() - 0.5) * 0.002,
              base.lng + (rng.nextDouble() - 0.5) * 0.002,
            ),
            accuracyMeters: 5 + rng.nextInt(20).toDouble(),
          );
          sent.add(sos);
          await engine.add(
            OutboxEntry(
              id: sos.clientId,
              action: OutboxAction.sos,
              accountId: 'res-001',
              capturedAt: sos.capturedAt,
              payload: sos.toJson(),
            ),
          );
          await _settle();
          // The gateway's reply reaches the phone (Tier 2 confirmed).
          for (final reply in sim.replies) {
            await engine.gatewayReplied(_gateway, reply);
          }
          sim.replies.clear();
        }
        await _settle();
        final duringOutage = {...ledger.first.keys};
        final byTier = <String, int>{};
        for (final v in ledger.first.values) {
          byTier[v.tier] = (byTier[v.tier] ?? 0) + 1;
        }

        // Recovery: the nearby phone (C4) and then the sender find the
        // internet again. Every copy still on a phone is sent.
        if (c.neighbourOnlineLater) {
          neighbourReachable = true;
          neighbourOnline.add(true);
          await _settle();
        }
        final viaNeighbourLater = {...ledger.first.keys}
          ..removeAll(duringOutage);
        appSender.reachable = true;
        online.add(true);
        texting.add(false);
        bluetooth.add(false);
        await _settle();
        await engine.retryNow();
        await _settle();

        // Checks against what was pressed.
        var timeErrorMax = 0, locErrorMax = 0.0, delivered = 0;
        for (final sos in sent) {
          final got = ledger.first[sos.clientId];
          if (got == null) continue;
          delivered++;
          timeErrorMax = math.max(
            timeErrorMax,
            got.capturedAt.difference(sos.capturedAt).inSeconds.abs(),
          );
          if (got.at != null) {
            locErrorMax = math.max(
              locErrorMax,
              got.at!.distanceTo(sos.location!),
            );
          }
          rows.add([
            c.key,
            sos.clientId.substring(0, 8),
            duringOutage.contains(sos.clientId) ? 'yes' : 'no',
            got.tier,
            viaNeighbourLater.contains(sos.clientId) ? 'yes' : 'no',
          ]);
        }
        final phoneDelivered = engine.entries
            .where((e) => e.delivery == DeliveryState.delivered)
            .length;
        final during =
            duringOutage.length +
            (c.neighbourOnlineLater ? viaNeighbourLater.length : 0);

        (summary['conditions']! as List).add({
          'key': c.key,
          'label': c.label,
          'attempts': _attempts,
          'reached_server_during_outage': duringOutage.length,
          'reached_server_by_tier_during_outage': byTier,
          'reached_server_through_neighbour_later': viaNeighbourLater.length,
          'reached_server_in_the_end': delivered,
          'success_rate_during_outage_pct':
              100 * (c.internet ? delivered : during) / _attempts,
          'success_rate_in_the_end_pct': 100 * delivered / _attempts,
          'copies_received_by_server': ledger.copies,
          'incidents_created': ledger.first.length,
          'duplicate_incidents': ledger.first.length - delivered,
          'phone_shows_delivered': phoneDelivered,
          'capture_time_error_max_s': timeErrorMax,
          'location_error_max_m': double.parse(locErrorMax.toStringAsFixed(2)),
          'sms_decode_failures': sim.decodeFailures,
        });
        allAttempts += _attempts;
        allDuringOutage += c.internet ? delivered : during;
        allFinal += delivered;

        expect(delivered, _attempts, reason: '${c.key}: every SOS arrives');
        expect(ledger.first.length, _attempts, reason: 'one incident per SOS');
        expect(phoneDelivered, _attempts, reason: 'the phone says delivered');
        expect(timeErrorMax, lessThanOrEqualTo(1));

        await node.dispose();
        await engine.dispose();
        await online.close();
        await texting.close();
        await bluetooth.close();
        await neighbourOnline.close();
      }

      // The outage conditions only (C1 to C5), as Objective 3 asks.
      final outage = (summary['conditions']! as List)
          .cast<Map<String, Object?>>()
          .where((m) => m['key'] != 'C0');
      final outAttempts = outage.length * _attempts;
      final outDuring = outage.fold<int>(
        0,
        (t, m) =>
            t +
            (m['reached_server_during_outage']! as int) +
            (m['reached_server_through_neighbour_later']! as int),
      );
      final outTiers2and3 = outage
          .where((m) => m['key'] != 'C5')
          .fold<int>(
            0,
            (t, m) =>
                t +
                (m['reached_server_during_outage']! as int) +
                (m['reached_server_through_neighbour_later']! as int),
          );
      summary['totals'] = {
        'attempts_all': allAttempts,
        'delivered_in_the_end_all': allFinal,
        'outage_attempts': outAttempts,
        'outage_delivered_without_the_senders_internet': outDuring,
        'outage_success_rate_pct': 100 * outDuring / outAttempts,
        'outage_success_rate_with_a_fallback_available_pct':
            100 * outTiers2and3 / ((outage.length - 1) * _attempts),
        'delivered_in_the_end_pct': 100 * allFinal / allAttempts,
        'during_outage_all': allDuringOutage,
      };

      final b = StringBuffer(
        'condition,sos,reached_server_during_outage,first_tier,'
        'through_neighbour_later\n',
      );
      for (final r in rows) {
        b.writeln(r.join(','));
      }
      File('$_out/simulation_attempts.csv').writeAsStringSync(b.toString());
      File(
        '$_out/simulation_summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(summary));
    },
    skip: run
        ? false
        : 'set SAGIP_EVAL=1 to run (writes docs/testing/objective3)',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
