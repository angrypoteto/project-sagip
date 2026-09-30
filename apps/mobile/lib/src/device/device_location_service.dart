import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The phone's GPS (R1, R4, F4). Keeps the last fix when GPS is turned off,
/// so an SOS can still send it (plan R1), and flags fixes from a
/// mock-location app for the dispatcher (FR8). It does not ask for the
/// permission itself; the welcome steps (S2) do.
class DeviceLocationService implements LocationService {
  final _status = LiveValue(const LocationStatus(gpsOn: false));
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _service;
  Timer? _permissionCheck;
  var _started = false;

  @override
  Stream<LocationStatus> watch() {
    if (!_started) {
      _started = true;
      unawaited(_start());
    }
    return _status.watch();
  }

  static bool _allowed(LocationPermission p) =>
      p == LocationPermission.always || p == LocationPermission.whileInUse;

  Future<void> _start() async {
    _service = Geolocator.getServiceStatusStream().listen(
      (s) => _update(gpsOn: s == ServiceStatus.enabled),
      onError: (Object _) {},
    );
    await _checkPermission();
    // The permission may be granted later, on S2 or in Settings.
    _permissionCheck = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_checkPermission()),
    );
  }

  Future<void> _checkPermission() async {
    try {
      final allowed = _allowed(await Geolocator.checkPermission());
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!allowed) {
        await _positions?.cancel();
        _positions = null;
        _update(gpsOn: false);
        return;
      }
      _update(gpsOn: enabled);
      if (_positions != null) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _status.value.lastFix == null) _update(fix: last);
      _positions =
          Geolocator.getPositionStream(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              intervalDuration: const Duration(seconds: 5),
            ),
          ).listen(
            (p) => _update(gpsOn: true, fix: p),
            onError: (Object _) => _update(gpsOn: false),
          );
    } catch (_) {
      _update(gpsOn: false);
    }
  }

  void _update({bool? gpsOn, Position? fix}) {
    final current = _status.value;
    _status.value = LocationStatus(
      gpsOn: gpsOn ?? current.gpsOn,
      lastFix: fix == null ? current.lastFix : _fix(fix),
    );
  }

  static LocationFix _fix(Position p) {
    final point = GeoPoint(p.latitude, p.longitude);
    // Stands in for bundled barangay boundaries; the server decides.
    final near = nearestBarangay(point);
    return LocationFix(
      point: point,
      accuracyMeters: p.accuracy,
      at: p.timestamp.toLocal(),
      barangay: near?.name,
      district: near?.district,
      mockProvider: p.isMocked,
    );
  }

  @override
  Future<void> openSettings() async {
    final allowed = _allowed(await Geolocator.checkPermission());
    if (allowed) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  void dispose() {
    _permissionCheck?.cancel();
    unawaited(_positions?.cancel());
    unawaited(_service?.cancel());
  }
}
