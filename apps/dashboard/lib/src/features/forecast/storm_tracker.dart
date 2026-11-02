import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// The typhoon tracker on the Heatmap page (Joshua, 2026-11-02, styled after
// UP NOAH's typhoon track page the same day): a switch, shown for flood and
// storm surge, that zooms the map out to the Philippines over Himawari
// satellite imagery and draws the cyclone that touched PAR (track with a
// category marker per position, forecast cone, wind zones; GDACS), PAGASA's
// flood advisory areas, and NASA's satellite rainfall. Its options, key,
// and the storm's details are in a panel on the right.

/// Where the map looks with the tracker on: PAR in the middle.
const trackerCenter = LatLng(14.5, 123.0);
const trackerZoom = 5.2;
const trackerMinZoom = 4.0;
final trackerCameraConstraint = CameraConstraint.containCenter(
  bounds: LatLngBounds(const LatLng(-2, 102), const LatLng(32, 150)),
);

/// NASA GIBS: Himawari's clean infrared band, every 10 minutes (about 45
/// minutes behind). Its tiles go to zoom 6.
const himawariTileUrl =
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
    'Himawari_AHI_Band13_Clean_Infrared/default/default/'
    'GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';

/// NASA GIBS: coastlines (a still layer), drawn over the satellite picture
/// so the islands stay readable even where a picture tile fails to load.
const coastlineTileUrl =
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
    'Coastlines_15m/default/GoogleMapsCompatible_Level13/{z}/{y}/{x}.png';

/// Coastlines in white at 70%, over the blue picture.
final _coastTint = ColorFilter.matrix(const <double>[
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0.7, 0, //
]);

/// NASA GIBS: IMERG precipitation rate, the latest half hour (about 6
/// hours behind). Its tiles go to zoom 6.
const imergTileUrl =
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
    'IMERG_Precipitation_Rate_30min/default/default/'
    'GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';

/// Turns NASA's gray infrared into blue sky and white cloud, as NOAH shows
/// it: brightness 98 (clear sky) becomes a deep blue, 200 (high cloud)
/// white; the colours NASA gives the coldest cloud tops are kept.
final satelliteTint = ColorFilter.matrix(_tint());

List<double> _tint() {
  const base = [20.0, 58.0, 160.0];
  const lo = 98.0, hi = 200.0;
  const lum = [0.299, 0.587, 0.114];
  final m = <double>[];
  for (var c = 0; c < 3; c++) {
    final k = (255 - base[c]) / (hi - lo);
    for (var i = 0; i < 3; i++) {
      m.add(lum[i] * (k - 1) + (i == c ? 1 : 0));
    }
    m.addAll([0, base[c] - k * lo]);
  }
  m.addAll([0, 0, 0, 1, 0]);
  return m;
}

/// Which of the tracker's layers are shown, and how strongly.
@immutable
class TrackerLayers {
  const TrackerLayers({
    this.track = true,
    this.satellite = true,
    this.satelliteOpacity = 0.85,
    this.rainfall = false,
    this.rainfallOpacity = 0.7,
    this.warnings = true,
  });

  final bool track;
  final bool satellite;
  final double satelliteOpacity;
  final bool rainfall;
  final double rainfallOpacity;
  final bool warnings;

  TrackerLayers copyWith({
    bool? track,
    bool? satellite,
    double? satelliteOpacity,
    bool? rainfall,
    double? rainfallOpacity,
    bool? warnings,
  }) => TrackerLayers(
    track: track ?? this.track,
    satellite: satellite ?? this.satellite,
    satelliteOpacity: satelliteOpacity ?? this.satelliteOpacity,
    rainfall: rainfall ?? this.rainfall,
    rainfallOpacity: rainfallOpacity ?? this.rainfallOpacity,
    warnings: warnings ?? this.warnings,
  );
}

