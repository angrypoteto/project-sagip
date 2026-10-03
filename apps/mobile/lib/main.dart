import 'dart:async';

import 'package:flutter_map/flutter_map.dart' show NetworkTileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'src/app.dart';
import 'src/device/device_location_service.dart';
import 'src/device/device_permission_service.dart';
import 'src/device/device_sms_sender.dart';
import 'src/device/fcm_push_device.dart';
import 'src/device/hive_store.dart';
import 'src/device/reachability_signal_monitor.dart';
import 'src/device/tile_map_saver.dart';
import 'src/l10n/app_localizations.dart';
import 'src/providers.dart';

/// Set from apps/mobile/.env with `--dart-define-from-file=.env`. Both are
/// public values (the publishable key only allows what Row Level Security
/// permits). Without them the app runs on sample data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// The MDRRMD gateway SIM's number for Tier 2 (an SOS by SMS), fixed at
/// build time. Usually empty: the app then uses the number an administrator
/// set on A3. With neither, an SOS waits on the phone until there is
/// internet.
const _smsGateway = String.fromEnvironment('SMS_GATEWAY_NUMBER');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty
      ? await _live()
      : mockOverrides(
          MockMobileBackend(
            withHistory: true,
            classifier: await loadIncidentClassifier(),
          ),
        );
  runApp(ProviderScope(overrides: overrides, child: const SagipMobileApp()));
}

/// The words on the notification Android shows while a responder's
/// position is shared in the background. Read without a BuildContext:
/// this runs when the account is known, before any screen needs it.
BackgroundNotice _dutyNotice() {
  final device = WidgetsBinding.instance.platformDispatcher.locale;
  final l10n = lookupAppLocalizations(
    AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == device.languageCode,
      orElse: () => AppLocalizations.supportedLocales.first,
    ),
  );
  return (
    title: l10n.dutyNoticeTitle,
    text: l10n.dutyNoticeText,
    channel: l10n.dutyNoticeChannel,
  );
}

/// The real app: Supabase, the phone's encrypted outbox (Hive), GPS,
/// connectivity, and Android permissions.
Future<List<Override>> _live() async {
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  final store = await HiveLocalStore.open();
  final backend = SupabaseMobileBackend(Supabase.instance.client, store: store);
  final signal = ReachabilitySignalMonitor(
    healthUrl: Uri.parse('$_supabaseUrl/auth/v1/health'),
    apiKey: _supabaseKey,
  );
  final location = DeviceLocationService();
  Stream<bool> online() =>
      signal.watch().map((s) => s == SignalState.internet).distinct();
  // The gateway number: from the build, or the one set on A3 (the phone
  // keeps the last copy, so it is there with no data).
  final config = CachedClientConfig(backend.config, store);
  final sms = SmsTier(
    sender: const DeviceSmsSender(),
    gatewayNumber: () =>
        _smsGateway.isNotEmpty ? _smsGateway : config.saved.smsGateway,
    available: signal.watch().map((s) => s == SignalState.smsOnly).distinct(),
  );
  final engine = SyncEngine(
    store: store,
    sender: ServerSender(backend.remote),
    online: online(),
    account: () => backend.accounts.currentUser?.id,
    sms: sms,
  );
  final sharer = ResponderLocationSharer(
    server: backend.remote,
    location: location.watch(),
    online: online(),
  );
  // Push notifications (plan part 7): only when the app was built with the
  // Firebase project's config file.
  final pushDevice = await FcmPushDevice.start();
  final push = pushDevice == null
      ? null
      : PushCoordinator(
          device: pushDevice,
          registry: backend.push,
          store: store,
        );
  if (push != null) backend.accounts.beforeSignOut = push.forgetHere;
  backend.accounts.watchUser().listen((user) {
    if (push != null) unawaited(_syncPush(push, backend, store, user));
    // Records made by this account can go now; another account's wait.
    engine.accountChanged();
    if (user?.role == UserRole.responder) {
      sharer.start();
      // Keep sharing with the screen off or another app open (FR9); the
      // notification stays up for as long as it does.
      unawaited(location.setBackground(_dutyNotice()));
    } else {
      unawaited(sharer.stop());
      unawaited(location.setBackground(null));
    }
  });
  // The map tiles: one cache on the phone for every map, which also keeps
  // the tiles saved for a responder's job (FR13).
  final tileCache = phoneTileCache();
  return liveOverrides(
    maps: TileMapSaver(cache: tileCache),
    tiles: NetworkTileProvider(cachingProvider: tileCache),
    backend: backend,
    store: store,
    engine: engine,
    signal: signal,
    location: location,
    permissions: DevicePermissionService(store),
    config: config,
    recheckSignal: signal.checkNow,
    pushOpens: push?.opened,
  );
}

/// Puts this phone on the signed-in account's push topics. A resident's
/// barangay comes from the server, or from the last copy when offline, so
/// an offline start never drops the barangay's topic.
Future<void> _syncPush(
  PushCoordinator push,
  SupabaseMobileBackend backend,
  LocalStore store,
  AppUser? user,
) async {
  const key = 'push:barangay';
  String? barangay;
  if (user?.role == UserRole.resident) {
    try {
      barangay = await backend.push.homeBarangay();
      await store.write(key, barangay);
    } catch (_) {
      final saved = store.read(key);
      barangay = saved is String ? saved : null;
    }
  }
  await push.setAccount(user, barangay: barangay);
}
