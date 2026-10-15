import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sagip_mobile/src/device/reachability_signal_monitor.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The online check against a stand-in server and network (Joshua,
/// 2026-10-16: the app kept going offline while online, and did not send
/// again when the connection came back).
void main() {
  late List<bool> answers; // what each health check gets, in order
  late List<ConnectivityResult> network;
  late StreamController<List<ConnectivityResult>> changes;
  late List<SignalState> states;
  ReachabilitySignalMonitor? monitor;

  ReachabilitySignalMonitor start() {
    final m = ReachabilitySignalMonitor(
      healthUrl: Uri.parse('https://project.example/auth/v1/health'),
      apiKey: 'key',
      every: const Duration(milliseconds: 400),
      everyOffline: const Duration(milliseconds: 40),
      confirmAfter: const Duration(milliseconds: 40),
      timeout: const Duration(milliseconds: 200),
      client: () => MockClient((_) async {
        final ok = answers.isEmpty || answers.removeAt(0);
        if (!ok) throw http.ClientException('connection reset');
        return http.Response('{}', 200);
      }),
      network: () async => network,
      networkChanges: changes.stream,
    );
    m.watch().listen(states.add);
    return monitor = m;
  }

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() {
    answers = [];
    network = [ConnectivityResult.wifi];
    changes = StreamController.broadcast();
    states = [];
  });
  tearDown(() async {
    monitor?.dispose();
    await changes.close();
  });

  test('one slow or lost answer does not mark the phone offline', () async {
    answers = [true, false, true];
    start();
    await wait(150);
    expect(states, isNot(contains(SignalState.noSignal)));
    expect(states.last, SignalState.internet);
  });

  test(
    'two failed checks in a row do; on mobile data it is SMS only',
    () async {
      network = [ConnectivityResult.mobile];
      answers = [false, false, false, false];
      start();
      await wait(150);
      expect(states.last, SignalState.smsOnly);
    },
  );

  test('back online within seconds once the server answers again', () async {
    answers = [false, false, false, true];
    start();
    await wait(70);
    expect(states, contains(SignalState.noSignal));
    await wait(150);
    expect(states.last, SignalState.internet);
  });

  test('a network change during a check is looked at right after it', () async {
    network = [ConnectivityResult.none];
    start();
    await wait(10);
    expect(states.last, SignalState.internet, reason: 'not confirmed yet');
    network = [ConnectivityResult.wifi];
    changes.add([ConnectivityResult.wifi]);
    await wait(60);
    expect(states.last, SignalState.internet);
    expect(states, isNot(contains(SignalState.noSignal)));
  });
}
