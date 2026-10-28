import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Calls through Android (`MainActivity.kt`, channel `ph.sagip/call`). The
/// first tap asks for the phone-call permission; with it the call starts at
/// once, without it the dialer opens with the number typed. Asked again
/// only while Android still allows asking.
class DevicePhoneCaller implements PhoneCaller {
  const DevicePhoneCaller();

  static const _channel = MethodChannel('ph.sagip/call');

  @override
  Future<CallOutcome> call(String number) async {
    var granted = false;
    try {
      var status = await Permission.phone.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        status = await Permission.phone.request();
      }
      granted = status.isGranted;
    } on Object {
      granted = false;
    }
    try {
      final answer = await _channel.invokeMethod<String>(
        granted ? 'call' : 'dial',
        {'number': number},
      );
      return switch (answer) {
        'calling' => CallOutcome.calling,
        'dialer' => CallOutcome.dialerOpened,
        _ => CallOutcome.unavailable,
      };
    } on Object {
      return CallOutcome.unavailable;
    }
  }
}
