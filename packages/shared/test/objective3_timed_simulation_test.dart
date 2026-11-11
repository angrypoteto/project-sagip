// Objective 3, simulation B (2026-11-12): the field trial's four conditions
// in simulated time, with radios that fail and take time, to show how far
// the 95% target holds (an SOS counts when it reaches the server within 3
// minutes of the press).
//
// Joshua, 2026-11-12: "can you simulate it" (Objective 3, instead of only
// the field trial).
//
// What is real here: the phone's offline code (SyncEngine: no data window
// when the phone knows it is offline, Bluetooth advert at once, SMS retried
// 10 s after a failed text, the 20 s give-up of a text) and the nearby
// phone's relay (RelayNode). Time runs in a fake clock, so the app's own
// timers fire as they would on a phone.
// What is assumed, and swept over a range because it was not measured:
// - how often a text fails at the phone (no load, weak signal);
// - how long a text takes from the phone to the gateway, after it went;
// - how quickly the nearby phone hears the advert (a chance per second);
// - how often the nearby phone's scan has stopped (a locked phone that
//   stops scans), which build 31 restarts within 10 minutes;
// - how long the nearby phone's upload takes.
// The "observed" settings come from the 71 real SOS of
// docs/testing/objective3/HISTORY-RESULTS.md.
//
// Skipped in normal runs (it writes files). Run it with:
//   cd packages/shared
//   SAGIP_EVAL=1 flutter test test/objective3_timed_simulation_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

const _out = '../../docs/testing/objective3';
const _gateway = '09170000000';
const _attempts = 500;
const _window = Duration(minutes: 3);

/// No internet on the sender for the whole run.
class _NoData implements OutboxSender {
  @override
  Future<String?> send(OutboxEntry entry) async =>
      throw const ActionRejected(ActionRejection.offline);
}

/// The sender's SIM: a text fails at the phone with [failChance] (after the
/// phone takes [failAfter] to say so); one that goes reaches the gateway
/// after [transit].
class _Sim implements SmsSender {
  _Sim(this.rng, this.s, this.onGateway);
  final math.Random rng;
  final Settings s;
  final void Function() onGateway;
  var texts = 0;

  @override
  Future<bool> send(String number, String text) async {
    texts++;
    if (rng.nextDouble() < s.smsFail) {
      await Future<void>.delayed(s.smsFailAfter);
      return false;
    }
    SosSms.decode(text); // the gateway can read it (throws if not)
    final transit =
        s.smsTransitMin +
        (s.smsTransitMax - s.smsTransitMin) * rng.nextDouble();
    Timer(transit, onGateway);
    return true;
  }
}

/// A Bluetooth radio; [hear] puts a packet into this phone's scan.
class _Radio implements RelayRadio {
  final adverts = <String, Uint8List>{};
  final _heard = StreamController<Uint8List>.broadcast();

  void hear(Uint8List p) => _heard.add(p);

  @override
  Future<bool> isSupported() async => true;
  @override
  Future<void> keepRunning(bool on) async {}
  @override
  Future<void> showStatus({required int carrying, required int sent}) async {}
  @override
  Future<bool> advertise(String key, Uint8List packet) async {
    adverts[key] = packet;
    return true;
  }

  @override
  Future<void> stop(String key) async => adverts.remove(key);
  @override
  Stream<Uint8List> heard() => _heard.stream;
}

/// One setting of the assumed radio behaviour.
class Settings {
  const Settings({
    required this.name,
    this.smsFail = 0,
    this.smsFailAfter = const Duration(seconds: 5),
    this.smsTransitMin = const Duration(milliseconds: 500),
    this.smsTransitMax = const Duration(seconds: 30),
    this.hearPerSecondNear = 0.03,
    this.hearPerSecondFar = 0.01,
    this.scanStopped = 0,
    this.uploadMax = const Duration(seconds: 2),
  });

  final String name;
  final double smsFail;
  final Duration smsFailAfter;
  final Duration smsTransitMin;
  final Duration smsTransitMax;

  /// Chance per second that the nearby phone hears the advert, at about
  /// 5 m and at 15 to 20 m.
  final double hearPerSecondNear;
  final double hearPerSecondFar;

  /// Chance the nearby phone's scan has stopped at the press; it restarts
  /// at a random moment in the next 10 minutes (build 31's keep-alive).
  final double scanStopped;
  final Duration uploadMax;

  Map<String, Object?> toJson() => {
    'name': name,
    'sms_fail_chance': smsFail,
    'sms_fail_reported_after_s': smsFailAfter.inMilliseconds / 1000,
    'sms_transit_s': [
      smsTransitMin.inMilliseconds / 1000,
      smsTransitMax.inMilliseconds / 1000,
    ],
    'hear_chance_per_second_near': hearPerSecondNear,
    'hear_chance_per_second_far': hearPerSecondFar,
    'scan_stopped_chance': scanStopped,
    'upload_s_max': uploadMax.inMilliseconds / 1000,
  };
}

