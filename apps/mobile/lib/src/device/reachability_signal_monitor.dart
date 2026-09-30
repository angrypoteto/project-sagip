import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:sagip_shared/sagip_shared.dart';

/// What the phone can reach (plan 7.6). "Internet" means the S.A.G.I.P.
/// server answers, not just that Wi-Fi is on. Without that: a mobile
/// network counts as SMS only, nothing at all as no signal.
///
/// Checked when the network changes and every [every] while running.
class ReachabilitySignalMonitor implements SignalMonitor {
  ReachabilitySignalMonitor({
    required this._healthUrl,
    required this._apiKey,
    this.every = const Duration(seconds: 20),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri _healthUrl;
  final String _apiKey;
  final http.Client _client;
  final Duration every;

  // Until the first check, assume online so the banner does not flash.
  final _state = LiveValue(SignalState.internet);
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _changes;
  Timer? _timer;
  var _started = false;
  var _checking = false;

  @override
  Stream<SignalState> watch() {
    if (!_started) {
      _started = true;
      _changes = _connectivity.onConnectivityChanged.listen(
        (r) => unawaited(_check(r)),
        onError: (Object _) {},
      );
      _timer = Timer.periodic(every, (_) => unawaited(_check()));
      unawaited(_check());
    }
    return _state.watch();
  }

  /// Checks now, for example after the resident taps "Try sending now".
  Future<void> checkNow() => _check();

  Future<void> _check([List<ConnectivityResult>? results]) async {
    if (_checking) return;
    _checking = true;
    try {
      final network = results ?? await _connectivity.checkConnectivity();
      final connected = network.any((r) => r != ConnectivityResult.none);
      var reachable = false;
      if (connected) {
        try {
          final res = await _client
              .get(_healthUrl, headers: {'apikey': _apiKey})
              .timeout(const Duration(seconds: 6));
          reachable = res.statusCode < 500;
        } catch (_) {
          reachable = false;
        }
      }
      final next = reachable
          ? SignalState.internet
          : network.contains(ConnectivityResult.mobile)
          ? SignalState.smsOnly
          : SignalState.noSignal;
      if (_state.value != next) _state.value = next;
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_changes?.cancel());
    _client.close();
  }
}
