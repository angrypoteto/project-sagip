import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../models/geo_point.dart';
import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';

// The map base both apps share: muted OpenStreetMap tiles and the credit.

/// Manila City Hall area; the default view for the whole city.
const manilaCenter = LatLng(14.5995, 120.9842);

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// Base map tiles. Development uses the public OpenStreetMap tiles with a
/// muted filter; the plan (Q1, risk 8) replaces these with self-hosted
/// Manila tiles before the pilot, because OSM's servers forbid heavy and
/// offline use.
class SagipTiles extends StatelessWidget {
  const SagipTiles({
    super.key,
    required this.userAgentPackageName,
    this.enabled = true,
  });

  /// Identifies the app to the tile server, for example "ph.sagip.mobile".
  final String userAgentPackageName;

  /// Off in widget tests, which have no network.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: userAgentPackageName,
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: p.panel.withValues(alpha: 0.85),
        child: Text(
          '© $label',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 11),
        ),
      ),
    );
  }
}