/// The field trial's four conditions (FIELD-TRIAL.md, Table 4.9b).
enum Cond {
  smsOnly('F1', 'SMS only (no data, signal and load, nobody nearby)'),
  bleNear(
    'F2',
    'Bluetooth relay, nearby phone within 5 m (no data, no signal)',
  ),
  bleFar('F3', 'Bluetooth relay, nearby phone 15 to 20 m away'),
  textFails('F4', 'Text fails (no load), Bluetooth relay takes over (5 m)');

  const Cond(this.key, this.label);
  final String key;
  final String label;
}

String _uuid(math.Random r) {
  String hex(int n) =>
      [for (var i = 0; i < n; i++) r.nextInt(16).toRadixString(16)].join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
}

/// One SOS press; the seconds until the server had it (null: not within
/// the run) and the tier that brought it first.
({double? seconds, String? tier}) _press(Cond c, Settings s, math.Random rng) {
  return fakeAsync((fa) {
    final start = DateTime.utc(2026, 11, 12, 6);
    DateTime now() => start.add(fa.elapsed);
    Duration? arrived;
    String? tier;
    void receive(String t) {
      if (arrived != null) return;
      arrived = fa.elapsed;
      tier = t;
    }

    final online = StreamController<bool>.broadcast();
    final texting = StreamController<bool>.broadcast();
    final bluetooth = StreamController<bool>.broadcast();
    final neighbourOnline = StreamController<bool>.broadcast();
    final phone = _Radio();
    final neighbour = _Radio();
    final settings = c == Cond.textFails
        ? Settings(
            name: s.name,
            smsFail: 1,
            smsFailAfter: s.smsFailAfter,
            hearPerSecondNear: s.hearPerSecondNear,
            hearPerSecondFar: s.hearPerSecondFar,
            scanStopped: s.scanStopped,
            uploadMax: s.uploadMax,
          )
        : s;
    final sim = _Sim(rng, settings, () => receive('sms'));
    final engine = SyncEngine(
      store: MemoryLocalStore(),
      sender: _NoData(),
      online: online.stream,
      account: () => 'res-001',
      clock: now,
      sms: SmsTier(
        sender: sim,
        gatewayNumber: () => _gateway,
        available: texting.stream,
      ),
      relay: RelayTier(radio: phone, available: bluetooth.stream),
    );
    final hasNeighbour = c != Cond.smsOnly;
    final node = RelayNode(
      radio: neighbour,
      store: MemoryLocalStore(),
      online: neighbourOnline.stream,
      upload: (p) async {
        await Future<void>.delayed(
          Duration(
            milliseconds: (s.uploadMax.inMilliseconds * rng.nextDouble())
                .round(),
          ),
        );
        receive('bleRelay');
      },
      ownIds: () => const {},
      clock: now,
    );
    unawaited(node.start());
    // Let the relay subscribe before the network events (broadcast
    // streams drop events nobody listens to yet).
    fa.flushMicrotasks();
    online.add(false);
    texting.add(c == Cond.smsOnly || c == Cond.textFails);
    bluetooth.add(true);
    neighbourOnline.add(true);
    fa.flushMicrotasks();

    final id = _uuid(rng);
    unawaited(
      engine.add(
        OutboxEntry(
          id: id,
          action: OutboxAction.sos,
          accountId: 'res-001',
          capturedAt: now(),
          payload: SosRequest(
            clientId: id,
            capturedAt: now(),
            delivery: DeliveryState.savedOnPhone,
            location: const GeoPoint(14.5995, 120.9842),
            accuracyMeters: 10,
          ).toJson(),
        ),
      ),
    );

    if (hasNeighbour) {
      final hear = c == Cond.bleFar ? s.hearPerSecondFar : s.hearPerSecondNear;
      final scanFrom = rng.nextDouble() < s.scanStopped
          ? Duration(milliseconds: rng.nextInt(10 * 60 * 1000))
          : Duration.zero;
      Timer.periodic(const Duration(seconds: 1), (_) {
        if (fa.elapsed < scanFrom || phone.adverts.isEmpty) return;
        if (rng.nextDouble() < hear) neighbour.hear(phone.adverts.values.first);
      });
    }
    fa.elapse(_window + const Duration(seconds: 1));
    final a = arrived;
    return (
      seconds: a == null || a > _window ? null : a.inMilliseconds / 1000,
      tier: tier,
    );
  });
}

