import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/src/supabase/board_cache.dart';

/// Surge test finding 4 (2026-11-03): the board reads only what changed.
void main() {
  var now = DateTime.utc(2026, 11, 3, 8);
  Map<String, dynamic> row(String id, String status, int sec, {int rec = 0}) =>
      {
        'id': id,
        'status': status,
        'received_at': DateTime.utc(2026, 11, 3, 7, 0, rec).toIso8601String(),
        'updated_at': DateTime.utc(2026, 11, 3, 7, 59, sec).toIso8601String(),
      };

  late List<Map<String, dynamic>> open;
  late List<Map<String, dynamic>> changed;
  late List<DateTime> asked;
  late int fullReads;
  late BoardCache cache;

  setUp(() {
    now = DateTime.utc(2026, 11, 3, 8);
    open = [
      row('INC-1', 'pendingVerification', 1, rec: 2),
      row('INC-2', 'assigned', 2, rec: 1),
    ];
    changed = [];
    asked = [];
    fullReads = 0;
    cache = BoardCache(
      fetchOpen: () async {
        fullReads++;
        return open;
      },
      fetchChangedSince: (since) async {
        asked.add(since);
        return changed;
      },
      clock: () => now,
    );
  });

  List<String> ids(List<Map<String, dynamic>> rows) => [
    for (final r in rows) '${r['id']}',
  ];

  test(
    'the first read takes every open incident, oldest received first',
    () async {
      expect(ids(await cache.read()), ['INC-2', 'INC-1']);
      expect(fullReads, 1);
      expect(cache.changeReads, 0);
    },
  );

  test(
    'then only the changes since the newest stamp, less the overlap',
    () async {
      await cache.read();
      changed = [
        row('INC-3', 'pendingVerification', 30, rec: 3),
        row('INC-1', 'confirmed', 31, rec: 2),
      ];
      now = now.add(const Duration(seconds: 5));
      final rows = await cache.read();
      expect(fullReads, 1);
      expect(cache.changeReads, 1);
      // Newest stamp was 07:59:02; asked from 10 s before it.
      expect(asked.single, DateTime.utc(2026, 11, 3, 7, 58, 52));
      expect(ids(rows), ['INC-2', 'INC-1', 'INC-3']);
      expect(rows.firstWhere((r) => r['id'] == 'INC-1')['status'], 'confirmed');
    },
  );

  test('a resolved incident leaves the board', () async {
    await cache.read();
    changed = [row('INC-2', 'resolved', 40, rec: 1)];
    now = now.add(const Duration(seconds: 5));
    expect(ids(await cache.read()), ['INC-1']);
  });

  test('a full read again after a minute', () async {
    await cache.read();
    now = now.add(const Duration(seconds: 30));
    await cache.read();
    expect(fullReads, 1);
    now = now.add(const Duration(seconds: 31));
    open = [row('INC-9', 'pendingVerification', 50)];
    expect(ids(await cache.read()), [
      'INC-9',
    ], reason: 'anything missed is dropped');
    expect(fullReads, 2);
  });

  test('reads never overlap: the second waits for the first', () async {
    final gate = Completer<void>();
    var running = 0;
    var most = 0;
    final slow = BoardCache(
      fetchOpen: () async {
        running++;
        most = running > most ? running : most;
        await gate.future;
        running--;
        return open;
      },
      fetchChangedSince: (_) async {
        running++;
        most = running > most ? running : most;
        running--;
        return const [];
      },
      clock: () => now,
    );
    final a = slow.read();
    final b = slow.read();
    await pumpEventQueue();
    gate.complete();
    await Future.wait([a, b]);
    expect(most, 1);
    expect(
      slow.changeReads,
      1,
      reason: 'the second read took only the changes',
    );
  });

  test('a server without updated_at keeps reading everything', () async {
    open = [
      {
        'id': 'INC-1',
        'status': 'pendingVerification',
        'received_at': '2026-11-03T07:00:00Z',
      },
    ];
    await cache.read();
    now = now.add(const Duration(seconds: 5));
    await cache.read();
    expect(fullReads, 2);
    expect(cache.changeReads, 0);
  });
}