/// The categories GDACS gives a cyclone's legs (JTWC's). It gives no wind
/// per position, so PAGASA's severe tropical storm cannot be told apart.
enum StormCategory {
  superTyphoon,
  typhoon,
  tropicalStorm,
  tropicalDepression,
  other;

  static StormCategory of(String? code) => switch (code?.toUpperCase()) {
    'STY' || 'ST' => superTyphoon,
    'TY' || 'HU' => typhoon,
    'TS' || 'STS' => tropicalStorm,
    'TD' => tropicalDepression,
    _ => other,
  };
}

List<LatLng> _points(List<GeoPoint> ring) => [
  for (final p in ring) toLatLng(p),
];

/// The storm to draw: the current one, else the latest to touch PAR.
Storm? trackedStorm(HazardFeeds feeds) => feeds.current ?? feeds.latest;

/// The tracker's map layers, drawn over the base map.
List<Widget> trackerMapLayers({
  required BuildContext context,
  required HazardFeeds feeds,
  required TrackerLayers layers,
  required bool tiles,
  required DateTime now,
}) {
  final p = SagipPalette.of(context);
  final storm = trackedStorm(feeds);
  // A storm that has ended is drawn faint: a reference, not a threat.
  final strength = storm?.isCurrent ?? false ? 1.0 : 0.55;
  // Over the blue satellite picture, lines are white.
  final ink = layers.satellite && tiles ? SagipColors.porcelain : p.textPrimary;
  final floods = [
    for (final w in feeds.activeAt(now))
      if (w.isFlood)
        for (final a in w.areas)
          for (final r in a.rings) r,
  ];
  return [
    if (layers.satellite && tiles)
      GibsTiles(
        key: const ValueKey('tracker-satellite'),
        url: himawariTileUrl,
        maxNativeZoom: 6,
        opacity: layers.satelliteOpacity,
        tint: satelliteTint,
        // A new picture every 10 minutes, never cached by the browser.
        refreshEvery: const Duration(minutes: 10),
      ),
    if (layers.rainfall && tiles)
      GibsTiles(
        key: const ValueKey('tracker-rainfall'),
        url: imergTileUrl,
        maxNativeZoom: 6,
        opacity: layers.rainfallOpacity,
        refreshEvery: const Duration(minutes: 30),
      ),
    if (tiles)
      GibsTiles(
        key: const ValueKey('tracker-coast'),
        url: coastlineTileUrl,
        maxNativeZoom: 13,
        tint: _coastTint,
      ),
    PolylineLayer(
      key: const ValueKey('tracker-par'),
      polylines: [
        Polyline(
          points: _points(parOutline),
          color: ink.withValues(alpha: 0.75),
          strokeWidth: 1.5,
        ),
      ],
    ),
    if (layers.warnings && floods.isNotEmpty)
      PolygonLayer(
        key: const ValueKey('tracker-floods'),
        polygons: [
          for (final r in floods)
            Polygon(
              points: _points(r),
              color: p.info.fill.withValues(alpha: 0.2),
              borderColor: p.info.fill,
              borderStrokeWidth: 1.2,
            ),
        ],
      ),
    if (layers.track && storm != null) ...[
      PolygonLayer(
        key: const ValueKey('tracker-zones'),
        polygons: [
          for (final r in storm.cone)
            Polygon(
              points: _points(r),
              color: ink.withValues(alpha: 0.1 * strength),
              borderColor: ink.withValues(alpha: 0.7 * strength),
              borderStrokeWidth: 1,
              pattern: StrokePattern.dashed(segments: [6, 5]),
            ),
          for (final z in storm.windZones)
            for (final r in z.rings)
              Polygon(
                points: _points(r),
                color: windColor(z.kmh, p).withValues(alpha: 0.16 * strength),
                borderColor: windColor(
                  z.kmh,
                  p,
                ).withValues(alpha: 0.8 * strength),
                borderStrokeWidth: 1,
              ),
        ],
      ),
      PolylineLayer(
        key: const ValueKey('tracker-track'),
        polylines: [
          Polyline(
            points: [
              for (final t in storm.track)
                if (!t.forecast) toLatLng(t.at),
            ],
            color: ink.withValues(alpha: 0.9 * strength),
            strokeWidth: 2.5,
          ),
          Polyline(
            points: [
              if (storm.latest case final last?) toLatLng(last.at),
              for (final t in storm.track)
                if (t.forecast) toLatLng(t.at),
            ],
            color: ink.withValues(alpha: 0.9 * strength),
            strokeWidth: 2.5,
            pattern: StrokePattern.dashed(segments: [6, 6]),
          ),
        ],
      ),
      MarkerLayer(
        key: const ValueKey('tracker-markers'),
        markers: [
          for (final t in storm.track)
            if (!identical(t, storm.latest))
              Marker(
                point: toLatLng(t.at),
                width: 20,
                height: 20,
                child: Opacity(
                  opacity: strength,
                  child: CategoryMarker(
                    category: StormCategory.of(t.category),
                    forecast: t.forecast,
                    size: 18,
                  ),
                ),
              ),
          if (storm.latest case final last?)
            Marker(
              key: const ValueKey('tracker-eye'),
              point: toLatLng(last.at),
              width: 34,
              height: 34,
              child: Opacity(
                opacity: storm.isCurrent ? 1 : 0.8,
                child: CategoryMarker(
                  category: StormCategory.of(last.category),
                  size: 30,
                ),
              ),
            ),
        ],
      ),
    ],
  ];
}

