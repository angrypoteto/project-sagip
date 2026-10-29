import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../board/map_parts.dart';
import 'heat_layer.dart';

/// Where each barangay's marker sits: its center (inside its boundary).
final _centers = {
  for (final b in manilaBarangays)
    if (b.center != null) b.name: b.center!,
};

/// D8, the Heatmap page (Joshua, 2026-10-29): two views kept apart so one
/// is never read as the other. "72-hour forecast" (it opens on this): the
/// risk per barangay (FR4), one hazard at a time on the map and in the
/// ranked list; a barangay's panel shows all three, the registered
/// vulnerable residents there, and what the forecast is based on.
/// "Hotspots": a heat map of where past incidents were densest (the KDE).
enum _View { forecast, hotspots }

class ForecastPage extends ConsumerStatefulWidget {
  const ForecastPage({super.key});

  @override
  ConsumerState<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends ConsumerState<ForecastPage> {
  final _map = MapController();
  var _view = _View.forecast;
  var _hazard = ForecastHazard.flood;
  String? _selected;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _select(String barangay) {
    setState(() => _selected = barangay);
    final center = _centers[barangay];
    if (center != null) _map.move(toLatLng(center), 15);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final runAsync = ref.watch(forecastProvider);
    final run = runAsync.value;
    final selected = _selected;
    final hotspots = _view == _View.hotspots;
    final densityAsync = ref.watch(densityProvider);
    final densities = [
      for (final d in densityAsync.value ?? const <HazardDensity>[])
        if (d.hazard == _hazard) d,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(right: BorderSide(color: p.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SagipSpace.lg,
                  SagipSpace.lg,
                  SagipSpace.lg,
                  0,
                ),
                child: SegmentedButton<_View>(
                  key: const ValueKey('heat-view'),
                  segments: [
                    ButtonSegment(
                      value: _View.forecast,
                      label: Text(l10n.heatViewForecast),
                      icon: const Icon(Symbols.radar_rounded),
                    ),
                    ButtonSegment(
                      value: _View.hotspots,
                      label: Text(l10n.heatViewHotspots),
                      icon: const Icon(Symbols.local_fire_department_rounded),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _view = s.first;
                    _selected = null;
                  }),
                ),
              ),
              Expanded(
                child: hotspots
                    ? AsyncBody(
                        value: densityAsync,
                        isEmpty: (rows) => rows.isEmpty,
                        empty: EmptyState(
                          icon: Symbols.local_fire_department_rounded,
                          title: l10n.hotspotsEmpty,
                          message: l10n.hotspotsEmptyHint,
                        ),
                        onRetry: () => ref.invalidate(densityProvider),
                        builder: (rows) => _HotspotList(
                          all: rows,
                          hazard: _hazard,
                          selected: selected,
                          onHazard: (h) => setState(() => _hazard = h),
                          onSelect: _select,
                        ),
                      )
                    : AsyncBody(
                        value: runAsync,
                        isEmpty: (run) => run == null,
                        empty: EmptyState(
                          icon: Symbols.radar_rounded,
                          title: l10n.forecastEmpty,
                          message: l10n.forecastEmptyHint,
                        ),
                        onRetry: () => ref.invalidate(forecastProvider),
                        builder: (run) => _RankedList(
                          run: run!,
                          hazard: _hazard,
                          selected: selected,
                          onHazard: (h) => setState(() => _hazard = h),
                          onSelect: _select,
                        ),
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  backgroundColor: mapBackground(context),
                  minZoom: mapMinZoom,
                  cameraConstraint: mapCameraConstraint,
                  initialCenter: manilaCenter,
                  initialZoom: 13.2,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  const SagipBaseMap(),
                  if (hotspots) ...[
                    // Glows over the map; the barangay lines stay on top,
                    // faint, for finding and clicking one.
                    HeatLayer(densities: densities),
                    BarangayBoundaries(highlight: selected, onTap: _select),
                  ] else ...[
                    // Every barangay of the run in its risk's color;
                    // clicking one opens its panel.
                    BarangayBoundaries(
                      fills: run == null
                          ? const {}
                          : riskFills(run, _hazard, p),
                      highlight: selected,
                      onTap: run == null ? null : _select,
                    ),
                    if (run != null && selected != null)
                      _SelectedMarker(
                        run: run,
                        hazard: _hazard,
                        barangay: selected,
                      ),
                  ],
                  const MapAttribution(),
                ],
              ),
              if (hotspots ? densities.isNotEmpty : run != null)
                Positioned(
                  left: SagipSpace.lg,
                  bottom: SagipSpace.x3,
                  child: hotspots
                      ? _HeatLegend(hazard: _hazard)
                      : _Legend(hazard: _hazard),
                ),
              Positioned(
                right: SagipSpace.lg,
                bottom: SagipSpace.x3,
                child: ZoomControls(controller: _map),
              ),
            ],
          ),
        ),
        if (!hotspots && run != null && selected != null)
          Container(
            width: 340,
            decoration: BoxDecoration(
              color: p.panel,
              border: Border(left: BorderSide(color: p.hairline)),
            ),
            child: _BarangayPanel(
              run: run,
              barangay: selected,
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ],
    );
  }
}