double _median(List<double> xs) {
  if (xs.isEmpty) return -1;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

void main() {
  final run = Platform.environment['SAGIP_EVAL'] != null;

  test(
    'Objective 3 simulation B: timed, with failing radios',
    () {
      // "Observed": set from the real SOS (SMS 0.5 to 26.4 s; Bluetooth
      // median 23.8 s, which a 3% chance per second gives).
      const observed = Settings(name: 'observed');
      final sweeps = <Settings>[
        observed,
        // The far phone (15 to 20 m) was never measured: how well must it
        // hear for the target?
        const Settings(
          name: 'far phone hears as well as near',
          hearPerSecondFar: 0.03,
        ),
        const Settings(
          name: 'far phone hears 2% a second',
          hearPerSecondFar: 0.02,
        ),
        const Settings(
          name: 'far phone hears 0.5% a second',
          hearPerSecondFar: 0.005,
        ),
        const Settings(name: 'texts fail 25%', smsFail: 0.25),
        const Settings(name: 'texts fail 50%', smsFail: 0.5),
        const Settings(name: 'texts fail 75%', smsFail: 0.75),
        const Settings(
          name: 'slow network: texts take up to 2 min',
          smsTransitMax: Duration(minutes: 2),
        ),
        const Settings(
          name: 'hearing half as likely',
          hearPerSecondNear: 0.015,
          hearPerSecondFar: 0.005,
        ),
        const Settings(
          name: 'hearing a quarter as likely',
          hearPerSecondNear: 0.0075,
          hearPerSecondFar: 0.0025,
        ),
        const Settings(name: 'nearby scan stopped 10%', scanStopped: 0.1),
        const Settings(name: 'nearby scan stopped 25%', scanStopped: 0.25),
        const Settings(
          name:
              'worst together: texts fail 50%, hearing half, scan '
              'stopped 25%',
          smsFail: 0.5,
          hearPerSecondNear: 0.015,
          hearPerSecondFar: 0.005,
          scanStopped: 0.25,
        ),
      ];

      final results = <Map<String, Object?>>[];
      final rows = StringBuffer(
        'setting,condition,attempts,within_3_min,s_rate_pct,'
        'median_s,p90_s,by_sms,by_ble\n',
      );
      for (final s in sweeps) {
        final perCond = <Map<String, Object?>>[];
        var total = 0, ok = 0;
        for (final c in Cond.values) {
          final rng = math.Random('${s.name}/${c.key}'.hashCode);
          final times = <double>[];
          var sms = 0, ble = 0;
          for (var i = 0; i < _attempts; i++) {
            final r = _press(c, s, rng);
            if (r.seconds == null) continue;
            times.add(r.seconds!);
            if (r.tier == 'sms') sms++;
            if (r.tier == 'bleRelay') ble++;
          }
          final sorted = [...times]..sort();
          final p90 = sorted.isEmpty
              ? -1.0
              : sorted[((sorted.length - 1) * 0.9).round()];
          final rate = 100 * times.length / _attempts;
          perCond.add({
            'key': c.key,
            'condition': c.label,
            'attempts': _attempts,
            'within_3_min': times.length,
            's_rate_pct': rate,
            'median_s': _median(times),
            'p90_s': p90,
            'first_by_sms': sms,
            'first_by_ble': ble,
          });
          rows.writeln(
            [
              '"${s.name}"',
              c.key,
              _attempts,
              times.length,
              rate.toStringAsFixed(1),
              _median(times).toStringAsFixed(1),
              p90.toStringAsFixed(1),
              sms,
              ble,
            ].join(','),
          );
          total += _attempts;
          ok += times.length;
        }
        results.add({
          'setting': s.toJson(),
          'conditions': perCond,
          'total_attempts': total,
          'total_within_3_min': ok,
          'total_s_rate_pct': 100 * ok / total,
        });
      }

      // ignore: avoid_print
      print(rows);
      final summary = {
        'ran_at': DateTime.now().toIso8601String(),
        'attempts_per_condition': _attempts,
        'success': 'reached the server within 3 minutes of the press',
        'results': results,
      };
      Directory(_out).createSync(recursive: true);
      File(
        '$_out/simulation_b_summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      File('$_out/simulation_b_rates.csv').writeAsStringSync(rows.toString());

      // The observed setting must meet the target in the conditions it was
      // measured for (SMS, Bluetooth at about 5 m); 15 to 20 m was not.
      final obs = results.first['conditions']! as List;
      for (final m in obs.cast<Map<String, Object?>>().where(
        (m) => m['key'] != 'F3',
      )) {
        expect(
          m['s_rate_pct']! as double,
          greaterThanOrEqualTo(95),
          reason: '${m['key']} at the observed setting',
        );
      }
    },
    skip: run
        ? false
        : 'set SAGIP_EVAL=1 to run (writes docs/testing/objective3)',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
