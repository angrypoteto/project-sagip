import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../board/map_parts.dart';

// The typhoon tracker on the Heatmap page (Joshua, 2026-11-02): a switch
// that zooms the map out to the Philippines and draws the cyclone that
// touched PAR (its track, wind zones, and forecast cone, from GDACS),
// PAGASA's flood advisory areas, and NASA's satellite rainfall, beside the
// 72-hour forecast so one can be checked against the other.

/// Where the map looks with the tracker on: west of PAR's middle, so PAR
/// sits to the right of the tracker card.
const trackerCenter = LatLng(15.0, 118.5);
const trackerZoom = 5.2;
const trackerMinZoom = 4.0;
final trackerCameraConstraint = CameraConstraint.containCenter(
  bounds: LatLngBounds(const LatLng(-2, 102), const LatLng(32, 150)),
);

/// NASA GIBS: IMERG precipitation rate, the latest half hour (about 6
/// hours behind), as map tiles. Its tiles go to zoom 6.
const imergTileUrl =
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/'
    'IMERG_Precipitation_Rate_30min/default/default/'
    'GoogleMapsCompatible_Level6/{z}/{y}/{x}.png';

/// Which of the tracker's layers are shown.
@immutable
class TrackerLayers {
  const TrackerLayers({
    this.track = true,
    this.warnings = true,
    this.rainfall = true,
  });

  final bool track;
  final bool warnings;
  final bool rainfall;

  TrackerLayers copyWith({bool? track, bool? warnings, bool? rainfall}) =>
      TrackerLayers(
        track: track ?? this.track,
        warnings: warnings ?? this.warnings,
        rainfall: rainfall ?? this.rainfall,
      );
}

List<LatLng> _points(List<GeoPoint> ring) => [
  for (final p in ring) toLatLng(p),
];

/// The storm to draw: the current one, else the latest to touch PAR.
Storm? trackedStorm(HazardFeeds feeds) => feeds.current ?? feeds.latest;

/// The tracker's map layers, under the barangay outlines.
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
  final strength = storm?.isCurrent ?? false ? 1.0 : 0.5;
  final floods = [
    for (final w in feeds.activeAt(now))
      if (w.isFlood)
        for (final a in w.areas)
          for (final r in a.rings) r,
  ];
  return [
    if (layers.rainfall && tiles)
      TileLayer(
        key: const ValueKey('tracker-rainfall'),
        urlTemplate: imergTileUrl,
        maxNativeZoom: 6,
        userAgentPackageName: 'ph.sagip.dashboard',
        tileDisplay: const TileDisplay.instantaneous(opacity: 0.7),
      ),
    PolylineLayer(
      key: const ValueKey('tracker-par'),
      polylines: [
        Polyline(
          points: _points(parOutline),
          color: p.textSecondary.withValues(alpha: 0.7),
          strokeWidth: 1.2,
          pattern: StrokePattern.dashed(segments: [8, 6]),
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
              color: p.info.fill.withValues(alpha: 0.16),
              borderColor: p.info.fill,
              borderStrokeWidth: 1,
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
              color: p.textSecondary.withValues(alpha: 0.08 * strength),
              borderColor: p.textSecondary.withValues(alpha: 0.6 * strength),
              borderStrokeWidth: 1,
              pattern: StrokePattern.dashed(segments: [6, 5]),
            ),
          for (final z in storm.windZones)
            for (final r in z.rings)
              Polygon(
                points: _points(r),
                color: windColor(z.kmh, p).withValues(alpha: 0.14 * strength),
                borderColor: windColor(
                  z.kmh,
                  p,
                ).withValues(alpha: 0.7 * strength),
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
            color: p.textPrimary.withValues(alpha: 0.85 * strength),
            strokeWidth: 2.5,
          ),
          Polyline(
            points: [
              if (storm.latest case final last?) toLatLng(last.at),
              for (final t in storm.track)
                if (t.forecast) toLatLng(t.at),
            ],
            color: p.textPrimary.withValues(alpha: 0.85 * strength),
            strokeWidth: 2.5,
            pattern: StrokePattern.dashed(segments: [6, 6]),
          ),
        ],
      ),
      CircleLayer(
        circles: [
          for (final t in storm.track)
            CircleMarker(
              point: toLatLng(t.at),
              radius: 3.5,
              color: t.forecast ? p.panel : p.textPrimary,
              borderColor: p.textPrimary,
              borderStrokeWidth: 1.2,
            ),
        ],
      ),
      if (storm.latest case final last?)
        MarkerLayer(
          markers: [
            Marker(
              key: const ValueKey('tracker-eye'),
              point: toLatLng(last.at),
              width: 36,
              height: 36,
              child: _Eye(current: storm.isCurrent),
            ),
          ],
        ),
    ],
  ];
}