/// How strongly each level is painted over the map: low stays quiet, high
/// is the strongest, so the levels differ in weight as well as in hue.
const riskFillAlpha = {
  RiskLevel.low: 0.22,
  RiskLevel.moderate: 0.50,
  RiskLevel.high: 0.62,
};

/// The fill of a barangay at [risk]: verdant for low, ember for moderate,
/// signal for high.
Color riskFill(RiskLevel risk, SagipPalette p) => switch (risk) {
  RiskLevel.low => p.success.fill,
  RiskLevel.moderate => p.warning.fill,
  RiskLevel.high => p.critical.fill,
}.withValues(alpha: riskFillAlpha[risk]);

/// Every barangay of [run] in the color of its risk for [hazard]. A
/// barangay the run has nothing for is left unpainted.
Map<String, Color> riskFills(
  ForecastRun run,
  ForecastHazard hazard,
  SagipPalette p,
) => {for (final f in run.forecasts) f.barangay: riskFill(f.riskOf(hazard), p)};

class _RankedList extends ConsumerWidget {
  const _RankedList({
    required this.run,
    required this.hazard,
    required this.selected,
    required this.onHazard,
    required this.onSelect,
  });

  final ForecastRun run;
  final ForecastHazard hazard;
  final String? selected;
  final ValueChanged<ForecastHazard> onHazard;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final without = [
      for (final b in manilaBarangays)
        if (run.forBarangay(b.name) == null) b,
    ];

