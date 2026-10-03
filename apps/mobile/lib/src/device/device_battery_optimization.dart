import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Android's battery optimization setting (`MainActivity.kt`, channel
/// `ph.sagip/battery`). The app is installed directly, not from Google Play,
/// so it may ask with the system dialog (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).
class DeviceBatteryOptimization implements BatteryOptimization {
  const DeviceBatteryOptimization();

  static const _channel = MethodChannel('ph.sagip/battery');

  @override
  Future<bool> isExempt() async {
    try {
      return await _channel.invokeMethod<bool>('isExempt') ?? true;
    } on Object {
      // No answer means no such setting to worry about.
      return true;
    }
  }

  @override
  Future<void> requestExemption() async {
    try {
      await _channel.invokeMethod<bool>('request');
    } on Object {
      // Nothing to show; the prompt stays until the phone says exempt.
    }
  }
}
