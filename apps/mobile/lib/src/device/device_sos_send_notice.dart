import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The "Sending your SOS" notification (`MainActivity.kt`, channel
/// `ph.sagip/sos_notice`). Nothing happens if Android refuses it (for
/// example notifications turned off): R2 shows the same steps.
class DeviceSosSendNotice implements SosSendNotice {
  const DeviceSosSendNotice();

  static const _channel = MethodChannel('ph.sagip/sos_notice');

  @override
  Future<void> show({
    required String title,
    required String text,
    bool done = false,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'text': text,
        'done': done,
      });
    } on Object {
      // No notification; the app still sends the SOS.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on Object {
      // Nothing was shown.
    }
  }
}
