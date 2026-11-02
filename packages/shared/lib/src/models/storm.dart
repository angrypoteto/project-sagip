import 'package:flutter/foundation.dart';

import 'geo_point.dart';

// The typhoon tracker on the Heatmap page (2026-11-02): tropical cyclones
// from GDACS that touch the Philippine Area of Responsibility, and PAGASA's
// public CAP warnings. The ingest-storms Edge Function fills `storm_track`
// and `pagasa_warning`; dispatchers and admins read them.

/// The Philippine Area of Responsibility (PAGASA): the box PAGASA names
/// cyclones in and issues warnings for.
const parOutline = [
  GeoPoint(5, 115),
  GeoPoint(15, 115),
  GeoPoint(21, 120),
  GeoPoint(25, 120),
  GeoPoint(25, 135),
  GeoPoint(5, 135),
  GeoPoint(5, 115),
];

List<GeoPoint> _ring(Object? raw) => [
  for (final p in (raw as List? ?? const []))
    GeoPoint(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
];

List<List<GeoPoint>> _rings(Object? raw) => [
  for (final r in (raw as List? ?? const [])) _ring(r),
];

List<List<double>> _ringJson(List<GeoPoint> ring) => [
  for (final p in ring) [p.lat, p.lng],
];

DateTime? _time(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// One position of a cyclone's track, observed or forecast.
@immutable
class StormPoint {
  const StormPoint({
    required this.time,
    required this.at,
    this.category,
    this.forecast = false,
  });

  factory StormPoint.fromJson(Map<String, dynamic> json) => StormPoint(
    time: _time(json['t'])!,
    at: GeoPoint(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
    ),
    category: json['category'] as String?,
    forecast: json['forecast'] as bool? ?? false,
  );

  final DateTime time;
  final GeoPoint at;

  /// JTWC's category for the leg from here: TD, TS, TY (or HU), STY.
  final String? category;

  /// After the latest advisory: where it is expected to be.
  final bool forecast;

  Map<String, dynamic> toJson() => {
    't': time.toUtc().toIso8601String(),
    'lat': at.lat,
    'lng': at.lng,
    'category': category,
    'forecast': forecast,
  };
}

/// The area a cyclone's winds of at least [kmh] reached or are expected to.
@immutable
class WindZone {
  const WindZone({required this.kmh, required this.rings});

  factory WindZone.fromJson(Map<String, dynamic> json) =>
      WindZone(kmh: (json['kmh'] as num).toInt(), rings: _rings(json['rings']));

  final int kmh;
  final List<List<GeoPoint>> rings;

  Map<String, dynamic> toJson() => {
    'kmh': kmh,
    'rings': [for (final r in rings) _ringJson(r)],
  };
}

/// A tropical cyclone that touched PAR (GDACS, from JTWC advisories).
@immutable
class Storm {
  const Storm({
    required this.eventId,
    required this.name,
    required this.alertLevel,
    required this.isCurrent,
    required this.from,
    required this.to,
    this.updatedAt,
    this.maxWindKmh,
    this.source,
    this.track = const [],
    this.windZones = const [],
    this.cone = const [],
  });

  factory Storm.fromJson(Map<String, dynamic> json) => Storm(
    eventId: (json['event_id'] as num).toInt(),
    name: json['name'] as String,
    alertLevel: json['alert_level'] as String? ?? 'Green',
    isCurrent: json['is_current'] as bool? ?? false,
    from: _time(json['from_at'])!,
    to: _time(json['to_at'])!,
    updatedAt: _time(json['updated_at']),
    maxWindKmh: (json['max_wind_kmh'] as num?)?.round(),
    source: json['source'] as String?,
    track: [
      for (final p in (json['track'] as List? ?? const []))
        StormPoint.fromJson(p as Map<String, dynamic>),
    ],
    windZones: [
      for (final z in (json['wind_zones'] as List? ?? const []))
        WindZone.fromJson(z as Map<String, dynamic>),
    ],
    cone: _rings(json['cone']),
  );

  final int eventId;

  /// GDACS's name, for example "CHAMPI-26".
  final String name;

  /// GDACS's alert for the storm's impact: Green, Orange, or Red.
  final String alertLevel;

  /// Still active: GDACS issues advisories for it.
  final bool isCurrent;
  final DateTime from;

  /// The latest advisory.
  final DateTime to;
  final DateTime? updatedAt;

  /// The strongest sustained wind over its life.
  final int? maxWindKmh;
  final String? source;
  final List<StormPoint> track;

  /// Weakest first (60, 90, 120 km/h).
  final List<WindZone> windZones;
  final List<List<GeoPoint>> cone;

  /// The international name without the year: "CHAMPI".
  String get baseName => name.replaceFirst(RegExp(r'-\d+$'), '');

  /// The latest observed position (not a forecast).
  StormPoint? get latest {
    StormPoint? last;
    for (final p in track) {
      if (!p.forecast) last = p;
    }
    return last ?? (track.isEmpty ? null : track.first);
  }

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'name': name,
    'alert_level': alertLevel,
    'is_current': isCurrent,
    'from_at': from.toUtc().toIso8601String(),
    'to_at': to.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'max_wind_kmh': maxWindKmh,
    'source': source,
    'track': [for (final p in track) p.toJson()],
    'wind_zones': [for (final z in windZones) z.toJson()],
    'cone': [for (final r in cone) _ringJson(r)],
  };
}

/// An area a PAGASA warning covers: named, and outlined when PAGASA gives
/// the outline (flood advisories do; cyclone warnings name provinces).
@immutable
class WarningArea {
  const WarningArea({required this.name, this.rings = const []});

  factory WarningArea.fromJson(Map<String, dynamic> json) => WarningArea(
    name: json['name'] as String? ?? '',
    rings: _rings(json['rings']),
  );

  final String name;
  final List<List<GeoPoint>> rings;

  Map<String, dynamic> toJson() => {
    'name': name,
    'rings': [for (final r in rings) _ringJson(r)],
  };
}

/// One of PAGASA's public CAP alerts.
@immutable
class PagasaWarning {
  const PagasaWarning({
    required this.id,
    required this.kind,
    required this.event,
    required this.sentAt,
    this.headline,
    this.description,
    this.responseType,
    this.signalLevel,
    this.expiresAt,
    this.refs = const [],
    this.areas = const [],
  });

  factory PagasaWarning.fromJson(Map<String, dynamic> json) => PagasaWarning(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'other',
    event: json['event'] as String,
    sentAt: _time(json['sent_at'])!,
    headline: json['headline'] as String?,
    description: json['description'] as String?,
    responseType: json['response_type'] as String?,
    signalLevel: (json['signal_level'] as num?)?.toInt(),
    expiresAt: _time(json['expires_at']),
    refs: [for (final r in (json['refs'] as List? ?? const [])) r as String],
    areas: [
      for (final a in (json['areas'] as List? ?? const []))
        WarningArea.fromJson(a as Map<String, dynamic>),
    ],
  );

  final String id;

  /// wcp: tropical cyclone warning; gfa: general flood advisory.
  final String kind;
  final String event;
  final DateTime sentAt;
  final String? headline;
  final String? description;

  /// "AllClear" ends an earlier warning.
  final String? responseType;

  /// The tropical cyclone wind signal (1 to 5), on cyclone warnings.
  final int? signalLevel;
  final DateTime? expiresAt;

  /// The warnings this one updates or ends.
  final List<String> refs;
  final List<WarningArea> areas;

  bool get isFlood => kind == 'gfa';
  bool get isAllClear => responseType == 'AllClear';

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'event': event,
    'sent_at': sentAt.toUtc().toIso8601String(),
    'headline': headline,
    'description': description,
    'response_type': responseType,
    'signal_level': signalLevel,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'refs': refs,
    'areas': [for (final a in areas) a.toJson()],
  };
}

