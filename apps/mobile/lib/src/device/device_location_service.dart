import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The words on the Android notification that stays up while positions
/// are shared in the background.
typedef BackgroundNotice = ({String title, String text, String channel});

/// How the phone is asked for positions. With a [notice], Android runs the
/// updates as a foreground service: they keep coming with the screen off
/// or another app open, and the notification says so for as long as they
/// do. The service starts while the app is open, so the usual "While using
/// the app" location permission is enough.
@visibleForTesting
AndroidSettings androidLocationSettings(BackgroundNotice? notice) =>
    AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: notice == null
          ? null
          : ForegroundNotificationConfig(
              notificationTitle: notice.title,
              notificationText: notice.text,
              notificationChannelName: notice.channel,
              // Without it the phone sleeps and hands over every position
              // at once when it wakes.
              enableWakeLock: true,
              setOngoing: true,
            ),
    );

/// The phone's GPS (R1, R4, F4). Keeps the last fix when GPS is turned off,
/// so an SOS can still send it (plan R1), and flags fixes from a
/// mock-location app for the dispatcher (FR8). It does not ask for the
/// permission itself; the welcome steps (S2) do.
class DeviceLocationService implements LocationService {
  DeviceLocationService({this.recheckEvery = const Duration(seconds: 5)});

  /// How often the permission is checked again.
  final Duration recheckEvery;

  final _status = LiveValue(const LocationStatus(gpsOn: false));
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _service;
  Timer? _permissionCheck;
  var _started = false;
  var _checking = false;

  /// Set while a responder is signed in (FR9); null for residents.
  BackgroundNotice? _background;

  /// What the running position stream was started with.
  BackgroundNotice? _running;

  @override
  Stream<LocationStatus> watch() {
    if (!_started) {
      _started = true;
      unawaited(_start());
    }
    return _status.watch();
  }

  /// Keeps positions coming in the background behind [notice], or stops
  /// doing so with null. Called when a responder signs in and out: dispatch
  /// must see a unit that is driving with the phone in a pocket (FR9), and
  /// a resident's phone never shares anything in the background.
  Future<void> setBackground(BackgroundNotice? notice) async {
    _background = notice;
    if (_started) await _checkPermission();
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
      recheckEvery,
      (_) => unawaited(_checkPermission()),
    );
  }

  Future<void> _checkPermission() async {
    // One at a time: two overlapping checks would start two streams. A
    // change that arrives meanwhile is picked up by the next check.
    if (_checking) return;
    _checking = true;
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
      final wanted = _background;
      if (_positions != null && _running == wanted) return;
      // Start, or start again with or without the background notice.
      await _positions?.cancel();
      _positions = null;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _status.value.lastFix == null) _update(fix: last);
      _running = wanted;
      _positions =
          Geolocator.getPositionStream(
            locationSettings: androidLocationSettings(wanted),
          ).listen(
            (p) => _update(gpsOn: true, fix: p),
            onError: (Object _) => _update(gpsOn: false),
          );
    } catch (_) {
      _update(gpsOn: false);
    } finally {
      _checking = false;
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
