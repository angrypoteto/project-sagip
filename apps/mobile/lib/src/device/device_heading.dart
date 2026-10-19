import 'package:flutter/services.dart';

/// Which way the phone is facing, in degrees from north, from Android's
/// rotation sensor (`Compass.kt`, channel `ph.sagip/heading`). Nothing on a
/// phone without one, or on platforms without the channel.
Stream<double> deviceHeading() =>
    const EventChannel('ph.sagip/heading')
        .receiveBroadcastStream()
        .where((e) => e is num)
        .map((e) => (e as num).toDouble())
        .handleError((Object _) {});
