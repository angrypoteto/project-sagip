import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The assignment tone from the app's resources (`res/raw/sagip_assignment`,
/// played by `MainActivity.kt`, channel `ph.sagip/sound`). Falls back to the
/// phone's alert sound.
class DeviceAlertSound implements AlertSound {
  const DeviceAlertSound();

  static const _channel = MethodChannel('ph.sagip/sound');

  @override
  Future<void> playAssignment() async {
    try {
      await _channel.invokeMethod<void>('assignment');
    } on Object {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}
