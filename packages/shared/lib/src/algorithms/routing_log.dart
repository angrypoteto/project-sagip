import '../models/road_route.dart';
import '../repositories/repositories.dart';

/// Keeps timed runs in memory (mock data and tests).
class MemoryRoutingLog implements RoutingLogRepository {
  final runs = <RoutingRun>[];

  @override
  void log(RoutingRun run) => runs.add(run);
}

/// Passes on at most one run per kind and incident every [minGap].
///
/// Suggestions are recomputed whenever a unit moves (every few seconds on a
/// busy board), and the responder's phone re-routes on every GPS fix; one
/// timing a minute per incident is plenty for Chapter 4.
class ThrottledRoutingLog implements RoutingLogRepository {
  ThrottledRoutingLog(
    this._inner, {
    this.minGap = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RoutingLogRepository _inner;
  final Duration minGap;
  final DateTime Function() _clock;
  final _last = <String, DateTime>{};

  @override
  void log(RoutingRun run) {
    final key = '${run.kind.name}:${run.incidentId}';
    final now = _clock();
    final last = _last[key];
    if (last != null && now.difference(last) < minGap) return;
    _last[key] = now;
    _inner.log(run);
  }
}
