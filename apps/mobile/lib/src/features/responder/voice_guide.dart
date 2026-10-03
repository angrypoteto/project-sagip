/// What F4 should say aloud, decided from what its card shows. Each thing
/// is said once: the next turn when it first appears, the same turn again
/// when the unit is [nearMeters] from it, and the arrival. The route is
/// computed again from every new position, so the card's state is fed in
/// often; anything already said stays quiet.
class VoiceGuide {
  VoiceGuide({this.nearMeters = 80});

  final double nearMeters;

  String? _turn;
  var _nearSaid = false;
  var _sceneSaid = false;

  /// [turn] is the next turn's instruction as shown (null when the scene is
  /// on the same street), [meters] the distance to it.
  VoiceLine? update({required bool atScene, String? turn, double? meters}) {
    if (atScene) {
      _turn = null;
      if (_sceneSaid) return null;
      _sceneSaid = true;
      return const VoiceLine.scene();
    }
    if (turn == null || meters == null) {
      _turn = null;
      return null;
    }
    if (turn != _turn) {
      _turn = turn;
      _nearSaid = meters <= nearMeters;
      return _nearSaid ? VoiceLine.now(turn) : VoiceLine.ahead(turn, meters);
    }
    if (!_nearSaid && meters <= nearMeters) {
      _nearSaid = true;
      return VoiceLine.now(turn);
    }
    return null;
  }
}

/// One thing to say.
class VoiceLine {
  const VoiceLine.scene() : turn = null, meters = null;
  const VoiceLine.now(String this.turn) : meters = null;
  const VoiceLine.ahead(String this.turn, double this.meters);

  /// Null for the arrival.
  final String? turn;

  /// Null when the turn is now.
  final double? meters;

  bool get isScene => turn == null;
}

/// A distance as it is said: to 50 m under a kilometre, else to 0.1 km.
({int? meters, String? kilometers}) spokenDistance(double meters) =>
    meters < 1000
    ? (meters: ((meters / 50).round() * 50).clamp(50, 950), kilometers: null)
    : (meters: null, kilometers: (meters / 1000).toStringAsFixed(1));
