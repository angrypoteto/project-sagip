import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sagip_mobile/src/device/tile_map_saver.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// flutter_map's cache interface, in memory.
class _MemoryCache implements MapCachingProvider {
  final tiles = <String, CachedMapTile>{};

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => tiles[url];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    tiles[url] = (bytes: bytes ?? tiles[url]!.bytes, metadata: metadata);
  }
}

void main() {
  const path = [GeoPoint(14.5995, 120.9842), GeoPoint(14.6091, 120.9925)];
  final now = DateTime.utc(2026, 10, 3, 6);
  const template = 'https://tiles.sagip.example/{z}/{x}/{y}.png';

  test('saves every tile along the route, fresh for two weeks', () async {
    final cache = _MemoryCache();
    final asked = <String>[];
    final saver = TileMapSaver(
      cache: cache,
      urlTemplate: template,
      clock: () => now,
      client: MockClient((req) async {
        asked.add(req.url.toString());
        expect(req.headers['User-Agent'], 'flutter_map (ph.sagip.mobile)');
        return http.Response.bytes([1, 2, 3], 200, headers: {'etag': 'v1'});
      }),
    );
    final progress = await saver.save(path).toList();
    final expected = tilesAlong(path, TileSavePolicy.forUrl(template));

    expect(progress.first, 0);
    expect(progress.last, 1);
    expect(progress, hasLength(expected.length + 1));
    expect(asked, [for (final t in expected) t.url(template)]);
    final saved = cache.tiles[expected.last.url(template)]!;
    expect(saved.bytes, [1, 2, 3]);
    expect(saved.metadata.etag, 'v1');
    expect(saved.metadata.staleAt, now.add(savedTileAge));
    // Street level is saved on a self-hosted server.
    expect(expected.map((t) => t.z).toSet(), contains(17));
  });

  test('tiles already saved are not fetched again', () async {
    final cache = _MemoryCache();
    var requests = 0;
    TileMapSaver saver() => TileMapSaver(
      cache: cache,
      urlTemplate: template,
      clock: () => now,
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes([9], 200);
      }),
    );
    await saver().save(path).drain<void>();
    final first = requests;
    await saver().save(path).drain<void>();
    expect(requests, first);
  });

  test('a refused tile ends the save; what was saved stays', () async {
    final cache = _MemoryCache();
    var n = 0;
    final saver = TileMapSaver(
      cache: cache,
      urlTemplate: template,
      clock: () => now,
      client: MockClient(
        (_) async =>
            ++n <= 3 ? http.Response.bytes([1], 200) : http.Response('no', 429),
      ),
    );
    final seen = <double>[];
    await expectLater(
      saver.save(path).forEach(seen.add),
      throwsA(isA<http.ClientException>()),
    );
    expect(cache.tiles, hasLength(3));
    expect(seen.last, greaterThan(0));
    expect(seen.last, lessThan(1));
  });
}