    return ListView(
      key: const ValueKey('forecast-list'),
      padding: const EdgeInsets.only(bottom: SagipSpace.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(SagipSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.forecastTitle, style: text.titleMedium),
                  ),
                  if (run.isSample)
                    SagipChip(
                      label: l10n.forecastSample,
                      tone: p.neutral,
                      icon: Symbols.science_rounded,
                    )
                  else if (run.isSimulated)
                    SagipChip(
                      label: l10n.simulatedFeed,
                      tone: p.neutral,
                      icon: Symbols.replay_rounded,
                    ),
                ],
              ),
              const SizedBox(height: SagipSpace.sm),
              Text(
                l10n.forecastIssued(
                  formatDateTime(run.issuedAt, locale),
                  formatDateTime(run.validUntil, locale),
                ),
                style: text.bodySmall,
              ),
              if (run.isSample) ...[
                const SizedBox(height: SagipSpace.xs),
                Text(l10n.forecastSampleNote, style: text.bodySmall),
              ],
              if (run.isStaleAt(now)) ...[
                const SizedBox(height: SagipSpace.md),
                _StaleNotice(message: l10n.forecastStale),
              ],
              const SizedBox(height: SagipSpace.lg),
              SegmentedButton<ForecastHazard>(
                segments: [
                  for (final h in ForecastHazard.values)
                    // Text only: with icons "Storm surge" wraps at this width.
                    ButtonSegment(value: h, label: Text(l10n.hazard(h))),
                ],
                selected: {hazard},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onHazard(s.first),
              ),
              const SizedBox(height: SagipSpace.md),
              Text(
                l10n.forecastCounts(
                  run.count(hazard, RiskLevel.high),
                  run.count(hazard, RiskLevel.moderate),
                  run.count(hazard, RiskLevel.low),
                ),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.hairline),
        for (final f in run.ranked(hazard))
          _BarangayRow(
            key: ValueKey('forecast-row-${f.barangay}'),
            barangay: f.barangay,
            district: f.district,
            risk: f.riskOf(hazard),
            selected: f.barangay == selected,
            onTap: () => onSelect(f.barangay),
          ),
        if (without.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SagipSpace.lg,
              SagipSpace.xl,
              SagipSpace.lg,
              SagipSpace.sm,
            ),
            child: Text(
              l10n.forecastNoneSection,
              style: text.labelMedium!.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final b in without)
            _BarangayRow(
              key: ValueKey('forecast-row-${b.name}'),
              barangay: b.name,
              district: b.district,
              risk: null,
              selected: false,
              onTap: null,
            ),
        ],
      ],
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Container(
      key: const ValueKey('forecast-stale'),
      padding: const EdgeInsets.all(SagipSpace.md),
      decoration: BoxDecoration(
        color: p.warning.tint,
        borderRadius: BorderRadius.circular(SagipRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.schedule_rounded, size: 20, color: p.warning.text),
          const SizedBox(width: SagipSpace.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: p.warning.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarangayRow extends StatelessWidget {
  const _BarangayRow({
    super.key,
    required this.barangay,
    required this.district,
    required this.risk,
    required this.selected,
    required this.onTap,
  });

  final String barangay;
  final String district;

  /// Null for a barangay the run has no forecast for.
  final RiskLevel? risk;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? p.panelRaised : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.lg,
              vertical: SagipSpace.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: selected ? p.info.fill : Colors.transparent,
                ),
                bottom: BorderSide(color: p.hairline),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(barangay, style: text.titleSmall),
                      Text(district, style: text.bodySmall),
                    ],
                  ),
                ),
                if (risk != null)
                  SagipChip.status(
                    label: l10n.risk(risk!),
                    visual: riskVisual(risk!, p),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen barangay's marker, with its risk's icon: the one marker on
/// the heat map, so the colors stay readable.
class _SelectedMarker extends StatelessWidget {
  const _SelectedMarker({
    required this.run,
    required this.hazard,
    required this.barangay,
  });

  final ForecastRun run;
  final ForecastHazard hazard;
  final String barangay;

  @override
  Widget build(BuildContext context) {
    final center = _centers[barangay];
    final forecast = run.forecasts
        .where((f) => f.barangay == barangay)
        .firstOrNull;
    if (center == null || forecast == null) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        Marker(
          key: ValueKey('risk-$barangay'),
          point: toLatLng(center),
          width: _RiskMarker.size,
          height: _RiskMarker.size,
          child: IgnorePointer(
            child: _RiskMarker(risk: forecast.riskOf(hazard), selected: true),
          ),
        ),
      ],
    );
  }
}

/// A barangay on the map: a dot in the risk's color with its icon, so the
/// level never rests on color alone.
class _RiskMarker extends StatelessWidget {
  const _RiskMarker({required this.risk, required this.selected});

  final RiskLevel risk;
  final bool selected;

