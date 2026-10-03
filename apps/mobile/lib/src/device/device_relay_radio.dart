import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Tier 3 over the phone's Bluetooth LE (`BleRelay.kt`, channels
/// `ph.sagip/relay` and `ph.sagip/relay/heard`). Needs the Nearby devices
/// permission (S2 step 3); without it nothing is advertised or heard.
class DeviceRelayRadio implements RelayRadio {
  const DeviceRelayRadio();

  static const _methods = MethodChannel('ph.sagip/relay');
  static const _events = EventChannel('ph.sagip/relay/heard');

  /// The phone's hardware can advertise (Bluetooth may be off right now).
  static Future<bool> hasHardware() async {
    try {
      return await _methods.invokeMethod<bool>('hasHardware') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isSupported() async {
    try {
      return await _methods.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> advertise(String key, Uint8List packet) async {
    try {
      return await _methods.invokeMethod<bool>('advertise', {
            'key': key,
            'packet': packet,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop(String key) async {
    try {
      await _methods.invokeMethod<void>('stop', {'key': key});
    } on Object {
      // Nothing was advertised.
    }
  }

  @override
  Stream<Uint8List> heard() => _events
      .receiveBroadcastStream()
      .where((e) => e is Uint8List)
      .cast<Uint8List>();
}
