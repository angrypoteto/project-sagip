import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  test('tile numbers match the standard slippy map scheme', () {
    // Manila City Hall, checked with the OSM wiki's Python formula.
    expect(
      tileAt(const GeoPoint(14.5995, 120.9842), 16),
      const TileId(16, 54792, 30081),
    );
    expect(tileAt(const GeoPoint(14.5995, 120.9842), 0), const TileId(0, 0, 0));
    expect(
      const TileId(16, 54792, 30081).url('https://t.example/{z}/{x}/{y}.png'),
      'https://t.example/16/54792/30081.png',
    );
  });

  test('the tiles along a route cover it at every zoom, widest first', () {
    const path = [GeoPoint(14.5995, 120.9842), GeoPoint(14.6091, 120.9925)];
    final tiles = tilesAlong(path, TileSavePolicy.forUrl(osmTileUrl));
    expect(tiles.first.z, 13);
    expect(tiles.map((t) => t.z).toSet(), {13, 14, 15, 16});
    expect(tiles.toSet(), hasLength(tiles.length));
    for (var z = 13; z <= 16; z++) {
      for (final p in path) {
        expect(tiles, contains(tileAt(p, z)));
      }
      // A point halfway along the route is covered too.
      expect(tiles, contains(tileAt(path.first.lerpTo(path.last, 0.5), z)));
    }
    // Zoom order never goes back.
    for (var i = 1; i < tiles.length; i++) {
      expect(tiles[i].z, greaterThanOrEqualTo(tiles[i - 1].z));
    }
  });

  test('OpenStreetMap saves stay small; a self-hosted server goes closer', () {
    final osm = TileSavePolicy.forUrl(osmTileUrl);
    expect(osm.maxZoom, 16);
    final own = TileSavePolicy.forUrl(
      'https://tiles.sagip.example/{z}/{x}/{y}.png',
    );
    expect(own.maxZoom, 17);
    // Over the limit, the closest levels are dropped whole.
    const across = [GeoPoint(14.64, 120.95), GeoPoint(14.56, 121.02)];
    const small = TileSavePolicy(maxZoom: 16, maxTiles: 40);
    final tiles = tilesAlong(across, small);
    expect(tiles.length, lessThanOrEqualTo(40));
    final zooms = tiles.map((t) => t.z).toSet();
    expect(zooms, contains(13));
    expect(zooms, isNot(contains(16)));
    // Each level kept is whole: the next one would not have fitted.
    final next = tilesAlong(
      across,
      TileSavePolicy(
        maxZoom: zooms.reduce((a, b) => a > b ? a : b) + 1,
        maxTiles: 10000,
      ),
    );
    expect(next.length, greaterThan(40));
    expect(tilesAlong(const [], osm), isEmpty);
  });
}
