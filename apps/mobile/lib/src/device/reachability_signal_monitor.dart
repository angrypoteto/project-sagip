import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:sagip_shared/sagip_shared.dart';

/// What the phone can reach (plan 7.6). "Internet" means the S.A.G.I.P.
/// server answers, not just that Wi-Fi is on. Without that: a mobile
/// network counts as SMS only, nothing at all as no signal.
///
/// Checked when the network changes, every [every] while online, and every
/// [everyOffline] while not, so a returning connection is noticed within
/// seconds and the saved records go out (FR13).
///
/// One slow answer on mobile data used to mark the phone offline at once
/// (Joshua, 2026-10-16: "even though I am online it keeps on making it
/// offline"). Now going offline takes [failuresToDrop] failed checks in a
/// row, a few seconds apart; coming back online takes one good answer.
class ReachabilitySignalMonitor implements SignalMonitor {
  ReachabilitySignalMonitor({
    required this._healthUrl,
    required this._apiKey,
    this.every = const Duration(seconds: 20),
    this.everyOffline = const Duration(seconds: 5),
    this.confirmAfter = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 10),
    this.failuresToDrop = 2,
    http.Client Function()? client,
    this._network,
    this._networkChanges,
  }) : _newClient = client ?? http.Client.new;

  final Uri _healthUrl;
  final String _apiKey;
  final Duration every;
  final Duration everyOffline;

  /// How soon a failed check is repeated before the phone counts offline.
  final Duration confirmAfter;
  final Duration timeout;
  final int failuresToDrop;

  /// A fresh client for each check: after the phone changes network, a
  /// kept-open connection can hang until the timeout and look like no
  /// internet.
  final http.Client Function() _newClient;
  final Future<List<ConnectivityResult>> Function()? _network;
  final Stream<List<ConnectivityResult>>? _networkChanges;

  // Until the first check, assume online so the banner does not flash.
  final _state = LiveValue(SignalState.internet);
  Connectivity? _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _changes;
  Timer? _timer;
  var _started = false;
  var _checking = false;
  var _again = false;
  var _failures = 0;
  var _disposed = false;

  Connectivity get _plugin => _connectivity ??= Connectivity();

  @override
  Stream<SignalState> watch() {
    if (!_started) {
      _started = true;
      _changes = (_networkChanges ?? _plugin.onConnectivityChanged).listen(
        (_) => unawaited(_check()),
        onError: (Object _) {},
      );
      unawaited(_check());
    }
    return _state.watch();
  }

  /// Checks now, for example after the resident taps "Try sending now".
  Future<void> checkNow() => _check();

  Future<void> _check() async {
    if (_disposed) return;
    if (_checking) {
      // A network change during a check: look again right after it, so
      // the change is never missed.
      _again = true;
      return;
    }
    _checking = true;
    _timer?.cancel();
    try {
      do {
        _again = false;
        await _checkOnce();
      } while (_again && !_disposed);
    } finally {
      _checking = false;
      _schedule();
    }
  }

  Future<void> _checkOnce() async {
    List<ConnectivityResult> network;
    try {
      network = await (_network ?? _plugin.checkConnectivity)();
    } catch (_) {
      network = const [ConnectivityResult.other];
    }
    final connected = network.any((r) => r != ConnectivityResult.none);
    final reachable = connected && await _serverAnswers();
    if (reachable) {
      _failures = 0;
      _set(SignalState.internet);
      return;
    }
    _failures++;
    // Online until the failure is confirmed: a second check a few seconds
    // later decides.
    if (_state.value == SignalState.internet && _failures < failuresToDrop) {
      return;
    }
    _set(
      network.contains(ConnectivityResult.mobile)
          ? SignalState.smsOnly
          : SignalState.noSignal,
    );
  }

  Future<bool> _serverAnswers() async {
    final client = _newClient();
    try {
      final res = await client
          .get(_healthUrl, headers: {'apikey': _apiKey})
          .timeout(timeout);
      return res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void _set(SignalState next) {
    if (_state.value != next) _state.value = next;
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    final wait = _state.value != SignalState.internet
        ? everyOffline
        : _failures > 0
        ? confirmAfter
        : every;
    _timer = Timer(wait, () => unawaited(_check()));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_changes?.cancel());
  }
}
