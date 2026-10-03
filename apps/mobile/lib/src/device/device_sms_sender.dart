import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Tier 2 texts through Android's SMS service (`MainActivity.kt`,
/// channel `ph.sagip/sms`). Needs the SMS permission (S2 step 3); without
/// it, [compose] opens the messages app with the text ready instead.
class DeviceSmsSender implements SmsSender, SmsComposer {
  const DeviceSmsSender();

  static const _channel = MethodChannel('ph.sagip/sms');

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
