import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'map_parts.dart';

enum _Layer { units, reports }

/// D2 map view: active incidents, unverified crowd reports, and units.
class IncidentMap extends ConsumerStatefulWidget {
  const IncidentMap({
    super.key,
    required this.selectedId,
    required this.onSelect,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<IncidentMap> createState() => _IncidentMapState();
}

class _IncidentMapState extends ConsumerState<IncidentMap> {
  final _controller = MapController();
  final _layers = {_Layer.units, _Layer.reports};
  bool _ready = false;

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
    final target = toLatLng(incident.location);
    final visible = camera.visibleBounds.contains(target);
    if (!visible) _controller.move(target, camera.zoom);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final incidents = ref.watch(activeIncidentsProvider).value ?? const [];
    final units = ref.watch(unitsProvider).value ?? const <ResponseUnit>[];
    final reports = ref.watch(crowdReportsProvider).value ?? const [];

    final markers = <Marker>[
      if (_layers.contains(_Layer.reports))
        for (final r in reports)
          if (!r.isClustered)
            Marker(
              point: toLatLng(r.location),
              width: ReportMarkerRing.size,
              height: ReportMarkerRing.size,
              child: const ReportMarkerRing(),
            ),
      if (_layers.contains(_Layer.units))
        for (final u in units)
          if (u.location != null)
            Marker(
              point: toLatLng(u.location!),
              width: UnitMarkerSquare.size,
              height: UnitMarkerSquare.size,
              child: UnitMarkerSquare(unit: u),
            ),
      // Incidents last so they draw on top; the selected one topmost.
      for (final i in [
        ...incidents.where((i) => i.id != widget.selectedId),
        ...incidents.where((i) => i.id == widget.selectedId),
      ])
        Marker(
          point: toLatLng(i.location),
          width: IncidentMarkerDot.size,
          height: IncidentMarkerDot.size,
          child: Semantics(
            button: true,
            label: i.place,
            child: GestureDetector(
              onTap: () => widget.onSelect(i.id),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: IncidentMarkerDot(
                  incident: i,
                  selected: i.id == widget.selectedId,
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
          child: ZoomControls(controller: _controller),
        ),
        if (incidents.isEmpty)
          Center(
            child: Container(
              decoration: floatingCard(p),
              child: EmptyState(
                icon: Symbols.check_circle_rounded,
                title: l10n.queueEmpty,
                message: l10n.queueEmptyMessage,
              ),
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
