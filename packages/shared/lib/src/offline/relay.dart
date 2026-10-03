import 'dart:async';
import 'dart:typed_data';

import '../algorithms/sos_relay.dart';
import '../mock/live_value.dart';
import '../repositories/repositories.dart';
import 'outbox.dart';
import 'streams.dart';

/// The phone's Bluetooth LE radio for Tier 3 (plan section 11, Q32):
/// store-and-forward over advertising, not Bluetooth SIG Mesh, which
/// Flutter apps cannot use. Every phone that relays must have the app
/// running.
abstract interface class RelayRadio {
  /// True when this phone can advertise and scan (Bluetooth LE on, the
  /// Nearby devices permission granted, advertising supported).
  Future<bool> isSupported();

  /// Advertises [packet] under [key] until [stop]. False when it could not
  /// start (Bluetooth off, no permission, too many adverts).
  Future<bool> advertise(String key, Uint8List packet);

  Future<void> stop(String key);

  /// The service data of every SOS packet heard nearby (repeats included).
  Stream<Uint8List> heard();
}

/// Tier 3 for the phone's own SOS: [SyncEngine] advertises it when there
/// is neither internet nor a way to text.
class RelayTier {
  const RelayTier({required this.radio, required this.available});

  final RelayRadio radio;

  /// True while relaying is the way out (no internet, no cellular signal).
  final Stream<bool> available;

  /// The advert key for the phone's own SOS.
  static String ownKey(String clientId) => 'own:$clientId';
}

/// One SOS this phone heard from another phone.
class HeardSos {
  const HeardSos({
    required this.packet,
    required this.heardAt,
    this.uploaded = false,
    this.dropped,
  });

  final SosRelayPacket packet;
  final DateTime heardAt;

  /// The server has it (from this phone, or it said it already had it).
  final bool uploaded;

  /// Why the server refused it (outside Manila, too many relays); kept so
  /// it is not sent again.
  final String? dropped;

  bool get done => uploaded || dropped != null;

  HeardSos copyWith({
    SosRelayPacket? packet,
    bool? uploaded,
    String? dropped,
  }) => HeardSos(
    packet: packet ?? this.packet,
    heardAt: heardAt,
    uploaded: uploaded ?? this.uploaded,
    dropped: dropped ?? this.dropped,
  );

  Map<String, Object?> toJson() => {
    'packet': packet.toJson(),
    'heard_at': heardAt.toUtc().toIso8601String(),
    'uploaded': uploaded,
    'dropped': dropped,
  };

  factory HeardSos.fromJson(Map<String, Object?> json) => HeardSos(
    packet: SosRelayPacket.fromJson(
      (json['packet']! as Map).cast<String, Object?>(),
    ),
    heardAt: DateTime.parse(json['heard_at']! as String),
    uploaded: json['uploaded'] as bool? ?? false,
    dropped: json['dropped'] as String?,
  );
}

/// What this phone does for SOS packets it hears (Tier 3): keep them on the
/// phone, pass them on (one more hop, up to [SosRelayPacket.maxHops]) while
/// it has no internet, and upload them as soon as it has. A packet whose
/// id is one of this phone's own SOS is ignored.
class RelayNode {
  RelayNode({
    required this._radio,
    required this._store,
    required Stream<bool> online,
    required this._upload,
    required this._ownIds,
    DateTime Function()? clock,
    this.maxPassedOn = 3,
  }) : _onlineSource = online,
       _clock = clock ?? DateTime.now;

  final RelayRadio _radio;
  final LocalStore _store;
  final Stream<bool> _onlineSource;

  /// Sends one packet to the server (`relay_sos`). Throws
  /// [ActionRejected] with [ActionRejection.offline] when it cannot reach
  /// the server; any other [ActionRejected] means refused.
  final Future<void> Function(SosRelayPacket packet) _upload;

  /// The client ids of this phone's own SOS.
  final Set<String> Function() _ownIds;
  final DateTime Function() _clock;

  /// How many heard packets this phone advertises at once (phones allow
  /// only a few adverts).
  final int maxPassedOn;

  /// Packets older than this are forgotten.
  static const keepFor = Duration(hours: 24);
  static const _key = 'relay:heard';

  late final _heard = LiveValue<Map<String, HeardSos>>(_load());
  final _passing = <String>{};
  StreamSubscription<Uint8List>? _heardSub;
  StreamSubscription<bool>? _onlineSub;
  var _online = false;
  var _uploading = false;

