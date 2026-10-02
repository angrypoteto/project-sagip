import 'dart:async';

import '../models/enums.dart';
import '../models/people.dart';
import '../offline/outbox.dart';

// Push notifications (FR6, FR14; plan part 7) through Firebase Cloud
// Messaging. Alerts go to topics (every resident's phone is on "manila"
// and on its barangay's topic); rescue confirmations and new assignments go
// to the account's own phones, whose tokens the server keeps.

/// Every resident's and responder's phone is subscribed to this topic.
const allManilaTopic = 'manila';

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ñ': 'n', 'ç': 'c',
};

/// The FCM topic of one barangay ("Barangay 412" -> "area-barangay-412").
/// Must match `topicForBarangay` in supabase/functions/send-alerts/fcm.ts
/// (the tests share their vectors).
String pushTopicForBarangay(String barangay) {
  final mapped = [
    for (final c in barangay.toLowerCase().split('')) _accents[c] ?? c,
  ].join();
  final slug = mapped
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'area-${slug.isEmpty ? 'unknown' : slug}';
}

/// The topics a phone should be on for [user]: residents get all of
/// Manila and their barangay; responders get all of Manila.
Set<String> pushTopicsFor(AppUser? user, {String? barangay}) {
  if (user == null) return const {};
  return switch (user.role) {
    UserRole.resident => {
      allManilaTopic,
      if (barangay != null && barangay.trim().isNotEmpty)
        pushTopicForBarangay(barangay),
    },
    UserRole.responder => {allManilaTopic},
    _ => const {},
  };
}

/// What a tapped notification is about.
enum PushKind { alert, rescue, assignment }

/// A notification the person tapped, read from its data.
class PushOpen {
  const PushOpen({required this.kind, this.alertId, this.incidentId});

  final PushKind kind;
  final String? alertId;
  final String? incidentId;

  /// Null for data the app does not know (an older or newer sender).
  static PushOpen? fromData(Map<String, Object?> data) {
    final type = data['type'];
    final kind = PushKind.values.where((k) => k.name == type).firstOrNull;
    if (kind == null) return null;
    final alert = data['alert_id'] as String?;
    final incident = data['incident_id'] as String?;
    if (kind == PushKind.alert && (alert == null || alert.isEmpty)) return null;
    if (kind != PushKind.alert && (incident == null || incident.isEmpty)) {
      return null;
    }
    return PushOpen(kind: kind, alertId: alert, incidentId: incident);
  }
}

/// The phone's push service: FCM on Android, a fake in tests.
abstract interface class PushDevice {
  /// This install's token; null when push is not available.
  Future<String?> token();

  /// A new token, when FCM replaces the old one.
  Stream<String> get tokenRefreshes;

  Future<void> subscribe(String topic);
  Future<void> unsubscribe(String topic);

  /// Drops this install's token, so nothing addressed to it arrives.
  Future<void> deleteToken();

  /// The data of each notification the person taps, including the one that
  /// started the app.
  Stream<Map<String, Object?>> get opened;
}

/// The server's list of phones (`push_device`).
abstract interface class PushRegistry {
  Future<void> register(String token);
  Future<void> forget(String token);
}

/// Keeps this phone's push set-up in step with the signed-in account:
/// registered with the server, on the right topics, and cleared at
/// sign-out so the next account on a shared phone gets nothing meant for
/// the last one. Every step is best effort: push must never block the
/// app, and a step that fails offline is done again at the next start.
class PushCoordinator {
  PushCoordinator({
    required this._device,
    required this._registry,
    required this._store,
  }) {
    _refreshes = _device.tokenRefreshes.listen((token) async {
      if (_signedIn) await _quietly(() => _registry.register(token));
    });
  }

  final PushDevice _device;
  final PushRegistry _registry;
  final LocalStore _store;
  late final StreamSubscription<String> _refreshes;
  var _signedIn = false;
  Future<void> _last = Future.value();

  static const _topicsKey = 'push:topics';

  Stream<PushOpen> get opened => _device.opened
      .map(PushOpen.fromData)
      .where((o) => o != null)
      .cast<PushOpen>();

  Set<String> get _savedTopics {
    final v = _store.read(_topicsKey);
    return v is List ? {for (final t in v) '$t'} : <String>{};
  }

  /// Runs [step]; false when it failed (offline, or push not available),
  /// so it is tried again at the next start.
  static Future<bool> _quietly(Future<void> Function() step) async {
    try {
      await step();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Signed in as [user] (with the resident's [barangay]), or signed out
  /// with null. Calls run one after another.
  Future<void> setAccount(AppUser? user, {String? barangay}) =>
      _last = _last.then((_) => _apply(user, barangay));

  Future<void> _apply(AppUser? user, String? barangay) async {
    _signedIn = user != null;
    final wanted = pushTopicsFor(user, barangay: barangay);
    final saved = _savedTopics;
    // Only what FCM confirmed is saved, so a step that failed is retried.
    final now = {...saved};
    for (final t in saved.difference(wanted)) {
      if (await _quietly(() => _device.unsubscribe(t))) now.remove(t);
    }
    for (final t in wanted.difference(saved)) {
      if (await _quietly(() => _device.subscribe(t))) now.add(t);
    }
    await _store.write(_topicsKey, now.toList()..sort());
    if (user == null) {
      await _quietly(_device.deleteToken);
      return;
    }
    final token = await _device.token().catchError((Object _) => null);
    if (token != null) await _quietly(() => _registry.register(token));
  }

  /// Called just before sign-out, while the session still works: the
  /// server stops sending this account's pushes to this phone.
  Future<void> forgetHere() async {
    final token = await _device.token().catchError((Object _) => null);
    if (token != null) await _quietly(() => _registry.forget(token));
  }

  Future<void> dispose() => _refreshes.cancel();
}
