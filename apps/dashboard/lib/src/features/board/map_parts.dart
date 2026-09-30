import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Manila City Hall area; the default view for the whole city.
const manilaCenter = LatLng(14.5995, 120.9842);

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// Base map layer. Development uses the public OpenStreetMap tiles with a dark
/// filter; the plan (Q1, risk 8) replaces these with self-hosted Manila tiles
/// before the pilot, because OSM's servers forbid heavy and offline use.
class SagipBaseMap extends ConsumerWidget {
  const SagipBaseMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mapTilesEnabledProvider)) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'ph.sagip.dashboard',
      maxNativeZoom: 19,
      tileBuilder: (context, tile, image) => ColorFiltered(
        colorFilter: dark ? _mutedDark : _mutedLight,
        child: tile,
      ),
    );
  }
}

// Muted basemaps (design skill: "a muted basemap tuned to the palette").
// Both turn the colorful OSM style into grey tones so only S.A.G.I.P. markers
// carry color. Dark: inverted luminance, tinted toward `bay`. Light: washed-out
// greys near `mist`. Replaced by a styled self-hosted basemap later.
const _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

ColorFilter _grey(
  List<double> scale,
  List<double> offset, {
  bool invert = false,
}) {
  final sign = invert ? -1.0 : 1.0;
  List<double> row(int c) => [
    sign * _lr * scale[c],
    sign * _lg * scale[c],
    sign * _lb * scale[c],
    0,
    offset[c] + (invert ? 255 * scale[c] : 0),
  ];
  return ColorFilter.matrix([...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0]);
}

final _mutedDark = _grey(
  const [0.45, 0.50, 0.58],
  const [11, 23, 36],
  invert: true,
);
final _mutedLight = _grey(const [0.52, 0.53, 0.55], const [112, 112, 112]);

/// Required OpenStreetMap credit, kept small and quiet.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(SagipSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: p.panel.withValues(alpha: 0.85),
        child: Text(
          '© ${AppLocalizations.of(context).mapAttribution}',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 11),
        ),
      ),
    );
  }
}

/// Incident marker: a clean circle with a status color; confirmed incidents
/// get a signal ring; clusters show their report count.
class IncidentMarkerDot extends StatelessWidget {
  const IncidentMarkerDot({
    super.key,
    required this.incident,
    required this.selected,
  });

  final Incident incident;
  final bool selected;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final visual = incidentStatusVisual(incident.status, p);
    final isCluster = incident.origin == IncidentOrigin.crowdCluster;
    final outline = visual.look == ChipLook.outline;
    final dot = isCluster ? 34.0 : 26.0;
    final ring = incident.status == IncidentStatus.confirmed;
    // Ember takes dark text; the other fills take white.
    final onFill = identical(visual.tone, p.warning)
        ? SagipColors.bay
        : SagipColors.porcelain;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (selected)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: visual.tone.fill.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
          ),
        Container(
          width: dot,
          height: dot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outline ? p.canvas : visual.tone.fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: outline ? visual.tone.text : p.canvas,
              width: 3,
            ),
            boxShadow: ring
                ? [BoxShadow(color: visual.tone.fill, spreadRadius: 2)]
                : null,
          ),
          child: isCluster
              ? Text(
                  '${incident.crowdReportIds.length}',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: outline ? visual.tone.text : onFill,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(
                  Symbols.sos_rounded,
                  size: 14,
                  color: outline ? visual.tone.text : onFill,
                ),
        ),
      ],
    );
  }
}

/// Unit marker: a rounded square with the unit type icon, colored by status.
class UnitMarkerSquare extends StatelessWidget {
  const UnitMarkerSquare({super.key, required this.unit});

  final ResponseUnit unit;

  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final busy = !unit.isDispatchable;
    final tone = busy ? unitStatusVisual(unit.status, p).tone : p.success;
    final fill = unit.status == UnitStatus.available && busy
        ? p
              .info
              .fill // Assigned but not yet moving.
        : tone.fill;
    return Tooltip(
      message: unit.callSign,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(SagipRadius.control),
          border: Border.all(color: p.canvas, width: 2),
        ),
        child: Icon(unitTypeIcon(unit.type), size: 16, color: SagipColors.bay),
      ),
    );
  }
}

/// Unverified single crowd report: a dashed hollow circle.
class ReportMarkerRing extends StatelessWidget {
  const ReportMarkerRing({super.key, this.clustered = false});

  final bool clustered;

  static const double size = 20;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    if (clustered) {
      return Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: p.critical.fill,
            shape: BoxShape.circle,
            border: Border.all(color: p.canvas, width: 2),
          ),
        ),
      );
    }
    return CustomPaint(
      painter: DashedRRectPainter(
        color: p.textSecondary,
        radius: size / 2,
        strokeWidth: 2,
        dash: 3,
        gap: 3,
      ),
      child: const SizedBox(width: size, height: size),
    );
  }
}

/// Floating card style for controls over the map.
BoxDecoration floatingCard(SagipPalette p) => BoxDecoration(
  color: p.panel,
  borderRadius: BorderRadius.circular(SagipRadius.card),
  border: Border.all(color: p.hairline),
  boxShadow: const [
    BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
  ],
);

/// Zoom buttons for a [MapController].
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.controller});

  final MapController controller;

  void _zoom(double delta) {
    final camera = controller.camera;
    controller.move(camera.center, camera.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: floatingCard(SagipPalette.of(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.zoomIn,
            onPressed: () => _zoom(1),
            icon: const Icon(Symbols.add_rounded),
          ),
          IconButton(
            tooltip: l10n.zoomOut,
            onPressed: () => _zoom(-1),
            icon: const Icon(Symbols.remove_rounded),
          ),
        ],
      ),
    );
  }
}
