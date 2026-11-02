import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Below this a cell is left unpainted: noise.
const _quietBelow = 0.06;

/// The smallest spread of a barangay's blob, in meters: about the KDE's
/// bandwidth (200 m) and a little more, so a small barangay still shows at
/// city zoom and neighbours run into each other.
const _minSigmaMeters = 260.0;

/// The field's cell size, in meters: fine enough to look smooth once the
/// picture is stretched over the map.
const _cellMeters = 35.0;

/// The heat map over the map (Joshua, 2026-11-02: "like weather radar"):
/// one smooth field, every barangay in [weights] (0 to 1) a soft blob
/// centred on it, coloured from light blue through blue and purple to red
/// ([heatColor]). Where blobs overlap the higher value wins, so neighbours
/// blend without adding up: a barangay's colour never goes past its own
/// level. The field is worked out once per set of weights as a small
/// picture over Manila and stretched over the map; the map does not rotate
/// on the Heatmap page.
class HeatLayer extends StatefulWidget {
  const HeatLayer({super.key, required this.weights});

  final Map<String, double> weights;

  @override
  State<HeatLayer> createState() => _HeatLayerState();
}

class _HeatLayerState extends State<HeatLayer> {
  ui.Image? _image;
  _Field? _field;
  Brightness? _brightness;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      _render();
    }
  }

  @override
  void didUpdateWidget(HeatLayer old) {
    super.didUpdateWidget(old);
    if (!mapEquals(old.weights, widget.weights)) _render();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _render() {
    final mine = ++_generation;
    final field = _Field.of(widget.weights);
    final ramp = heatRamp(SagipPalette.of(context));
    final pixels = field.pixels(ramp);
    if (pixels == null) {
      setState(() {
        _image?.dispose();
        _image = null;
        _field = field;
      });
      return;
    }
    ui.decodeImageFromPixels(
      pixels,
      field.cols,
      field.rows,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || mine != _generation) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _field = field;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final field = _field;
    if (image == null || field == null) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final topLeft = camera.latLngToScreenOffset(
      LatLng(field.north, field.west),
    );
    final bottomRight = camera.latLngToScreenOffset(
      LatLng(field.south, field.east),
    );
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FieldPainter(
          image: image,
          rect: Rect.fromPoints(topLeft, bottomRight),
        ),
      ),
    );
  }
}

/// The ramp, weakest to strongest: light blue, blue, purple, red. Red is
/// the High chips' red, so the strongest colour means the same everywhere.
List<Color> heatRamp(SagipPalette p) => [
  Color.lerp(p.info.fill, SagipColors.porcelain, 0.45)!,
  p.info.fill,
  HSVColor.lerp(
    HSVColor.fromColor(p.info.fill),
    HSVColor.fromColor(p.critical.fill),
    0.5,
  )!.toColor(),
  p.critical.fill,
];

/// Where each colour of [heatRamp] sits (0 to 1): purple low enough that a
/// moderate barangay (riskHeat 0.5 to 0.72) reads purple, not blue.
const heatStops = [0.0, 0.3, 0.6, 1.0];

/// The colour of [value] (0 to 1) on [ramp]; shared with the legend so the
/// two always match.
Color heatColor(double value, List<Color> ramp) {
  final v = value.clamp(0, 1).toDouble();
  for (var i = 1; i < heatStops.length; i++) {
    if (v <= heatStops[i]) {
      final t = (v - heatStops[i - 1]) / (heatStops[i] - heatStops[i - 1]);
      // Round the colour wheel, not straight through: blue to red passes a
      // clear purple instead of a grey mauve.
      return HSVColor.lerp(
        HSVColor.fromColor(ramp[i - 1]),
        HSVColor.fromColor(ramp[i]),
        t,
      )!.toColor();
    }
  }
  return ramp.last;
}

/// How opaque the field is at [value]: fading in smoothly from nothing at
/// the edge of a blob (no hard rim), steadier at its core.
double heatAlpha(double value) {
  final v = value.clamp(0, 1).toDouble();
  if (v <= _quietBelow) return 0;
  final t = math.min(1.0, (v - _quietBelow) / 0.12);
  return t * t * (3 - 2 * t) * (0.66 + 0.26 * v);
}

/// The field over Manila: one value (0 to 1) per cell, each the highest of
/// the barangay blobs over it.
class _Field {
  _Field(
    this.north,
    this.south,
    this.west,
    this.east,
    this.rows,
    this.cols,
    this.values,
  );

  factory _Field.of(Map<String, double> weights) {
    const margin = 0.012;
    var north = -90.0, south = 90.0, west = 180.0, east = -180.0;
    for (final b in manilaBarangays) {
      final c = b.center;
      if (c == null) continue;
      north = math.max(north, c.lat);
      south = math.min(south, c.lat);
      west = math.min(west, c.lng);
      east = math.max(east, c.lng);
    }
    north += margin;
    south -= margin;
    west -= margin;
    east += margin;
    const ky = 110574.0;
    final kx = 111320 * math.cos((north + south) / 2 * math.pi / 180);
    final rows = ((north - south) * ky / _cellMeters).ceil();
    final cols = ((east - west) * kx / _cellMeters).ceil();
    final values = Float32List(rows * cols);
    for (final MapEntry(key: name, value: weight) in weights.entries) {
      if (weight < _quietBelow) continue;
      final c = barangayNamed(name)?.center;
      if (c == null) continue;
      final sigma = math.max(
        _minSigmaMeters,
        (barangayRadiusMeters(name) ?? 0) * 0.9,
      );
      // Rows and columns within three sigmas of the centre.
      final r0 = ((north - c.lat) * ky / _cellMeters).floor();
      final c0 = ((c.lng - west) * kx / _cellMeters).floor();
      final reach = (3 * sigma / _cellMeters).ceil();
      final twoSigma2 = 2 * sigma * sigma;
      for (
        var r = math.max(0, r0 - reach);
        r <= math.min(rows - 1, r0 + reach);
        r++
      ) {
        final dy = (r - r0) * _cellMeters;
        for (
          var k = math.max(0, c0 - reach);
          k <= math.min(cols - 1, c0 + reach);
          k++
        ) {
          final dx = (k - c0) * _cellMeters;
          final v = weight * math.exp(-(dx * dx + dy * dy) / twoSigma2);
          final i = r * cols + k;
          if (v > values[i]) values[i] = v;
        }
      }
    }
    return _Field(north, south, west, east, rows, cols, values);
  }

  final double north, south, west, east;
  final int rows, cols;
  final Float32List values;

  /// The field as RGBA pixels on [ramp]; null when nothing is painted.
  Uint8List? pixels(List<Color> ramp) {
    final out = Uint8List(rows * cols * 4);
    var any = false;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final alpha = heatAlpha(v);
      if (alpha == 0) continue;
      any = true;
      final c = heatColor(v, ramp);
      final o = i * 4;
      // Premultiplied: the engine takes raw pixels with their colour
      // already scaled by their opacity (unscaled, faint edges glowed).
      out[o] = (c.r * alpha * 255).round();
      out[o + 1] = (c.g * alpha * 255).round();
      out[o + 2] = (c.b * alpha * 255).round();
      out[o + 3] = (alpha * 255).round();
    }
    return any ? out : null;
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({required this.image, required this.rect});

  final ui.Image image;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: rect,
      image: image,
      fit: BoxFit.fill,
      // Smooth when stretched: the cells blend into one field.
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.image != image || old.rect != rect;
}