  /// What this phone is carrying for others, newest first.
  Stream<List<HeardSos>> watch() => _heard.watch().map(
    (m) => m.values.toList()..sort((a, b) => b.heardAt.compareTo(a.heardAt)),
  );

  Map<String, HeardSos> _load() {
    final raw = _store.read(_key);
    final json = raw is String ? jsonDecodeSafe(raw) : null;
    final now = _clock();
    final out = <String, HeardSos>{};
    for (final e in json is List ? json : const []) {
      try {
        final h = HeardSos.fromJson((e as Map).cast<String, Object?>());
        if (now.difference(h.heardAt) < keepFor) out[h.packet.clientId] = h;
      } catch (_) {
        // A damaged entry is skipped.
      }
    }
    return out;
  }

  Future<void> _save() => _store.write(
    _key,
    jsonEncodeSafe([for (final h in _heard.value.values) h.toJson()]),
  );

  void _put(HeardSos h) =>
      _heard.value = {..._heard.value, h.packet.clientId: h};

  /// Starts listening (call once the account is known). Calling it again
  /// listens again, for example after the Nearby devices permission was
  /// granted.
  Future<void> start() async {
    await _heardSub?.cancel();
    _heardSub = _radio.heard().listen(_onHeard, onError: (Object _) {});
    _onlineSub ??= _onlineSource.listen((on) {
      _online = on;
      if (on) {
        unawaited(uploadAll());
      } else {
        unawaited(_passOn());
      }
    });
  }

  void _onHeard(Uint8List bytes) {
    final SosRelayPacket packet;
    try {
      packet = SosRelayPacket.decode(bytes, _clock());
    } on FormatException {
      return;
    }
    if (_ownIds().contains(packet.clientId)) return;
    final known = _heard.value[packet.clientId];
    if (known != null && known.packet.hops <= packet.hops) return;
    _put(
      known == null
          ? HeardSos(packet: packet, heardAt: _clock())
          : known.copyWith(packet: packet),
    );
    unawaited(_save());
    if (_online) {
      unawaited(uploadAll());
    } else {
      unawaited(_passOn());
    }
  }

  /// Advertises the newest packets not yet uploaded, one hop further.
  Future<void> _passOn() async {
    final waiting = [
      for (final h in _heard.value.values)
        if (!h.done && h.packet.canHop) h,
    ]..sort((a, b) => b.heardAt.compareTo(a.heardAt));
    final keep = {for (final h in waiting.take(maxPassedOn)) h.packet.clientId};
    for (final id in _passing.difference(keep).toList()) {
      await _radio.stop(_relayKey(id));
      _passing.remove(id);
    }
    for (final h in waiting.take(maxPassedOn)) {
      if (_passing.contains(h.packet.clientId)) continue;
      if (await _radio.advertise(
        _relayKey(h.packet.clientId),
        h.packet.nextHop().encode(),
      )) {
        _passing.add(h.packet.clientId);
      }
    }
  }

  static String _relayKey(String id) => 'relay:$id';

  /// Sends every packet not yet uploaded, oldest first.
  Future<void> uploadAll() async {
    if (_uploading) return;
    _uploading = true;
    try {
      final waiting = [
        for (final h in _heard.value.values)
          if (!h.done) h,
      ]..sort((a, b) => a.heardAt.compareTo(b.heardAt));
      for (final h in waiting) {
        try {
          await _upload(h.packet);
          _put(h.copyWith(uploaded: true));
        } on ActionRejected catch (e) {
          if (e.reason == ActionRejection.offline) break;
          _put(h.copyWith(dropped: e.reason.name));
        }
        final id = h.packet.clientId;
        if (_passing.remove(id)) await _radio.stop(_relayKey(id));
      }
      await _save();
    } finally {
      _uploading = false;
    }
  }

  /// Stops listening and advertising (signed out). What was heard stays
  /// on the phone for the next account.
  Future<void> stop() async {
    await _heardSub?.cancel();
    _heardSub = null;
    await _onlineSub?.cancel();
    _onlineSub = null;
    for (final id in _passing.toList()) {
      await _radio.stop(_relayKey(id));
    }
    _passing.clear();
  }

  Future<void> dispose() => stop();
}
