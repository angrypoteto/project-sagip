import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/screen.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import 'map_parts.dart';
import 'unit_glide.dart';

enum _Layer { units, reports, boundaries }

/// D2 map view: active incidents, unverified crowd reports, and units.
class IncidentMap extends ConsumerStatefulWidget {
  const IncidentMap({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.wall = false,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// The wall map (a window of its own for another monitor): markers are
  /// drawn larger to be read from across a room, and the button that opens
  /// that window is left out.
  final bool wall;

  /// How much larger the wall map draws its markers.
  static const wallScale = 1.7;

  @override
  ConsumerState<IncidentMap> createState() => _IncidentMapState();
}

class _IncidentMapState extends ConsumerState<IncidentMap>
    with SingleTickerProviderStateMixin {
  final _controller = MapController();
  final _layers = {_Layer.units, _Layer.reports, _Layer.boundaries};
  bool _ready = false;

  /// The markers on their way between two reported positions, by unit.
  final _glides = <String, UnitGlide>{};

  /// Redraws the map while any marker is on its way, and only then.
  late final Ticker _moving = createTicker((_) {
    final now = DateTime.now();
    setState(() => _glides.removeWhere((_, g) => g.done(now)));
    if (_glides.isEmpty) _moving.stop();
  });

  /// A crew's phone reported a new position: its marker sets off from
  /// where it is drawn now, straight at first and along the streets as
  /// soon as the road graph has the way.
  void _unitsMoved(List<ResponseUnit>? before, List<ResponseUnit>? after) {
    if (before == null || after == null || !ref.read(unitGlideProvider)) {
      return;
    }
    final now = DateTime.now();
    final old = {for (final u in before) u.id: u.location};
    for (final u in after) {
      final was = old[u.id], at = u.location;
      if (was == null || at == null || was == at) continue;
      final from = _glides[u.id]?.at(now) ?? was;
      final meters = from.distanceTo(at);
      if (meters < unitGlideMinMeters || meters > unitGlideMaxMeters) {
        _glides.remove(u.id);
        continue;
      }
      final glide = UnitGlide(points: [from, at], startedAt: now);
      _glides[u.id] = glide;
      if (!_moving.isActive) _moving.start();
      ref.read(roadRouterProvider.future).then((router) {
        // Still the same trip: a newer position has not replaced it.
        if (!mounted || _glides[u.id] != glide) return;
        glide.points = glidePoints(from, at, router.route(from, at)?.points);
      }).ignore();
    }
  }

  /// The unit as it is drawn this frame: on its way, or where it is.
  ResponseUnit _shown(ResponseUnit u, DateTime now) {
    final glide = _glides[u.id];
    return glide == null || glide.to != u.location
        ? u
        : u.copyWith(location: glide.at(now));
  }

  @override
  void didUpdateWidget(IncidentMap old) {
    super.didUpdateWidget(old);
    if (widget.selectedId != null && widget.selectedId != old.selectedId) {
      _focusSelected();
    }
  }

  /// Brings the selected incident into view, left of the drawer.
  void _focusSelected() {
    final incident = ref.read(incidentByIdProvider(widget.selectedId!));
    if (!_ready || incident == null) return;
    final camera = _controller.camera;
    final target = toLatLng(incident.currentLocation);
    final visible = camera.visibleBounds.contains(target);
    if (!visible) _controller.move(target, camera.zoom);
  }

  @override
  void dispose() {
    _moving.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final incidents = ref.watch(activeIncidentsProvider).value ?? const [];
    ref.listen(
      unitsProvider,
      (before, after) => _unitsMoved(before?.value, after.value),
    );
    final frame = DateTime.now();
    final units = [
      for (final u in ref.watch(unitsProvider).value ?? const <ResponseUnit>[])
        _shown(u, frame),
    ];
    final reports = ref.watch(crowdReportsProvider).value ?? const [];
    final pings = ref.watch(sosPingProvider);
    // Whether a free unit's fix is recent enough to draw: a slow tick.
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    // Where the crews of free units are is shown only while an incident is
    // open: one on its way back may then be the nearest. With the board
    // empty, free units are at their stations and nothing else.
    GeoPoint? ghostOf(ResponseUnit u) =>
        u.ghostPosition(now, freeCrews: incidents.isNotEmpty);
    final scale = widget.wall ? IncidentMap.wallScale : 1.0;
    // A marker drawn [scale] times its size.
    Widget sized(double size, Widget child) => scale == 1
        ? child
        : FittedBox(
            child: SizedBox(width: size, height: size, child: child),
          );

    final markers = <Marker>[
      if (_layers.contains(_Layer.reports))
        for (final r in reports)
          if (!r.isClustered)
            Marker(
              point: toLatLng(r.location),
              width: ReportMarkerRing.size * scale,
              height: ReportMarkerRing.size * scale,
              child: sized(ReportMarkerRing.size, const ReportMarkerRing()),
            ),
      if (_layers.contains(_Layer.units))
        for (final u in units) ...[
          // The faint one first, so the main marker draws over it: the
          // station while the unit is out, or its crew while it is free.
          if (ghostOf(u) != null)
            Marker(
              key: ValueKey('unit-ghost-${u.id}'),
              point: toLatLng(ghostOf(u)!),
              width: UnitMarkerSquare.size * scale,
              height: UnitMarkerSquare.size * scale,
              child: sized(
                UnitMarkerSquare.size,
                UnitMarkerSquare(
                  unit: u,
                  ghost: u.onJob ? UnitGhost.station : UnitGhost.crew,
                ),
              ),
            ),
          if (u.mapPosition != null)
            Marker(
              key: ValueKey('unit-${u.id}'),
              point: toLatLng(u.mapPosition!),
              width: UnitMarkerSquare.size * scale,
              height: UnitMarkerSquare.size * scale,
              child: sized(UnitMarkerSquare.size, UnitMarkerSquare(unit: u)),
            ),
        ],
      // Incidents last so they draw on top; the selected one topmost.
      for (final i in [
        ...incidents.where((i) => i.id != widget.selectedId),
        ...incidents.where((i) => i.id == widget.selectedId),
      ])
        Marker(
          point: toLatLng(i.currentLocation),
          width: IncidentMarkerDot.size * scale,
          height: IncidentMarkerDot.size * scale,
          child: Semantics(
            button: true,
            label: i.place,
            child: GestureDetector(
              onTap: () => widget.onSelect(i.id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: sized(
                  IncidentMarkerDot.size,
                  IncidentMarkerDot(
                    incident: i,
                    selected: i.id == widget.selectedId,
                    ping: pings && IncidentMarkerDot.waits(i),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: manilaCenter,
            initialZoom: 13.6,
            minZoom: 11,
            maxZoom: 18,
            backgroundColor: p.canvas,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              if (widget.selectedId != null) _focusSelected();
            },
          ),
          children: [
            const SagipBaseMap(),
            if (_layers.contains(_Layer.boundaries)) const BarangayBoundaries(),
            // A dotted line ties each unit to its faint second marker.
            if (_layers.contains(_Layer.units))
              PolylineLayer(
                polylines: [
                  for (final u in units)
                    if (ghostOf(u) != null && u.mapPosition != null)
                      Polyline(
                        points: [
                          toLatLng(u.mapPosition!),
                          toLatLng(ghostOf(u)!),
                        ],
                        color: p.textSecondary.withValues(alpha: 0.7),
                        strokeWidth: 1.5 * scale,
                        pattern: const StrokePattern.dotted(),
                      ),
                ],
              ),
            MarkerLayer(markers: markers),
            const MapAttribution(),
          ],
        ),
        Positioned(
          right: SagipSpace.lg,
          top: SagipSpace.lg,
          child: _LayersCard(
            layers: _layers,
            onToggle: (layer) => setState(() {
              _layers.contains(layer)
                  ? _layers.remove(layer)
                  : _layers.add(layer);
            }),
          ),
        ),
        const Positioned(
          left: SagipSpace.lg,
          bottom: SagipSpace.x3,
          child: _Legend(),
        ),
        Positioned(
          right: SagipSpace.lg,
          bottom: SagipSpace.x3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.wall) ...[
                Container(
                  decoration: floatingCard(p),
                  child: IconButton(
                    key: const ValueKey('open-wall-map'),
                    tooltip: l10n.wallOpen,
                    onPressed: () => openInNewWindow(Routes.wall),
                    icon: const Icon(Symbols.open_in_new_rounded),
                  ),
                ),
                const SizedBox(height: SagipSpace.sm),
              ],
              ZoomControls(controller: _controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayersCard extends StatelessWidget {
  const _LayersCard({required this.layers, required this.onToggle});

  final Set<_Layer> layers;
  final ValueChanged<_Layer> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.lg,
        SagipSpace.md,
        SagipSpace.sm,
        SagipSpace.sm,
      ),
      decoration: floatingCard(SagipPalette.of(context)),
      // CheckboxListTile paints on the nearest Material, not on this card.
      child: Material(
        type: MaterialType.transparency,
        child: _layerList(l10n, text),
      ),
    );
  }

  Widget _layerList(AppLocalizations l10n, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.layersTitle, style: text.titleSmall),
        for (final (layer, label) in [
          (_Layer.units, l10n.layerUnits),
          (_Layer.reports, l10n.layerReports),
          (_Layer.boundaries, l10n.layerBoundaries),
        ])
          CheckboxListTile(
            value: layers.contains(layer),
            onChanged: (_) => onToggle(layer),
            title: Text(label, style: text.labelMedium),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final style = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: p.textSecondary);

    Widget dot(Color color, {bool ring = false, bool square = false}) =>
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: ring ? Colors.transparent : color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(3) : null,
            border: ring ? Border.all(color: color, width: 2) : null,
          ),
        );

    final entries = [
      (dot(p.warning.fill), l10n.legendPending),
      (dot(p.critical.fill), l10n.legendConfirmed),
      (dot(p.info.text, ring: true), l10n.legendAssigned),
      (dot(p.info.fill), l10n.legendEnRoute),
      (dot(p.onScene.fill), l10n.legendOnScene),
      (
        CustomPaint(
          painter: DashedRRectPainter(
            color: p.textSecondary,
            radius: 6,
            strokeWidth: 1.5,
          ),
          child: const SizedBox(width: 12, height: 12),
        ),
        l10n.legendUnverified,
      ),
      (dot(p.success.fill, square: true), l10n.legendUnitAvailable),
      (dot(p.info.fill, square: true), l10n.legendUnitBusy),
    ];

    return Container(
      padding: const EdgeInsets.all(SagipSpace.md),
      decoration: floatingCard(p),
      child: SizedBox(
        width: 300,
        child: Wrap(
          runSpacing: SagipSpace.sm,
          children: [
            for (final (marker, label) in entries)
              SizedBox(
                width: 150,
                child: Row(
                  children: [
                    marker,
                    const SizedBox(width: SagipSpace.sm),
                    Flexible(child: Text(label, style: style)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Map/List switch for the Triage Queue (FR2).
class ViewToggle extends StatelessWidget {
  const ViewToggle({
    super.key,
    required this.listView,
    required this.onChanged,
  });

  final bool listView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;

    Widget option(bool list, IconData icon, String label) {
      final selected = listView == list;
      return Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? p.panelRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(SagipRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(SagipRadius.control),
            onTap: () => onChanged(list),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? p.textPrimary : p.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: text.labelMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? p.textPrimary : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(SagipSpace.xs),
      decoration: floatingCard(p),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(false, Symbols.map_rounded, l10n.viewMap),
          const SizedBox(width: SagipSpace.xs),
          option(true, Symbols.list_rounded, l10n.viewList),
        ],
      ),
    );
  }
}
