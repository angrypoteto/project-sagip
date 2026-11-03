import 'dart:async';

/// The open incidents of the Command Board, kept between reads (surge test
/// finding 4, 2026-11-03; docs/SURGE-TEST.md). With 10,000 open incidents
/// the whole board is 10.5 MB, and it was read again on every change. Now
/// the first read, and one a minute after it, take every open incident;
/// the reads in between take only the rows whose `updated_at` is newer
/// than the newest one seen ([overlap] earlier, for a change that was
/// committed a moment after a later one), merge them in, and drop the
/// ones that were resolved.
///
/// Reads never overlap: a read asked for while one runs waits for it, so
/// an older answer can never be merged over a newer one.
class BoardCache {
  BoardCache({
    required this.fetchOpen,
    required this.fetchChangedSince,
    this.fullEvery = const Duration(minutes: 1),
    this.overlap = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Every incident not resolved.
  final Future<List<Map<String, dynamic>>> Function() fetchOpen;

  /// Every incident, resolved or not, changed after the given time.
  final Future<List<Map<String, dynamic>>> Function(DateTime since)
  fetchChangedSince;

  final Duration fullEvery;
  final Duration overlap;
  final DateTime Function() _clock;

  final _rows = <String, Map<String, dynamic>>{};
  DateTime? _newest;
  DateTime? _fullAt;
  Future<void> _last = Future.value();

  /// How many reads took only the changes (for tests).
  int changeReads = 0;

  /// The open incidents' rows, oldest received first.
  Future<List<Map<String, dynamic>>> read() {
    final next = _last.then((_) => _read(), onError: (_) => _read());
    _last = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<Map<String, dynamic>>> _read() async {
    final now = _clock();
    final newest = _newest;
    final fullAt = _fullAt;
    if (newest == null ||
        fullAt == null ||
        now.difference(fullAt) >= fullEvery) {
      final rows = await fetchOpen();
      _rows
        ..clear()
        ..addEntries([for (final r in rows) MapEntry('${r['id']}', r)]);
      _fullAt = now;
      _newest = _newestOf(rows, null);
      // A server without `updated_at` (before migration board_changes)
      // gives no stamp: every read stays a full one.
      if (rows.isNotEmpty && rows.any((r) => r['updated_at'] == null)) {
        _newest = null;
      }
    } else {
      final rows = await fetchChangedSince(newest.subtract(overlap));
      changeReads++;
      for (final r in rows) {
        final id = '${r['id']}';
        if (r['status'] == 'resolved') {
          _rows.remove(id);
        } else {
          _rows[id] = r;
        }
      }
      _newest = _newestOf(rows, newest);
    }
    final out = _rows.values.toList()
      ..sort((a, b) => '${a['received_at']}'.compareTo('${b['received_at']}'));
    return out;
  }

  /// The newest `updated_at` among [rows], or [start].
  static DateTime? _newestOf(List<Map<String, dynamic>> rows, DateTime? start) {
    var newest = start;
    for (final r in rows) {
      final raw = r['updated_at'];
      if (raw is! String) continue;
      final t = DateTime.tryParse(raw);
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return newest;
  }
}
