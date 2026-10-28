import 'package:flutter/services.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Opens the phone's contacts app with MDRRMD's numbers filled in
/// (`MainActivity.kt`, channel `ph.sagip/contacts`). No contacts permission:
/// the person taps Save in their contacts app.
class DeviceContactSaver implements ContactSaver {
  const DeviceContactSaver();

  static const _channel = MethodChannel('ph.sagip/contacts');

  @override
  Future<bool> save({
    required String name,
    required String company,
    required String mobile,
    String? otherNumber,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('save', {
            'name': name,
            'company': company,
            'mobile': mobile,
            'other': otherNumber,
          }) ??
          false;
    } on Object {
      return false;
    }
  }
}
