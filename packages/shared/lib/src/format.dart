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

// Clock times are 24-hour ("army time"), as MDRRMD's operations center
// writes them (MDRRMD, 2026-11-10): "14:05", never "2:05 PM".

/// "14:05:09".
String formatClock(DateTime t, String locale) =>
    DateFormat.Hms(locale).format(t);

/// "14:05".
String formatTime(DateTime t, String locale) => DateFormat.Hm(locale).format(t);

/// "Sep 30, 2026".
String formatDate(DateTime t, String locale) =>
    DateFormat.yMMMd(locale).format(t);

/// "Nov 10, 2026 14:05".
String formatDateTime(DateTime t, String locale) =>
    DateFormat.yMMMd(locale).add_Hm().format(t);

/// A moment as short as it can be next to [now]: "14:05" today,
/// "Nov 9, 14:05" this year, "Nov 9, 2025, 14:05" before that.
String formatStamp(DateTime t, DateTime now, String locale) {
  final time = formatTime(t, locale);
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return time;
  }
  final day = t.year == now.year
      ? DateFormat.MMMd(locale).format(t)
      : DateFormat.yMMMd(locale).format(t);
  return '$day, $time';
}

String formatCoordinates(GeoPoint p) =>
    '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}';

/// "850 m" under a kilometer, then "1.2 km".
String formatDistance(double meters) => meters < 1000
    ? '${(meters / 10).round() * 10} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
