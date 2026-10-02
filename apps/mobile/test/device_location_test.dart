import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sagip_mobile/src/device/device_location_service.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Stands in for the phone's location plugin: records how positions were
/// asked for and lets the test hand out fixes.
class _FakeGeolocator extends GeolocatorPlatform {
  var permission = LocationPermission.whileInUse;
  final asked = <LocationSettings?>[];
  final streams = <StreamController<Position>>[];

  int get listening => streams.where((s) => s.hasListener).length;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Stream<ServiceStatus> getServiceStatusStream() => const Stream.empty();

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    asked.add(locationSettings);
    final stream = StreamController<Position>();
    streams.add(stream);
    return stream.stream;
  }
}

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 2, 9),
  accuracy: 6,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

const BackgroundNotice _notice = (
  title: 'S.A.G.I.P. is sharing your location',
  text: 'MDRRMD dispatch sees your unit while you are signed in.',
  channel: 'Unit location sharing',
);

/// Background GPS for a responder on duty (FR9, plan part 7).
void main() {
  late _FakeGeolocator phone;
  late DeviceLocationService service;

  ForegroundNotificationConfig? noticeOf(LocationSettings? s) =>
      (s! as AndroidSettings).foregroundNotificationConfig;

  setUp(() {
    phone = _FakeGeolocator();
    GeolocatorPlatform.instance = phone;
    service = DeviceLocationService(
      recheckEvery: const Duration(milliseconds: 20),
    );
  });

  tearDown(() => service.dispose());

  test('the settings: a foreground service only with a notice', () {
    final plain = androidLocationSettings(null);
    expect(plain.foregroundNotificationConfig, isNull);
    expect(plain.accuracy, LocationAccuracy.high);

    final duty = androidLocationSettings(_notice);
    final config = duty.foregroundNotificationConfig!;
    expect(config.notificationTitle, _notice.title);
    expect(config.notificationText, _notice.text);
    expect(config.notificationChannelName, _notice.channel);
    expect(config.enableWakeLock, isTrue, reason: 'or the phone sleeps');
    expect(config.setOngoing, isTrue, reason: 'it cannot be swiped away');
    // Same accuracy and pace either way.
    expect(duty.accuracy, plain.accuracy);
    expect(duty.distanceFilter, plain.distanceFilter);
    expect(duty.intervalDuration, plain.intervalDuration);
  });

  test('a resident never shares in the background', () async {
    final seen = <LocationStatus>[];
    final sub = service.watch().listen(seen.add);
    await pumpEventQueue();
    expect(phone.asked, hasLength(1));
    expect(noticeOf(phone.asked.single), isNull);

    phone.streams.single.add(_position(14.6091, 120.9925));
    await pumpEventQueue();
    expect(seen.last.gpsOn, isTrue);
    expect(seen.last.lastFix!.point.lat, 14.6091);
    await sub.cancel();
  });

  test(
    'a responder on duty: restarted behind the notice, then without it',
    () async {
      final seen = <LocationStatus>[];
      final sub = service.watch().listen(seen.add);
      await pumpEventQueue();

      // Signed in as a responder.
      await service.setBackground(_notice);
      expect(phone.asked, hasLength(2));
      expect(noticeOf(phone.asked.last)!.notificationTitle, _notice.title);
      expect(phone.listening, 1, reason: 'the first stream was stopped');

      // The same notice again changes nothing.
      await service.setBackground(_notice);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(phone.asked, hasLength(2), reason: 'rechecks do not restart it');

      // Fixes still arrive, and the last one is kept.
      phone.streams.last.add(_position(14.6045, 121.0010));
      await pumpEventQueue();
      expect(seen.last.lastFix!.point.lng, 121.0010);

      // Signed out: no more background sharing.
      await service.setBackground(null);
      expect(phone.asked, hasLength(3));
      expect(noticeOf(phone.asked.last), isNull);
      expect(phone.listening, 1);
      expect(seen.last.lastFix!.point.lng, 121.0010, reason: 'the fix is kept');
      await sub.cancel();
    },
  );

  test('without the location permission nothing starts', () async {
    phone.permission = LocationPermission.denied;
    final seen = <LocationStatus>[];
    final sub = service.watch().listen(seen.add);
    await service.setBackground(_notice);
    await pumpEventQueue();
    expect(phone.asked, isEmpty);
    expect(seen.last.gpsOn, isFalse);

    // Granted later (S2 or Settings): it starts behind the notice.
    phone.permission = LocationPermission.whileInUse;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(phone.asked, hasLength(1));
    expect(noticeOf(phone.asked.single), isNotNull);
    await sub.cancel();
  });
}
