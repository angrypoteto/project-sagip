import 'package:intl/intl.dart';

import 'models/geo_point.dart';

// Formatters used by both apps. Numbers that change on screen (timers,
// ETAs) should also use FontFeature.tabularFigures().

/// Wait timers: "04:12", or "1:04:12" past an hour. Tabular in the UI.
String formatWait(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// intl puts a narrow no-break space (U+202F) before AM/PM, which Plus Jakarta
// Sans does not draw ("7:44:12AM"). Use an ordinary no-break space instead.
String _spaced(String s) => s.replaceAll(' ', ' ');

String formatClock(DateTime t, String locale) =>
    _spaced(DateFormat.jms(locale).format(t));

String formatTime(DateTime t, String locale) =>
    _spaced(DateFormat.jm(locale).format(t));

String formatDateTime(DateTime t, String locale) =>
    _spaced(DateFormat.yMMMd(locale).add_jm().format(t));

String formatCoordinates(GeoPoint p) =>
    '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}';

/// "850 m" under a kilometer, then "1.2 km".
String formatDistance(double meters) => meters < 1000
    ? '${(meters / 10).round() * 10} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
