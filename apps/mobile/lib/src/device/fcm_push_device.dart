import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Push through Firebase Cloud Messaging (plan part 7). Android shows each
/// notification itself, even with the app closed; this class only gives
/// the app the phone's token, the topics, and the taps.
class FcmPushDevice implements PushDevice {
  FcmPushDevice._(this._messaging);

  final FirebaseMessaging _messaging;
  var _initialTaken = false;

  /// Null when the app was built without the Firebase project's config
  /// file (android/app/google-services.json): the app then runs without
  /// push, as before.
  static Future<FcmPushDevice?> start() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return null;
    }
    return FcmPushDevice._(FirebaseMessaging.instance);
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Future<void> subscribe(String topic) => _messaging.subscribeToTopic(topic);

  @override
  Future<void> unsubscribe(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  /// The tap that started the app comes first, once; then taps while the
  /// app runs or sits in the background.
  @override
  Stream<Map<String, Object?>> get opened async* {
    if (!_initialTaken) {
      _initialTaken = true;
      final first = await _messaging.getInitialMessage();
      if (first != null) yield first.data;
    }
    yield* FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);
  }
}