  static const double size = 52;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final visual = riskVisual(risk, p);
    final low = risk == RiskLevel.low;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (selected)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: (low ? p.info : visual.tone).fill.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
          ),
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: low ? p.panel : visual.tone.fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: low ? p.hairlineStrong : p.canvas,
              width: 2,
            ),
          ),
          child: Icon(
            visual.icon ?? Symbols.remove_rounded,
            size: 16,
            // Ember takes dark text; signal takes white.
            color: switch (risk) {
              RiskLevel.low => p.textSecondary,
              RiskLevel.moderate => SagipColors.bay,
              RiskLevel.high => SagipColors.porcelain,
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.hazard});

  final ForecastHazard hazard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(SagipSpace.md),
      decoration: floatingCard(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.forecastLegend(l10n.hazard(hazard)),
            style: text.labelMedium,
          ),
          const SizedBox(height: SagipSpace.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in RiskLevel.values.reversed) ...[
                // The color as it looks on the map, then its name.
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(riskFill(r, p), p.canvas),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: p.hairlineStrong),
                  ),
                ),
                const SizedBox(width: SagipSpace.xs),
                Text(l10n.risk(r), style: text.labelMedium),
                const SizedBox(width: SagipSpace.md),
              ],
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          Text(l10n.forecastLegendNote, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// The explanation panel for one barangay.
class _BarangayPanel extends ConsumerWidget {
  const _BarangayPanel({
    required this.run,
    required this.barangay,
    required this.onClose,
  });

  final ForecastRun run;
  final String barangay;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final forecast = run.forBarangay(barangay);
    if (forecast == null) return const SizedBox.shrink();

    final residents = ref.watch(vulnerableResidentsProvider);
    final registered = residents.value
        ?.where((r) => r.barangay == barangay)
        .length;
    final weather = ref.watch(weatherProvider).value;
    final thresholds = ref.watch(alertThresholdsProvider);

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
      key: const ValueKey('forecast-panel'),
      padding: const EdgeInsets.all(SagipSpace.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(forecast.barangay, style: text.titleLarge),
                  Text(forecast.district, style: text.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.close,
              onPressed: onClose,
              icon: const Icon(Symbols.close_rounded),
            ),
          ],
        ),
        section(l10n.forecastRisks),
        for (final h in ForecastHazard.values)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Icon(hazardIcon(h), size: 20, color: p.textSecondary),
                const SizedBox(width: SagipSpace.md),
                Expanded(child: Text(l10n.hazard(h), style: text.bodyMedium)),
                SagipChip.status(
                  label: l10n.risk(forecast.riskOf(h)),
                  visual: riskVisual(forecast.riskOf(h), p),
                ),
              ],
            ),
          ),
        section(l10n.forecastVulnerable),
        Row(
          children: [
            Icon(Symbols.accessible_rounded, size: 20, color: p.textSecondary),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Text(
                registered == null
                    ? l10n.forecastVulnerableUnknown
                    : l10n.forecastVulnerableCount(registered),
                style: text.bodyMedium,
              ),
            ),
            if (registered != null && registered > 0)
              TextButton(
                key: const ValueKey('forecast-open-list'),
                onPressed: () => context.go(
                  Uri(
                    path: Routes.vulnerable,
                    queryParameters: {'barangay': barangay},
                  ).toString(),
                ),
                child: Text(l10n.forecastOpenList),
              ),
          ],
        ),
        if (weather != null) ...[
          section(l10n.forecastWeatherNow),
          _Reading(
            icon: Symbols.cyclone_rounded,
            value: weather.signalLevel > 0
                ? l10n.signalLevel(weather.signalLevel)
                : l10n.noSignal,
            level: thresholds.levelIn(weather, WeatherHazard.signal),
          ),
          _Reading(
            icon: Symbols.rainy_rounded,
            value: l10n.rainfall(weather.rainfallMmPerHour.toStringAsFixed(1)),
            level: thresholds.levelIn(weather, WeatherHazard.rainfall),
          ),
          _Reading(
            icon: Symbols.tsunami_rounded,
            value: weather.stormSurgeMeters != null
                ? l10n.forecastSurge(
                    weather.stormSurgeMeters!.toStringAsFixed(1),
                  )
                : (weather.stormSurgeAdvisory ?? l10n.forecastNoSurge),
            level: thresholds.levelIn(weather, WeatherHazard.surge),
          ),
        ],
        section(l10n.forecastAbout),
        Text(
          run.isSample
              ? l10n.forecastAboutSample
              : run.modelVersion == null
              ? l10n.forecastAboutNoVersion
              : l10n.forecastAboutModel(run.modelVersion!),
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// One PAGASA reading with its level against the A3 thresholds.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.icon,
    required this.value,
    required this.level,
  });

  final IconData icon;
  final String value;
  final AlertLevel? level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.textSecondary),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (level != null)
            SagipChip(
              label: l10n.alertLevel(level!),
              tone: level == AlertLevel.critical ? p.critical : p.warning,
              icon: level == AlertLevel.critical
                  ? Symbols.warning_rounded
                  : Symbols.error_rounded,
            ),
        ],
      ),
    );
  }
}

/// The Hotspots list: the barangays where past incidents of the hazard
/// were densest, densest first, each with its share of the densest.
class _HotspotList extends ConsumerWidget {
  const _HotspotList({
    required this.all,
    required this.hazard,
    required this.selected,
    required this.onHazard,
    required this.onSelect,
  });

