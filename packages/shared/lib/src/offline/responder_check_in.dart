import 'dart:async';

import 'mobile_server.dart';

/// Tells the server the responder app is open on screen (2026-11-03,
/// `note_app_open`): no position, only the time. Someone off duty whose app
/// is in use is shown to their crew head and the dispatcher, so a member
/// the head forgot to switch on stands out.
///
/// Checks in at once when the app comes to the screen, then every [every]
/// while it stays there and the phone is online. Never queued: only the
/// newest time matters.
class ResponderCheckIn {
  ResponderCheckIn({
    required this._server,
    required Stream<bool> online,
    this.every = const Duration(minutes: 2),
  }) : _onlineChanges = online;

  final MobileServer _server;
  final Stream<bool> _onlineChanges;
  final Duration every;

  StreamSubscription<bool>? _onlineSub;
  Timer? _timer;
  var _online = false;
  var _foreground = true;
  var _running = false;
  var _busy = false;

  void start() {
    if (_running) return;
    _running = true;
    _onlineSub = _onlineChanges.listen((on) {
      final cameOnline = on && !_online;
      _online = on;
      if (cameOnline) unawaited(_send());
    });
    _timer = Timer.periodic(every, (_) => unawaited(_send()));
    unawaited(_send());
  }

  /// The app came to the screen (true) or left it (false).
  void setForeground(bool on) {
    final cameBack = on && !_foreground;
    _foreground = on;
    if (cameBack) unawaited(_send());
  }

  Future<void> _send() async {
    if (!_running || !_online || !_foreground || _busy) return;
    _busy = true;
    try {
      await _server.noteAppOpen();
    } catch (_) {
      // The next tick tries again.
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _onlineSub?.cancel();
    _onlineSub = null;
  }
}