/// One NASA GIBS layer. GIBS sometimes answers 503 for a few minutes while
/// it publishes a new picture (seen 2026-11-02 around 01:00 UTC): a failed
/// tile (other than 404, which GIBS gives where there is nothing to draw)
/// makes the layer try again 30 seconds later, and [refreshEvery] fetches
/// the newest picture.
class GibsTiles extends StatefulWidget {
  const GibsTiles({
    super.key,
    required this.url,
    required this.maxNativeZoom,
    this.opacity = 1,
    this.tint,
    this.refreshEvery,
  });

  final String url;
  final int maxNativeZoom;
  final double opacity;
  final ColorFilter? tint;
  final Duration? refreshEvery;

  @override
  State<GibsTiles> createState() => _GibsTilesState();
}

class _GibsTilesState extends State<GibsTiles> {
  final _reset = StreamController<void>.broadcast();
  Timer? _retry;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    if (widget.refreshEvery case final every?) {
      _refresh = Timer.periodic(every, (_) => _reset.add(null));
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _refresh?.cancel();
    _reset.close();
    super.dispose();
  }

  void _failed(TileImage tile, Object error, StackTrace? stack) {
    if (error is NetworkImageLoadException && error.statusCode == 404) return;
    _retry ??= Timer(const Duration(seconds: 30), () {
      _retry = null;
      if (mounted) _reset.add(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final layer = TileLayer(
      urlTemplate: widget.url,
      maxNativeZoom: widget.maxNativeZoom,
      userAgentPackageName: 'ph.sagip.dashboard',
      panBuffer: 0,
      reset: _reset.stream,
      // flutter_map's default loading: with a throttle or debounce the
      // layers missed the zoom-out to the Philippines and loaded nothing
      // (checked in Chrome, 2026-11-02).
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
      errorTileCallback: _failed,
      tileDisplay: TileDisplay.instantaneous(opacity: widget.opacity),
    );
    final tint = widget.tint;
    return tint == null
        ? layer
        : ColorFiltered(colorFilter: tint, child: layer);
  }
}

/// The color of a wind zone: 60 km/h ember, 120 km/h and up signal.
Color windColor(int kmh, SagipPalette p) => switch (kmh) {
  < 80 => p.warning.fill,
  < 110 => Color.lerp(p.warning.fill, p.critical.fill, 0.5)!,
  _ => p.critical.fill,
};

/// A cyclone category's colour: stronger is hotter.
SagipTone categoryTone(StormCategory c, SagipPalette p) => switch (c) {
  StormCategory.superTyphoon || StormCategory.typhoon => p.critical,
  StormCategory.tropicalStorm => p.warning,
  StormCategory.tropicalDepression => p.info,
  StormCategory.other => p.neutral,
};

/// One position of a track: a disc with the category's letter (D, S, T),
/// or the cyclone symbol for a super typhoon. Forecast positions are
/// hollow. Shape and letter carry the category, not colour alone.
class CategoryMarker extends StatelessWidget {
  const CategoryMarker({
    super.key,
    required this.category,
    this.forecast = false,
    this.size = 18,
  });

  final StormCategory category;
  final bool forecast;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final tone = categoryTone(category, p);
    // Ember takes dark text; the other fills take white.
    final onFill = identical(tone, p.warning)
        ? SagipColors.bay
        : SagipColors.porcelain;
    final mark = forecast ? tone.fill : onFill;
    final letter = switch (category) {
      StormCategory.typhoon => 'T',
      StormCategory.tropicalStorm => 'S',
      StormCategory.tropicalDepression => 'D',
      _ => null,
    };
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: forecast ? SagipColors.porcelain : tone.fill,
          shape: BoxShape.circle,
          border: Border.all(
            color: forecast ? tone.fill : SagipColors.porcelain,
            width: size > 24 ? 2 : 1.5,
          ),
        ),
        child: letter != null
            ? Text(
                letter,
                style: TextStyle(
                  fontSize: size * 0.55,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: mark,
                ),
              )
            : Icon(
                category == StormCategory.superTyphoon
                    ? Symbols.cyclone_rounded
                    : Symbols.circle_rounded,
                size: size * (category == StormCategory.other ? 0.4 : 0.75),
                color: mark,
              ),
      ),
    );
  }
}

