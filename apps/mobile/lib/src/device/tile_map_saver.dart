import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:sagip_shared/sagip_shared.dart';

/// How long a saved tile counts as fresh, so it is shown with no signal.
/// A job takes hours, not weeks; the map of Manila changes slowly.
const savedTileAge = Duration(days: 14);

/// The phone's map tile cache, shared by every map in the app and by
/// [TileMapSaver], so saved tiles are the ones the maps read (flutter_map's
/// built-in cache, in the app's cache folder).
MapCachingProvider phoneTileCache() =>
    BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 300 * 1024 * 1024,
      overrideFreshAge: savedTileAge,
    );

/// Saves the map around a job at dispatch time (FR13): every tile along
/// the route, within [TileSavePolicy.forUrl]'s limits, one request at a
/// time, skipping tiles already saved.
class TileMapSaver implements MapSaver {
  TileMapSaver({
    required this._cache,
    http.Client? client,
    this.urlTemplate = mapTileUrl,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final MapCachingProvider _cache;
  final http.Client _client;
  final DateTime Function() _clock;
  final String urlTemplate;

  /// The same name flutter_map gives the tile server.
  static const userAgent = 'flutter_map (ph.sagip.mobile)';

  @override
  Stream<double> save(List<GeoPoint> path) async* {
    if (!_cache.isSupported) {
      throw UnsupportedError('This device cannot keep map tiles.');
    }
    final tiles = tilesAlong(path, TileSavePolicy.forUrl(urlTemplate));
    if (tiles.isEmpty) {
      yield 1;
      return;
    }
    yield 0;
    var done = 0;
    for (final tile in tiles) {
      final url = tile.url(urlTemplate);
      if (!await _fresh(url)) {
        final res = await _client.get(
          Uri.parse(url),
          headers: {'User-Agent': userAgent},
        );
        if (res.statusCode != 200) {
          throw http.ClientException('Tile $tile: ${res.statusCode}');
        }
        await _cache.putTile(
          url: url,
          metadata: CachedMapTileMetadata(
            staleAt: _clock().toUtc().add(savedTileAge),
            lastModified: null,
            etag: res.headers['etag'],
          ),
          bytes: res.bodyBytes,
        );
      }
      done++;
      yield done / tiles.length;
    }
  }

  Future<bool> _fresh(String url) async {
    try {
      final tile = await _cache.getTile(url);
      return tile != null && !tile.metadata.isStale;
    } on Object {
      return false;
    }
  }
}
