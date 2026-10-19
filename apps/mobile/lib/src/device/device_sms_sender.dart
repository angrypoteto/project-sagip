import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Tier 2 texts through Android's SMS service (`MainActivity.kt`,
/// channel `ph.sagip/sms`). Needs the SMS permission (S2 step 3); without
/// it, [compose] opens the messages app with the text ready instead.
class DeviceSmsSender implements SmsSender, SmsComposer {
  const DeviceSmsSender();

  static const _channel = MethodChannel('ph.sagip/sms');
  static const _replies = EventChannel('ph.sagip/sms/received');

  /// Texts that come in starting "S.A.G.I.P.:", such as the gateway's
  /// reply to an SOS text. Android passes on no other message. Never
  /// logged: they hold the sender's number.
  static Stream<({String from, String text})> replies() => _replies
      .receiveBroadcastStream()
      .handleError((Object _) {})
      .where((m) => m is Map && m['from'] is String && m['text'] is String)
      .map((m) {
        final map = m as Map;
        return (from: map['from'] as String, text: map['text'] as String);
      });

  /// The phone can text and the permission is granted.
  Future<bool> canSend() async {
    try {
      return await _channel.invokeMethod<bool>('canSend') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> compose(String number, String text) async {
    try {
      return await _channel.invokeMethod<bool>('compose', {
            'number': number,
            'text': text,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> send(String number, String text) async {
    try {
      return await _channel.invokeMethod<bool>('send', {
            'number': number,
            'text': text,
          }) ??
          false;
    } on Object {
      return false;
    }
  }
}
