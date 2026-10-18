import '../algorithms/hazard_penalty.dart';
import '../data/manila_safe_places.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/safe_place.dart';
import '../repositories/repositories.dart';

/// The safe places bundled in the app (OpenStreetMap, the day the list was
/// made), read-only. The phone falls back to it with no connection, and
/// the mobile sample data uses it. It knows only the confirmed floods and
/// fires [hazards] gives (none for a resident: they are not told where
/// those are), and nothing an admin changed on the server.
class BundledSafePlaceRepository implements SafePlaceRepository {
  BundledSafePlaceRepository({this.places = manilaSafePlaces, this.hazards});

  final List<SafePlace> places;

  /// The confirmed open floods and fires to keep away from, if known.
  final List<HazardZone> Function()? hazards;

  @override
  Stream<List<SafePlace>> watchPlaces() => Stream.value(places);

  @override
  Future<List<SafePlaceOption>> nearest(
    GeoPoint from,
    IncidentType need, {
    int limit = SafePlaceRules.defaultLimit,
  }) async => nearestSafePlaces(
    places,
    from,
    need,
    avoid: hazards?.call() ?? const [],
    limit: limit,
  );

  @override
  Future<String> savePlace({
    String? id,
    String? name,
    required SafePlaceKind kind,
    required GeoPoint location,
    required bool official,
  }) => throw const ActionRejected(ActionRejection.notAllowed);

  @override
  Future<void> setHidden(String id, bool hidden) =>
      throw const ActionRejected(ActionRejection.notAllowed);
}
