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

/// Where each barangay sits on the map. Centers only: boundaries arrive
/// with the full list of Manila's barangays.
final _centers = {
  for (final b in sampleManilaBarangays)
    if (b.center != null) b.name: b.center!,
};

/// D8: the 72-hour risk forecast per barangay (FR4). One hazard at a time
/// on the map and in the ranked list; a barangay's panel shows all three,
/// the registered vulnerable residents there, and what the forecast is
/// based on.
class ForecastPage extends ConsumerStatefulWidget {
  const ForecastPage({super.key});

  @override
  ConsumerState<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends ConsumerState<ForecastPage> {
  final _map = MapController();
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
                  initialCenter: manilaCenter,
                  initialZoom: 13.2,
                  minZoom: 11,
                  maxZoom: 18,
                  backgroundColor: p.canvas,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  const SagipBaseMap(),
                  if (run != null) ...[
                    CircleLayer(
                      circles: [
                        for (final f in run.forecasts)
                          if (_centers[f.barangay] != null) _riskCircle(f, p),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        for (final f in run.forecasts)
                          if (_centers[f.barangay] != null)
                            Marker(
                              point: toLatLng(_centers[f.barangay]!),
                              width: _RiskMarker.size,
                              height: _RiskMarker.size,
                              child: Tooltip(
                                message: l10n.forecastMarker(
                                  f.barangay,
                                  l10n.risk(f.riskOf(_hazard)),
                                ),
                                child: GestureDetector(
                                  onTap: () => _select(f.barangay),
                                  child: _RiskMarker(
                                    risk: f.riskOf(_hazard),
                                    selected: f.barangay == selected,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ],
                  const MapAttribution(),
                ],
              ),
              if (run != null)
                Positioned(
                  left: SagipSpace.lg,
                  bottom: SagipSpace.x3,
                  child: _Legend(hazard: _hazard),
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

  /// The risk drawn as a soft disc around the barangay's center: nothing
  /// for low, ember for moderate, signal for high.
  CircleMarker _riskCircle(BarangayForecast f, SagipPalette p) {
    final risk = f.riskOf(_hazard);
    final tone = riskVisual(risk, p).tone;
    return CircleMarker(
      point: toLatLng(_centers[f.barangay]!),
      radius: 350,
      useRadiusInMeter: true,
      color: switch (risk) {
        RiskLevel.low => const Color(0x00000000),
        RiskLevel.moderate => tone.fill.withValues(alpha: 0.2),
        RiskLevel.high => tone.fill.withValues(alpha: 0.28),
      },
      borderColor: risk == RiskLevel.low ? p.hairlineStrong : tone.fill,
      borderStrokeWidth: 1,
    );
  }
}

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
      for (final b in sampleManilaBarangays)
        if (run.forBarangay(b.name) == null) b,
    ];

    return ListView(
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
                SagipChip.status(label: l10n.risk(r), visual: riskVisual(r, p)),
                const SizedBox(width: SagipSpace.sm),
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
