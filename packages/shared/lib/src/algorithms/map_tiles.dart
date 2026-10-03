import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';

/// The map tile address both apps use, unless the build names another
/// (`--dart-define=MAP_TILE_URL=...`, for the self-hosted Manila tiles the
/// plan wants before the pilot).
const mapTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: osmTileUrl,
);

/// OpenStreetMap's public tiles: fine for light development use only. Its
/// tile policy forbids saving large areas, and zoom 17 and closer, for
/// offline use, so [TileSavePolicy.forUrl] keeps saves small on it.
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// One map tile (Web Mercator, the usual z/x/y scheme).
@immutable
class TileId {
  const TileId(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  /// The tile's address under [template] (with `{z}`, `{x}`, `{y}`).
  String url(String template) => template
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  @override
  bool operator ==(Object other) =>
      other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// The tile at zoom [z] that holds [p].
TileId tileAt(GeoPoint p, int z) {
  final n = 1 << z;
  final lat = p.lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final x = ((p.lng + 180) / 360 * n).floor().clamp(0, n - 1);
  final y =
      ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)
          .floor()
          .clamp(0, n - 1);
  return TileId(z, x, y);
}

/// How much map a save may take from a tile server.
@immutable
class TileSavePolicy {
  const TileSavePolicy({
    this.minZoom = 13,
    required this.maxZoom,
    required this.maxTiles,
    this.bufferMeters = 250,
  });

  /// OpenStreetMap's public server: up to zoom 16 and a few hundred tiles,
  /// within its rules for light use. A self-hosted server: street level
  /// (zoom 17) and more tiles.
  factory TileSavePolicy.forUrl(String template) =>
      template.contains('tile.openstreetmap.org')
      ? const TileSavePolicy(maxZoom: 16, maxTiles: 300)
      : const TileSavePolicy(maxZoom: 17, maxTiles: 800);

  final int minZoom;
  final int maxZoom;
  final int maxTiles;

  /// How far either side of the route to save.
  final double bufferMeters;
}

/// The tiles covering [path] and [policy]'s buffer around it, from the
/// widest zoom to the closest. When they would exceed the policy's limit,
/// the closest zoom levels are left out whole, so every level kept covers
/// the full route.
List<TileId> tilesAlong(List<GeoPoint> path, TileSavePolicy policy) {
  if (path.isEmpty) return const [];
  final levels = <List<TileId>>[];
  var total = 0;
  for (var z = policy.minZoom; z <= policy.maxZoom; z++) {
    final level = _levelTiles(path, z, policy.bufferMeters);
    if (total + level.length > policy.maxTiles) break;
    levels.add(level);
    total += level.length;
  }
  return [for (final l in levels) ...l];
}

List<TileId> _levelTiles(List<GeoPoint> path, int z, double buffer) {
  // Tile width in meters at this latitude; sample the route more finely
  // than that so no tile along it is skipped.
  final lat0 = path.first.lat * math.pi / 180;
  final tileMeters = 40075016.686 * math.cos(lat0) / (1 << z);
  final step = math.min(tileMeters / 4, buffer);
  final dLat = buffer / 110574;
  final dLng = buffer / (111320 * math.cos(lat0));
  final seen = <TileId>{};
  final out = <TileId>[];

  void cover(GeoPoint p) {
    final a = tileAt(GeoPoint(p.lat + dLat, p.lng - dLng), z);
    final b = tileAt(GeoPoint(p.lat - dLat, p.lng + dLng), z);
    for (var x = a.x; x <= b.x; x++) {
      for (var y = a.y; y <= b.y; y++) {
        final t = TileId(z, x, y);
        if (seen.add(t)) out.add(t);
      }
    }
  }

  cover(path.first);
  for (var i = 1; i < path.length; i++) {
    final from = path[i - 1], to = path[i];
    final n = math.max(1, (from.distanceTo(to) / step).ceil());
    for (var k = 1; k <= n; k++) {
      cover(from.lerpTo(to, k / n));
    }
  }
  return out;
}