/// The color of a wind zone: 60 km/h ember, 120 km/h and up signal.
Color windColor(int kmh, SagipPalette p) => switch (kmh) {
  < 80 => p.warning.fill,
  < 110 => Color.lerp(p.warning.fill, p.critical.fill, 0.5)!,
  _ => p.critical.fill,
};

/// The storm's latest position: a cyclone symbol in a ring.
class _Eye extends StatelessWidget {
  const _Eye({required this.current});

  final bool current;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final tone = current ? p.critical : p.neutral;
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: current ? tone.fill : p.panel,
          shape: BoxShape.circle,
          border: Border.all(color: current ? p.canvas : tone.fill, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(
          Symbols.cyclone_rounded,
          size: 20,
          color: current ? SagipColors.porcelain : tone.text,
        ),
      ),
    );
  }
}

/// The switch, the layer choices, and (when on) what the tracker shows.
class TrackerCard extends ConsumerWidget {
  const TrackerCard({
    super.key,
    required this.on,
    required this.layers,
    required this.onToggle,
    required this.onLayers,
  });

  final bool on;
  final TrackerLayers layers;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TrackerLayers> onLayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final feeds = ref.watch(hazardFeedsProvider);

    Widget check(String label, bool value, ValueChanged<bool> set, Key key) =>
        InkWell(
          key: key,
          borderRadius: BorderRadius.circular(SagipRadius.control),
          onTap: () => set(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => set(v ?? false),
                ),
                Expanded(child: Text(label, style: text.bodyMedium)),
              ],
            ),
          ),
        );

    return Container(
      key: const ValueKey('tracker-card'),
      width: 340,
      decoration: floatingCard(p),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SagipSpace.lg,
              SagipSpace.sm,
              SagipSpace.sm,
              SagipSpace.sm,
            ),
            child: Row(
              children: [
                Icon(Symbols.cyclone_rounded, size: 20, color: p.textSecondary),
                const SizedBox(width: SagipSpace.sm),
                Expanded(
                  child: Text(l10n.trackerTitle, style: text.titleSmall),
                ),
                Switch(
                  key: const ValueKey('tracker-switch'),
                  value: on,
                  onChanged: onToggle,
                ),
              ],
            ),
          ),
          if (on) ...[
            Divider(height: 1, color: p.hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  SagipSpace.sm,
                  SagipSpace.sm,
                  SagipSpace.lg,
                  SagipSpace.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    check(
                      l10n.trackerLayerTrack,
                      layers.track,
                      (v) => onLayers(layers.copyWith(track: v)),
                      const ValueKey('tracker-layer-track'),
                    ),
                    check(
                      l10n.trackerLayerWarnings,
                      layers.warnings,
                      (v) => onLayers(layers.copyWith(warnings: v)),
                      const ValueKey('tracker-layer-warnings'),
                    ),
                    check(
                      l10n.trackerLayerRainfall,
                      layers.rainfall,
                      (v) => onLayers(layers.copyWith(rainfall: v)),
                      const ValueKey('tracker-layer-rainfall'),
                    ),
                    const SizedBox(height: SagipSpace.sm),
                    Padding(
                      padding: const EdgeInsets.only(left: SagipSpace.sm),
                      child: switch (feeds) {
                        AsyncData(:final value) => _TrackerDetails(
                          feeds: value,
                        ),
                        AsyncError() => Text(
                          l10n.trackerError,
                          style: text.bodySmall,
                        ),
                        _ => Text(l10n.trackerLoading, style: text.bodySmall),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The storm, PAGASA's warnings in force, the key, and the sources.
class _TrackerDetails extends ConsumerWidget {
  const _TrackerDetails({required this.feeds});

  final HazardFeeds feeds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final storm = trackedStorm(feeds);
    final warnings = feeds.activeAt(now);
    final signals = [
      for (final w in warnings)
        if (!w.isFlood && w.signalLevel != null) w,
    ];
    final floods = [
      for (final w in warnings)
        if (w.isFlood) w,
    ];
    final label = text.labelMedium!.copyWith(
      color: p.textSecondary,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (storm == null)
          Text(l10n.trackerNoStorm, style: text.bodySmall)
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
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
          const SizedBox(height: SagipSpace.xs),
          if (!storm.isCurrent)
            Text(l10n.trackerNoStormNow, style: text.bodySmall),
          Text(
            [
              if (storm.latest?.category case final c?) _category(l10n, c),
              if (storm.maxWindKmh case final w?) l10n.trackerMaxWind(w),
            ].join(' · '),
            style: text.bodySmall,
          ),
          Text(
            l10n.trackerAdvisory(formatDateTime(storm.to.toLocal(), locale)),
            style: text.bodySmall,
          ),
        ],
        const SizedBox(height: SagipSpace.md),
        Text(l10n.trackerWarningsTitle, style: label),
        const SizedBox(height: SagipSpace.xs),
        if (signals.isEmpty && floods.isEmpty)
          Text(l10n.trackerNoWarnings, style: text.bodySmall),
        for (final w in signals)
          Padding(
            padding: const EdgeInsets.only(bottom: SagipSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SagipChip(
                  label: l10n.trackerSignal(w.signalLevel!),
                  tone: w.signalLevel! >= 3 ? p.critical : p.warning,
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
        for (final w in floods)
          Padding(
            padding: const EdgeInsets.only(bottom: SagipSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SagipChip(
                  label: l10n.trackerFloodAdvisory,
                  tone: p.info,
                  icon: Symbols.water_rounded,
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
        const SizedBox(height: SagipSpace.md),
        Text(l10n.trackerKeyTitle, style: label),
        const SizedBox(height: SagipSpace.xs),
        _KeyRow(
          swatch: _Swatch.line(p.textPrimary, dashed: false),
          label: l10n.trackerKeyTrack,
        ),
        _KeyRow(
          swatch: _Swatch.line(p.textPrimary, dashed: true),
          label: l10n.trackerKeyForecast,
        ),
        for (final kmh in const [60, 90, 120])
          _KeyRow(
            swatch: _Swatch.area(windColor(kmh, p)),
            label: l10n.trackerKeyWind(kmh),
          ),
        _KeyRow(swatch: _Swatch.area(p.info.fill), label: l10n.trackerKeyFlood),
        _KeyRow(
          swatch: _Swatch.line(p.textSecondary, dashed: true),
          label: l10n.trackerKeyPar,
        ),
        const SizedBox(height: SagipSpace.md),
        Text(l10n.trackerSources, style: text.bodySmall),
      ],
    );
  }

  static String _category(AppLocalizations l10n, String code) =>
      switch (code.toUpperCase()) {
        'TD' => l10n.trackerCategoryTd,
        'TS' => l10n.trackerCategoryTs,
        'STS' => l10n.trackerCategorySts,
        'TY' || 'HU' => l10n.trackerCategoryTy,
        'STY' || 'ST' => l10n.trackerCategorySty,
        _ => code,
      };
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
  const _Swatch.area(this.color) : area = true, dashed = false;

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
          color: color.withValues(alpha: 0.2),
          border: Border.all(color: color),
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
