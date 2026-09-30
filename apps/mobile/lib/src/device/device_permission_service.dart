import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Android permissions for the welcome steps (S2) and Me (S7).
/// Android cannot tell "never asked" from "refused once", so the phone
/// remembers which ones the app has asked for.
class DevicePermissionService implements PermissionService {
  DevicePermissionService(this._store);

  final LocalStore _store;
  final _state = LiveValue<Map<AppPermission, PermissionState>>({
    for (final p in AppPermission.values) p: PermissionState.notAsked,
  });
  var _loaded = false;

  static List<Permission> _android(AppPermission p) => switch (p) {
    AppPermission.location => [Permission.locationWhenInUse],
    AppPermission.notifications => [Permission.notification],
    AppPermission.sms => [Permission.sms],
    AppPermission.nearbyDevices => [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ],
  };

  String _askedKey(AppPermission p) => 'permission-asked:${p.name}';

  Future<PermissionState> _read(AppPermission p) async {
    final statuses = [for (final x in _android(p)) await x.status];
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return PermissionState.granted;
    }
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return PermissionState.permanentlyDenied;
    }
    return _store.read(_askedKey(p)) == 'yes'
        ? PermissionState.denied
        : PermissionState.notAsked;
  }

  Future<void> _refresh() async {
    _state.value = {for (final p in AppPermission.values) p: await _read(p)};
  }

  @override
  Stream<Map<AppPermission, PermissionState>> watch() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_refresh());
    }
    return _state.watch();
  }

  @override
  Future<PermissionState> request(AppPermission permission) async {
    await _store.write(_askedKey(permission), 'yes');
    for (final p in _android(permission)) {
      await p.request();
    }
    final result = await _read(permission);
    _state.value = {..._state.value, permission: result};
    return result;
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
    // The resident may change them there; read them again on return.
    await Future<void>.delayed(const Duration(seconds: 1));
    await _refresh();
  }
}
