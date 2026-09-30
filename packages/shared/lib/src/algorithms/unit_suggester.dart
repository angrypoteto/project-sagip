import '../models/incident.dart';
import '../models/records.dart';
import '../models/response_unit.dart';

/// Ranks units that could respond to an incident (FR3).
abstract interface class UnitSuggester {
  /// The best [limit] dispatchable units, fastest first.
  Future<List<UnitSuggestion>> suggest(
    Incident incident,
    List<ResponseUnit> units, {
    int limit = 3,
  });
}

/// Ranks Available units by straight-line distance at an assumed city speed.
///
/// A stand-in until Dijkstra over the OSM road graph is ready (plan 10.2),
/// and the fallback when routing fails. The UI labels these ETAs as
/// estimated by distance.
class StraightLineSuggester implements UnitSuggester {
  const StraightLineSuggester({
    this.averageSpeedKmh = 20,
    this.detourFactor = 1.3,
  });

  /// Typical Manila travel speed during a storm, to be tuned with MDRRMD's
  /// dispatch records (Table 3.1 item 2).
  final double averageSpeedKmh;

  /// Roads are never straight; this approximates the extra distance.
  final double detourFactor;

  @override
  Future<List<UnitSuggestion>> suggest(
    Incident incident,
    List<ResponseUnit> units, {
    int limit = 3,
  }) async {
    final ranked = <UnitSuggestion>[
      for (final unit in units)
        if (unit.isDispatchable && unit.location != null)
          _estimate(unit, unit.location!.distanceTo(incident.location)),
    ]..sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return ranked.take(limit).toList();
  }

  UnitSuggestion _estimate(ResponseUnit unit, double meters) {
    final km = meters / 1000 * detourFactor;
    return UnitSuggestion(
      unit: unit,
      distanceKm: km,
      etaMinutes: km / averageSpeedKmh * 60,
      method: RoutingMethod.straightLine,
    );
  }
}