  final List<HazardDensity> all;
  final ForecastHazard hazard;
  final String? selected;
  final ValueChanged<ForecastHazard> onHazard;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final rows = [
      for (final d in all)
        if (d.hazard == hazard && d.relative > 0) d,
    ]..sort((a, b) => b.relative.compareTo(a.relative));
    final sample = all.any((d) => d.isSample);
    final computed = all
        .map((d) => d.computedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final header = Padding(
      padding: const EdgeInsets.all(SagipSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.hotspotsTitle, style: text.titleMedium),
              ),
              if (sample)
                SagipChip(
                  label: l10n.hotspotsSample,
                  tone: p.neutral,
                  icon: Symbols.science_rounded,
                ),
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          Text(l10n.hotspotsIntro, style: text.bodySmall),
          const SizedBox(height: SagipSpace.xs),
          Text(
            l10n.hotspotsComputed(formatDateTime(computed, locale)),
            style: text.bodySmall,
          ),
          if (sample) ...[
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.hotspotsSampleNote, style: text.bodySmall),
          ],
          const SizedBox(height: SagipSpace.lg),
          SegmentedButton<ForecastHazard>(
            segments: [
              for (final h in ForecastHazard.values)
                ButtonSegment(value: h, label: Text(l10n.hazard(h))),
            ],
            selected: {hazard},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onHazard(s.first),
          ),
          const SizedBox(height: SagipSpace.md),
          Text(l10n.hotspotsCount(rows.length), style: text.bodySmall),
        ],
      ),
    );

    return ListView.builder(
      key: const ValueKey('hotspot-list'),
      padding: const EdgeInsets.only(bottom: SagipSpace.xxl),
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Divider(height: 1, color: p.hairline),
            ],
          );
        }
        final d = rows[i - 1];
        return _HotspotRow(
          key: ValueKey('hotspot-row-${d.barangay}'),
          density: d,
          selected: d.barangay == selected,
          onTap: () => onSelect(d.barangay),
        );
      },
    );
  }
}

class _HotspotRow extends StatelessWidget {
  const _HotspotRow({
    super.key,
    required this.density,
    required this.selected,
    required this.onTap,
  });

  final HazardDensity density;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final percent = (density.relative * 100).round();
    final color = heatColor(density.relative, p.warning.fill, p.critical.fill);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.hotspotsDensityLabel(density.barangay, percent),
      excludeSemantics: true,
      child: Material(
        color: selected ? p.panelRaised : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.lg,
              vertical: SagipSpace.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: selected ? p.info.fill : Colors.transparent,
                ),
                bottom: BorderSide(color: p.hairline),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(density.barangay, style: text.titleSmall),
                      Text(density.district, style: text.bodySmall),
                    ],
                  ),
                ),
                // A thin bar: the share of the densest barangay.
                SizedBox(
                  width: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: density.relative,
                      minHeight: 4,
                      color: color,
                      backgroundColor: p.hairline,
                    ),
                  ),
                ),
                const SizedBox(width: SagipSpace.sm),
                SizedBox(
                  width: 40,
                  child: Text(
                    l10n.hotspotsPercent(percent),
                    textAlign: TextAlign.end,
                    style: text.labelMedium!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Hotspots legend: one bar from clear through ember to signal, as the
/// glows are painted.
class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.hazard});

  final ForecastHazard hazard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final warm = p.warning.fill, hot = p.critical.fill;
    return Container(
      key: const ValueKey('heat-legend'),
      width: 320,
      padding: const EdgeInsets.all(SagipSpace.md),
      decoration: floatingCard(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.hotspotsLegend(l10n.hazard(hazard)),
            style: text.labelMedium,
          ),
          const SizedBox(height: SagipSpace.sm),
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: p.hairline),
              gradient: LinearGradient(
                colors: [
                  for (final r in const [0.0, 0.25, 0.5, 0.75, 1.0])
                    Color.alphaBlend(
                      heatColor(
                        r,
                        warm,
                        hot,
                      ).withValues(alpha: heatAlpha(r) * r.clamp(0.15, 1)),
                      p.canvas,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SagipSpace.xs),
          Row(
            children: [
              Text(l10n.hotspotsFewer, style: text.bodySmall),
              const Spacer(),
              Text(l10n.hotspotsMore, style: text.bodySmall),
            ],
          ),
          const SizedBox(height: SagipSpace.sm),
          Text(l10n.hotspotsLegendNote, style: text.bodySmall),
        ],
      ),
    );
  }
}