/// The tracker's panel on the right: the storm, the layers with their
/// sources and opacity, PAGASA's warnings in force, and the key.
class TrackerPanel extends ConsumerWidget {
  const TrackerPanel({
    super.key,
    required this.layers,
    required this.onLayers,
    required this.onClose,
  });

  final TrackerLayers layers;
  final ValueChanged<TrackerLayers> onLayers;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final feeds = ref.watch(hazardFeedsProvider);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: SagipSpace.xl, bottom: SagipSpace.sm),
      child: Text(
        title,
        style: text.labelMedium!.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return ListView(
      key: const ValueKey('tracker-panel'),
      padding: const EdgeInsets.all(SagipSpace.lg),
      children: [
        Row(
          children: [
            Icon(Symbols.cyclone_rounded, size: 20, color: p.textSecondary),
            const SizedBox(width: SagipSpace.sm),
            Expanded(child: Text(l10n.trackerTitle, style: text.titleLarge)),
            IconButton(
              key: const ValueKey('tracker-close'),
              tooltip: l10n.close,
              onPressed: onClose,
              icon: const Icon(Symbols.close_rounded),
            ),
          ],
        ),
        switch (feeds) {
          AsyncData(:final value) => _StormSummary(feeds: value),
          AsyncError() => Padding(
            padding: const EdgeInsets.only(top: SagipSpace.sm),
            child: Text(l10n.trackerError, style: text.bodySmall),
          ),
          _ => Padding(
            padding: const EdgeInsets.only(top: SagipSpace.sm),
            child: Text(l10n.trackerLoading, style: text.bodySmall),
          ),
        },
        section(l10n.trackerLayersTitle),
        _LayerRow(
          key: const ValueKey('tracker-layer-track'),
          title: l10n.trackerLayerTrack,
          source: l10n.trackerSourceTrack,
          value: layers.track,
          onChanged: (v) => onLayers(layers.copyWith(track: v)),
        ),
        _LayerRow(
          key: const ValueKey('tracker-layer-satellite'),
          title: l10n.trackerLayerSatellite,
          source: l10n.trackerSourceSatellite,
          value: layers.satellite,
          onChanged: (v) => onLayers(layers.copyWith(satellite: v)),
          opacity: layers.satelliteOpacity,
          onOpacity: (v) => onLayers(layers.copyWith(satelliteOpacity: v)),
        ),
        _LayerRow(
          key: const ValueKey('tracker-layer-rainfall'),
          title: l10n.trackerLayerRainfall,
          source: l10n.trackerSourceRainfall,
          value: layers.rainfall,
          onChanged: (v) => onLayers(layers.copyWith(rainfall: v)),
          opacity: layers.rainfallOpacity,
          onOpacity: (v) => onLayers(layers.copyWith(rainfallOpacity: v)),
        ),
        _LayerRow(
          key: const ValueKey('tracker-layer-warnings'),
          title: l10n.trackerLayerWarnings,
          source: l10n.trackerSourceWarnings,
          value: layers.warnings,
          onChanged: (v) => onLayers(layers.copyWith(warnings: v)),
        ),
        if (feeds.value case final value?) _Warnings(feeds: value),
        section(l10n.trackerKeyTitle),
        Wrap(
          runSpacing: SagipSpace.sm,
          children: [
            for (final c in const [
              StormCategory.superTyphoon,
              StormCategory.typhoon,
              StormCategory.tropicalStorm,
              StormCategory.tropicalDepression,
            ])
              SizedBox(
                width: 150,
                child: Row(
                  children: [
                    CategoryMarker(category: c, size: 22),
                    const SizedBox(width: SagipSpace.sm),
                    Expanded(
                      child: Text(
                        _categoryName(l10n, c),
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: SagipSpace.md),
        _KeyRow(
          swatch: _Swatch.line(p.textPrimary, dashed: false),
          label: l10n.trackerKeyTrack,
        ),
        _KeyRow(
          swatch: _Swatch.line(p.textPrimary, dashed: true),
          label: l10n.trackerKeyForecast,
        ),
        _KeyRow(
          swatch: _Swatch.area(p.textSecondary, dashed: true),
          label: l10n.trackerKeyCone,
        ),
        for (final kmh in const [60, 90, 120])
          _KeyRow(
            swatch: _Swatch.area(windColor(kmh, p)),
            label: l10n.trackerKeyWind(kmh),
          ),
        _KeyRow(swatch: _Swatch.area(p.info.fill), label: l10n.trackerKeyFlood),
        _KeyRow(
          swatch: _Swatch.line(p.textSecondary, dashed: false),
          label: l10n.trackerKeyPar,
        ),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.trackerKeyNote,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        section(l10n.trackerAboutTitle),
        Text(l10n.trackerSources, style: text.bodySmall),
      ],
    );
  }
}

String _categoryName(AppLocalizations l10n, StormCategory c) => switch (c) {
  StormCategory.superTyphoon => l10n.trackerCategorySty,
  StormCategory.typhoon => l10n.trackerCategoryTy,
  StormCategory.tropicalStorm => l10n.trackerCategoryTs,
  StormCategory.tropicalDepression => l10n.trackerCategoryTd,
  StormCategory.other => l10n.trackerCategoryOther,
};

/// The storm being shown: its names, whether it is active, its category,
/// strongest wind, and latest advisory.
class _StormSummary extends StatelessWidget {
  const _StormSummary({required this.feeds});

  final HazardFeeds feeds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final storm = trackedStorm(feeds);
    if (storm == null) {
      return Padding(
        padding: const EdgeInsets.only(top: SagipSpace.sm),
        child: Text(l10n.trackerNoStorm, style: text.bodyMedium),
      );
    }
    final category = StormCategory.of(storm.latest?.category);
    return Container(
      margin: const EdgeInsets.only(top: SagipSpace.md),
      padding: const EdgeInsets.all(SagipSpace.md),
      decoration: BoxDecoration(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(SagipRadius.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryMarker(category: category, size: 28),
              const SizedBox(width: SagipSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (feeds.localName(storm)) {
                        final local? => l10n.trackerStormLocal(
                          storm.baseName,
                          local,
                        ),
                        null => storm.baseName,
                      },
                      key: const ValueKey('tracker-storm-name'),
                      style: text.titleSmall,
                    ),
                    Text(_categoryName(l10n, category), style: text.bodySmall),
                  ],
                ),
              ),
              SagipChip(
                label: storm.isCurrent ? l10n.trackerActive : l10n.trackerEnded,
                tone: storm.isCurrent ? p.critical : p.neutral,
                icon: storm.isCurrent
                    ? Symbols.cyclone_rounded
                    : Symbols.history_rounded,
              ),
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          if (!storm.isCurrent)
            Text(l10n.trackerNoStormNow, style: text.bodySmall),
          if (storm.maxWindKmh case final w?)
            Text(l10n.trackerMaxWind(w), style: text.bodySmall),
          Text(
            l10n.trackerAdvisory(formatDateTime(storm.to.toLocal(), locale)),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// PAGASA's warnings in force: signal levels by province, flood advisories.
class _Warnings extends ConsumerWidget {
  const _Warnings({required this.feeds});

  final HazardFeeds feeds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final warnings = feeds.activeAt(now);
    return Padding(
      padding: const EdgeInsets.only(
        left: 40,
        top: SagipSpace.xs,
        bottom: SagipSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warnings.isEmpty)
            Text(
              l10n.trackerNoWarnings,
              style: text.bodySmall!.copyWith(color: p.textSecondary),
            ),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: SagipSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (w.isFlood)
                    SagipChip(
                      label: l10n.trackerFloodAdvisory,
                      tone: p.info,
                      icon: Symbols.water_rounded,
                    )
                  else
                    SagipChip(
                      label: w.signalLevel != null
                          ? l10n.trackerSignal(w.signalLevel!)
                          : w.event,
                      tone: (w.signalLevel ?? 0) >= 3 ? p.critical : p.warning,
                      icon: Symbols.flag_rounded,
                    ),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(
                      w.areas.map((a) => a.name).join(', '),
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One layer: its checkbox, name, source, and (for pictures) opacity.
class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.title,
    required this.source,
    required this.value,
    required this.onChanged,
    this.opacity,
    this.onOpacity,
  });

  final String title;
  final String source;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double? opacity;
  final ValueChanged<double>? onOpacity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(SagipRadius.control),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => onChanged(v ?? false),
                ),
                const SizedBox(width: SagipSpace.xs),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.bodyMedium),
                        Text(
                          source,
                          style: text.bodySmall!.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (value && opacity != null && onOpacity != null)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Row(
              children: [
                Text(l10n.trackerOpacity, style: text.bodySmall),
                Expanded(
                  child: Slider(
                    value: opacity!,
                    min: 0.2,
                    max: 1,
                    label: '${(opacity! * 100).round()}%',
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChanged: onOpacity,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.swatch, required this.label});

  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 24, child: Center(child: swatch)),
        const SizedBox(width: SagipSpace.sm),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch.line(this.color, {required this.dashed}) : area = false;
  const _Swatch.area(this.color, {this.dashed = false}) : area = true;

  final Color color;
  final bool area;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (area) {
      return Container(
        width: 20,
        height: 12,
        decoration: BoxDecoration(
          color: color.withValues(alpha: dashed ? 0.1 : 0.2),
          border: Border.all(color: color, width: dashed ? 1 : 1),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    return SizedBox(
      width: 20,
      height: 12,
      child: Row(
        children: [
          for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(child: Container(height: 2.5, color: color)),
          ],
        ],
      ),
    );
  }
}
