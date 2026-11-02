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
import 'storm_tracker.dart';

/// Where each barangay's marker sits: its center (inside its boundary).
final _centers = {
  for (final b in manilaBarangays)
    if (b.center != null) b.name: b.center!,
};

/// D8, the Heatmap page: the 72-hour risk per barangay (FR4), one hazard
/// at a time, painted as a heat map (2026-11-02: moderate and high glow,
/// low is not painted) and ranked in the list. A barangay's panel shows
/// all three hazards and why each has its level (the chance, the past
/// incidents there, and the rule), what was recorded there in the last 12
/// months, the registered vulnerable residents, and the weather now. The
/// typhoon tracker switch zooms out to the Philippines (storm_tracker.dart).

class ForecastPage extends ConsumerStatefulWidget {
  const ForecastPage({super.key});

  @override
  ConsumerState<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends ConsumerState<ForecastPage> {
  final _map = MapController();
  var _hazard = ForecastHazard.flood;
  String? _selected;
  var _tracker = false;
  var _layers = const TrackerLayers();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _select(String barangay) {
    // Choosing a barangay goes back to the city.
    setState(() {
      _selected = barangay;
      _tracker = false;
    });
    final center = _centers[barangay];
    if (center != null) _map.move(toLatLng(center), 15);
  }

  void _setTracker(bool on) {
    if (on) {
      setState(() {
        _tracker = true;
        _selected = null;
      });
      // After the wider limits are in place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(trackerCenter, trackerZoom);
      });
    } else {
      _map.move(manilaCenter, 13.2);
      setState(() => _tracker = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final runAsync = ref.watch(forecastProvider);
    final run = runAsync.value;
    final selected = _selected;
    final feeds = ref.watch(hazardFeedsProvider).value ?? HazardFeeds.empty;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(right: BorderSide(color: p.hairline)),
          ),
          child: AsyncBody(
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
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  backgroundColor: mapBackground(context),
                  minZoom: _tracker ? trackerMinZoom : mapMinZoom,
                  cameraConstraint: _tracker
                      ? trackerCameraConstraint
                      : mapCameraConstraint,
                  initialCenter: manilaCenter,
                  initialZoom: 13.2,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  const SagipBaseMap(),
                  if (_tracker)
                    ...trackerMapLayers(
                      context: context,
                      feeds: feeds,
                      layers: _layers,
                      tiles: ref.watch(mapTilesEnabledProvider),
                      now: now,
                    ),
                  // The heat map: a glow per barangay at moderate or high
                  // risk; the barangay lines stay on top, faint, for
                  // finding and clicking one.
                  if (run != null)
                    HeatLayer(weights: riskWeights(run, _hazard)),
                  // 897 outlines are noise at the scale of the country.
                  if (!_tracker)
                    BarangayBoundaries(
                      highlight: selected,
                      onTap: run == null ? null : _select,
                    ),
                  if (run != null && selected != null)
                    _SelectedMarker(
                      run: run,
                      hazard: _hazard,
                      barangay: selected,
                    ),
                  const MapAttribution(),
                ],
              ),
              if (run != null && !_tracker)
                Positioned(
                  left: SagipSpace.lg,
                  bottom: SagipSpace.x3,
                  child: _Legend(hazard: _hazard),
                ),
              Positioned(
                left: SagipSpace.lg,
                top: SagipSpace.lg,
                bottom: SagipSpace.x3,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TrackerCard(
                    on: _tracker,
                    layers: _layers,
                    onToggle: _setTracker,
                    onLayers: (l) => setState(() => _layers = l),
                  ),
                ),
              ),
              Positioned(
                right: SagipSpace.lg,
                bottom: SagipSpace.x3,
                child: ZoomControls(controller: _map),
              ),
            ],
          ),
        ),
        if (run != null && selected != null)
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

/// How strongly each level glows on the heat map (2026-11-02): low is not
/// painted, moderate glows amber, high red.
const riskHeat = {
  RiskLevel.low: 0.0,
  // At the amber end, so moderate never reads as high.
  RiskLevel.moderate: 0.1,
  RiskLevel.high: 1.0,
};

