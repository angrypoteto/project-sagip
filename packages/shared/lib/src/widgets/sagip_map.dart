import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../algorithms/map_tiles.dart';
import '../models/geo_point.dart';
import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';

// The map base both apps share: muted OpenStreetMap tiles and the credit.

/// Manila City Hall area; the default view for the whole city.
const manilaCenter = LatLng(14.5995, 120.9842);

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// The farthest out any map zooms: all of Metro Manila still fits on a
/// phone (Joshua, 2026-10-28: a map could be zoomed out to the whole
/// world, with no streets left to see).
const mapMinZoom = 11.0;

/// How far any map can be dragged: its centre stays over Metro Manila and
/// a margin around it, so it never slides off to the sea or the world.
final mapCameraConstraint = CameraConstraint.containCenter(
  bounds: LatLngBounds(
    const LatLng(14.30, 120.80),
    const LatLng(14.90, 121.25),
  ),
);

/// Base map tiles. Development uses the public OpenStreetMap tiles with a
/// muted filter; the plan (Q1, risk 8) replaces these with self-hosted
/// Manila tiles before the pilot, because OSM's servers forbid heavy and
/// offline use.
///
/// Only what is on screen is loaded (Joshua, 2026-10-28: phones lagged
/// while tracking): no extra ring of tiles around the screen, tiles more
/// than one ring off screen are dropped (and their downloads cancelled),
/// and while panning tiles are loaded and dropped at most every
/// [_tileUpdates].
class SagipTiles extends StatefulWidget {
  const SagipTiles({
    super.key,
    required this.userAgentPackageName,
    this.enabled = true,
    this.urlTemplate = mapTileUrl,
    this.tileProvider,
  });

  /// Where tiles come from ([mapTileUrl] unless a test says otherwise).
  final String urlTemplate;

  /// Null: flutter_map's own network provider. The phone app passes one
  /// that reads the tiles saved for a job (FR13).
  final TileProvider? tileProvider;

  /// Identifies the app to the tile server, for example "ph.sagip.mobile".
  final String userAgentPackageName;

  /// Off in widget tests, which have no network.
  final bool enabled;

  @override
  State<SagipTiles> createState() => _SagipTilesState();
}

/// How often panning may load or drop tiles.
const _tileUpdates = Duration(milliseconds: 120);

class _SagipTilesState extends State<SagipTiles> {
  // One of each per map, made once: building them again on every rebuild
  // (a moving marker, the compass) left a new HTTP client behind each time.
  NetworkTileProvider? _ownProvider;
  final _updates = TileUpdateTransformers.throttle(_tileUpdates);

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The muted filter goes over the whole layer once, not over each tile:
    // two filter passes per frame instead of two per tile. The repaint
    // boundary keeps a moving marker from repainting the tiles under it.
    // Two passes: the first sorts each pixel into "road", "ink", and "warm
    // or cool"; the second paints those in the palette.
    return RepaintBoundary(
      child: ColorFiltered(
        colorFilter: dark ? _paintDark : _paintLight,
        child: ColorFiltered(
          colorFilter: _sort,
          child: TileLayer(
            urlTemplate: widget.urlTemplate,
            userAgentPackageName: widget.userAgentPackageName,
            tileProvider:
                widget.tileProvider ?? (_ownProvider ??= NetworkTileProvider()),
            maxNativeZoom: 19,
            panBuffer: 0,
            keepBuffer: 1,
            tileUpdateTransformer: _updates,
          ),
        ),
      ),
    );
  }
}

// Muted basemaps (design skill: "a muted basemap tuned to the palette"):
// OpenStreetMap's colorful tiles redrawn in quiet tones so only S.A.G.I.P.
// markers carry strong color, without losing the streets. Replaced by a
// styled self-hosted basemap later.
//
// OpenStreetMap tells a street from the block beside it mostly by color: a
// white street on pale grey land differs by a few percent in brightness, a
// yellow or orange main road by none at all. A plain grey filter (what
// this used to be) therefore lost most of the street network, and the map
// looked emptier than the original. One color matrix cannot fix that, but
// two can, because values are cut off at 0 and 255 between them:
//
// 1. [_sort] measures three things per pixel, one per channel:
//    red:   how much lighter than land it is (minor streets, white);
//    green: how much darker than land it is (names, outlines, railways);
//    blue:  how warm it is, around a middle of 128 (above: main roads,
//           which are yellow to red; below: water, which is blue).
// 2. [_paintDark] or [_paintLight] starts from the land color and adds
//    each of the three in a tone of the palette.
//
// The numbers were set by eye on Manila tiles at zooms 13, 15, and 16.
const _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

/// Brighter than this (0 to 1) is a minor street; land is about 0.94.
const _streetFrom = 0.955;
const _streetGain = 9.0;

/// Darker than this is ink; buildings and housing blocks are 0.82 to 0.88.
const _inkFrom = 0.86;
const _inkGain = 1.6;
const _warmGain = 1.4;

final _sort = ColorFilter.matrix(<double>[
  _streetGain * _lr, _streetGain * _lg, _streetGain * _lb, 0, //
  -_streetGain * _streetFrom * 255,
  -_inkGain * _lr, -_inkGain * _lg, -_inkGain * _lb, 0, //
  _inkGain * _inkFrom * 255,
  _warmGain, 0, -_warmGain, 0, 128,
  0, 0, 0, 1, 0,
]);

/// Land in [land] (red, green, blue), plus the three measures of [_sort],
/// each added in its own tone. The warm measure counts from 128.
ColorFilter _paint(
  List<double> land, {
  required List<double> street,
  required List<double> ink,
  required List<double> warm,
}) => ColorFilter.matrix(<double>[
  for (var c = 0; c < 3; c++) ...[
    street[c],
    ink[c],
    warm[c],
    0,
    land[c] - 128 * warm[c],
  ],
  0,
  0,
  0,
  1,
  0,
]);

/// Dark: land near `bay`, streets a lighter blue-grey, main roads a warm
/// grey, water darker than land, names light.
final _paintDark = _paint(
  const [13, 25, 38],
  street: const [0.62, 0.66, 0.72],
  ink: const [0.50, 0.54, 0.60],
  warm: const [0.62, 0.52, 0.34],
);

/// Light: land near `mist`, streets white, main roads a pale amber, water
/// a pale blue, names dark.
final _paintLight = _paint(
  const [232, 235, 239],
  street: const [0.22, 0.20, 0.16],
  ink: const [-0.80, -0.78, -0.74],
  warm: const [0.10, -0.06, -0.50],
);

/// The map's background: the land color of the muted tiles, so a tile
/// still loading looks like empty land instead of a white square (Joshua,
/// 2026-10-28: only the screen's tiles are loaded now, so panning shows
/// them arriving). Pass it as `MapOptions.backgroundColor`.
Color mapBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color.fromARGB(255, 13, 25, 38)
    : const Color.fromARGB(255, 232, 235, 239);

/// The required OpenStreetMap credit, kept small and quiet. [label] comes
/// from the app's l10n file ("OpenStreetMap contributors").
class MapCredit extends StatelessWidget {
  const MapCredit({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(SagipSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: p.panel.withValues(alpha: 0.7),
        // As small as it goes while staying readable: the license asks
        // for a legible credit (Joshua, 2026-10-13).
        child: Text(
          '© $label',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 9),
        ),
      ),
    );
  }
}
