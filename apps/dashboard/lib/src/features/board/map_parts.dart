import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// The shared base map, switched off in widget tests.
class SagipBaseMap extends ConsumerWidget {
  const SagipBaseMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SagipTiles(
    userAgentPackageName: 'ph.sagip.dashboard',
    enabled: ref.watch(mapTilesEnabledProvider),
  );
}

/// Every barangay's outline as map points, made once.
final Map<String, List<List<LatLng>>> _outlines = {
  for (final b in manilaBarangays)
    b.name: [
      for (final ring in barangayOutline(b.name))
        [for (final p in ring) toLatLng(p)],
    ],
};

/// Manila's 897 barangay boundaries (PSA, indicative): thin lines, an
/// optional fill per barangay, and one highlighted barangay.
///
/// The shapes are made once and kept until the fills, the highlight, or
/// the theme change: flutter_map keeps what it worked out for a list of
/// polygons only while it is handed the same list, and working that out
/// again for 897 shapes on every rebuild made the map stutter.
class BarangayBoundaries extends StatefulWidget {
  const BarangayBoundaries({super.key, this.fills = const {}, this.highlight});

  /// Fill color by barangay name; barangays not listed are not filled.
  final Map<String, Color> fills;

  /// Drawn with a stronger, thicker line.
  final String? highlight;

  @override
  State<BarangayBoundaries> createState() => _BarangayBoundariesState();
}

class _BarangayBoundariesState extends State<BarangayBoundaries> {
  List<Polygon>? _polygons;
  SagipPalette? _palette;

  @override
  void didUpdateWidget(BarangayBoundaries old) {
    super.didUpdateWidget(old);
    if (old.highlight != widget.highlight ||
        !mapEquals(old.fills, widget.fills)) {
      _polygons = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    if (!identical(p, _palette)) {
      _palette = p;
      _polygons = null;
    }
    return PolygonLayer(polygons: _polygons ??= _build(p));
  }

  List<Polygon> _build(SagipPalette p) {
    final fills = widget.fills;
    final highlight = widget.highlight;
    final polygons = <Polygon>[];
    Polygon<Object> shape(String name, List<LatLng> ring, {bool top = false}) =>
        Polygon(
          points: ring,
          color: fills[name],
          // Quiet but visible over the muted basemap in both themes.
          borderColor: top
              ? p.textPrimary
              : p.textSecondary.withValues(alpha: 0.55),
          borderStrokeWidth: top ? 2.5 : 1,
        );
    for (final entry in _outlines.entries) {
      if (entry.key == highlight) continue;
      for (final ring in entry.value) {
        polygons.add(shape(entry.key, ring));
      }
    }
    // The highlighted barangay last, so its line is on top.
    for (final ring in _outlines[highlight] ?? const <List<LatLng>>[]) {
      polygons.add(shape(highlight!, ring, top: true));
    }
    return polygons;
  }
}

/// The ping of a waiting SOS: two rings that spread from the dot to the
/// edge of the marker and fade, one after the other, without end. It is
/// the one looping motion on the dashboard, kept for the one thing that
/// must not be overlooked.
class _SosPing extends StatefulWidget {
  const _SosPing({required this.color, required this.from, required this.to});

  final Color color;

  /// Diameters the ring grows between.
  final double from;
  final double to;

  @override
  State<_SosPing> createState() => _SosPingState();
}

class _SosPingState extends State<_SosPing>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.to),
      painter: _PingPainter(_beat, widget.color, widget.from, widget.to),
    ),
  );
}

class _PingPainter extends CustomPainter {
  _PingPainter(this.beat, this.color, this.from, this.to)
    : super(repaint: beat);

  final Animation<double> beat;
  final Color color;
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The second ring starts half a beat after the first.
    for (final offset in const [0.0, 0.5]) {
      final t = Curves.easeOut.transform((beat.value + offset) % 1);
      final radius = (from + (to - from) * t) / 2;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - t) + 0.5
          ..color = color.withValues(alpha: 0.85 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_PingPainter old) =>
      old.color != color || old.from != from || old.to != to;
}

/// The OpenStreetMap credit with the dashboard's wording.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      MapCredit(label: AppLocalizations.of(context).mapAttribution);
}

/// Incident marker: a clean circle with a status color; confirmed incidents
/// get a signal ring; clusters show their report count.
class IncidentMarkerDot extends StatelessWidget {
  const IncidentMarkerDot({
    super.key,
    required this.incident,
    required this.selected,
    this.ping = false,
  });

  final Incident incident;
  final bool selected;

  /// Rings spread out from the marker, again and again: an SOS that still
  /// waits for a unit. It stops the moment a unit is sent.
  final bool ping;

  /// An SOS nobody has been sent to yet.
  static bool waits(Incident i) =>
      i.origin == IncidentOrigin.sos &&
      i.assignedUnitId == null &&
      i.status != IncidentStatus.resolved;

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
        if (ping)
          // People who turned animations off get one still ring instead.
          MediaQuery.disableAnimationsOf(context)
              ? Container(
                  width: size * 0.75,
                  height: size * 0.75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: visual.tone.fill, width: 2),
                  ),
                )
              : _SosPing(color: visual.tone.fill, from: dot, to: size),
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

/// A confirmed cluster on the crowd reports map: its number of reports in
/// a signal dot, readable at city zoom where the 50 m ring is a few pixels.
class ClusterCountMarker extends StatelessWidget {
  const ClusterCountMarker({super.key, required this.count});

  final int count;

  static const double size = 30;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.critical.fill,
        shape: BoxShape.circle,
        border: Border.all(color: p.canvas, width: 3),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: SagipColors.porcelain,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
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