/// What the typhoon tracker shows: the storms and PAGASA's warnings.
@immutable
class HazardFeeds {
  const HazardFeeds({this.storms = const [], this.warnings = const []});

  static const empty = HazardFeeds();

  /// Newest first.
  final List<Storm> storms;

  /// Newest first.
  final List<PagasaWarning> warnings;

  /// The cyclone GDACS still follows, if any.
  Storm? get current {
    for (final s in storms) {
      if (s.isCurrent) return s;
    }
    return null;
  }

  /// The latest cyclone to touch PAR, current or not.
  Storm? get latest => storms.isEmpty
      ? null
      : storms.reduce((a, b) => b.to.isAfter(a.to) ? b : a);

  /// The warnings in force at [now]: not expired, not an all-clear, and not
  /// replaced by a later warning. Highest signal first, then newest.
  List<PagasaWarning> activeAt(DateTime now) {
    final replaced = {for (final w in warnings) ...w.refs};
    final out = [
      for (final w in warnings)
        if (!w.isAllClear &&
            !replaced.contains(w.id) &&
            (w.expiresAt == null || w.expiresAt!.isAfter(now)))
          w,
    ];
    out.sort((a, b) {
      final s = (b.signalLevel ?? 0).compareTo(a.signalLevel ?? 0);
      return s != 0 ? s : b.sentAt.compareTo(a.sentAt);
    });
    return out;
  }

  /// PAGASA's local name for [storm], from a warning that names both
  /// ("Typhoon Rosal (CHAMPI)"); null when no warning does.
  String? localName(Storm storm) {
    final pattern = RegExp(
      r'([A-Z][A-Za-z]+)\s*\(' + RegExp.escape(storm.baseName) + r'\)',
      caseSensitive: false,
    );
    for (final w in warnings) {
      final m = pattern.firstMatch(w.headline ?? '');
      if (m != null) {
        final n = m.group(1)!;
        return n[0].toUpperCase() + n.substring(1).toLowerCase();
      }
    }
    return null;
  }
}