/// Every barangay of [run] above low for [hazard], with its glow.
Map<String, double> riskWeights(ForecastRun run, ForecastHazard hazard) => {
  for (final f in run.forecasts)
    if (f.riskOf(hazard) != RiskLevel.low)
      f.barangay: riskHeat[f.riskOf(hazard)]!,
};

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
                    )
                  else if (run.isLiveWeather)
                    SagipChip(
                      key: const ValueKey('forecast-live-weather'),
                      label: l10n.forecastLiveWeather,
                      tone: p.neutral,
                      icon: Symbols.partly_cloudy_day_rounded,
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
              if (run.isLiveWeather) ...[
                const SizedBox(height: SagipSpace.xs),
                Text(l10n.forecastLiveWeatherNote, style: text.bodySmall),
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
    final warm = p.warning.fill, hot = p.critical.fill;
    return Container(
      key: const ValueKey('forecast-legend'),
      width: 340,
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
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: p.hairline),
              gradient: LinearGradient(
                colors: [
                  for (final r in [0.0, riskHeat[RiskLevel.moderate]!, 1.0])
                    Color.alphaBlend(
                      heatColor(
                        r,
                        warm,
                        hot,
                      ).withValues(alpha: r == 0 ? 0 : heatAlpha(r)),
                      p.canvas,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SagipSpace.xs),
          Row(
            children: [
              Text(l10n.risk(RiskLevel.low), style: text.bodySmall),
              const Spacer(),
              Text(l10n.risk(RiskLevel.moderate), style: text.bodySmall),
              const Spacer(),
              Text(l10n.risk(RiskLevel.high), style: text.bodySmall),
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
    final locale = Localizations.localeOf(context).toString();
    // How dense each hazard's past incidents are here (the KDE), relative
    // to the busiest barangay.
    final density = {
      for (final d
          in ref.watch(densityProvider).value ?? const <HazardDensity>[])
        if (d.barangay == barangay) d.hazard: d.relative,
    };
    // What the system recorded here (resolved incidents, last 12 months).
    final recorded = [
      for (final c
          in ref.watch(yearHistoryProvider).value ?? const <ClosedIncident>[])
        if (c.incident.barangay == barangay &&
            c.ending == IncidentEnding.resolved &&
            c.incident.type != null)
          c.incident,
    ];
    final byType = <IncidentType, List<Incident>>{};
    for (final i in recorded) {
      byType.putIfAbsent(i.type!, () => []).add(i);
    }
    String percent(double v) => '${(v * 100).round()}';
    String reason(
      ForecastHazard h,
      ForecastRule rule,
      double chance,
      double d,
    ) {
      final level = forecast.riskOf(h);
      final c = rule.matched(chance, d);
      return switch (level) {
        RiskLevel.high when c != null => l10n.forecastReasonHigh(
          percent(c.chance),
          percent(c.density),
        ),
        RiskLevel.moderate when c != null => l10n.forecastReasonModerate(
          percent(c.chance),
          percent(c.density),
        ),
        RiskLevel.low when chance < rule.lowestChance =>
          l10n.forecastReasonLowChance(percent(rule.lowestChance)),
        RiskLevel.low => l10n.forecastReasonLowPast,
        // The run's level and the recorded numbers disagree (a density
        // fitted again since the run): show the numbers only.
        _ => '',
      };
    }

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
        for (final h in ForecastHazard.values) ...[
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
          // Why (2026-11-02): the chance, the past incidents here, and
          // which part of the rule gave the level.
          if (run.chances?[h] case final chance? when run.rule != null)
            Padding(
              key: ValueKey('forecast-why-${h.name}'),
              padding: const EdgeInsets.only(
                left: 20 + SagipSpace.md,
                bottom: SagipSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.forecastWhyChance(percent(chance)),
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                  Text(
                    (density[h] ?? 0) > 0
                        ? l10n.forecastWhyDensity(percent(density[h]!))
                        : l10n.forecastWhyNoPast,
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                  if (reason(h, run.rule!, chance, density[h] ?? 0) case final r
                      when r.isNotEmpty)
                    Text(r, style: text.bodySmall),
                ],
              ),
            ),
        ],
        Text(
          run.chances == null ? l10n.forecastWhyUnknown : l10n.forecastWhyModel,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        section(l10n.forecastHistoryTitle),
        if (byType.isEmpty)
          Text(
            l10n.forecastHistoryNone,
            key: const ValueKey('forecast-history-none'),
            style: text.bodyMedium,
          )
        else
          for (final MapEntry(key: type, value: list) in byType.entries)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                key: ValueKey('forecast-history-${type.name}'),
                children: [
                  Icon(
                    incidentTypeIcon(type),
                    size: 20,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: SagipSpace.md),
                  Expanded(
                    child: Text(
                      l10n.forecastHistoryLine(
                        l10n.incidentType(type),
                        list.length,
                        formatDate(
                          list
                              .map((i) => i.receivedAt)
                              .reduce((a, b) => a.isAfter(b) ? a : b),
                          locale,
                        ),
                      ),
                      style: text.bodyMedium,
                    ),
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
