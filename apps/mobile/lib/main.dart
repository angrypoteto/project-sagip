import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'src/app.dart';
import 'src/device/device_location_service.dart';
import 'src/device/device_permission_service.dart';
import 'src/device/device_sms_sender.dart';
import 'src/device/hive_store.dart';
import 'src/device/reachability_signal_monitor.dart';
import 'src/providers.dart';

/// Set from apps/mobile/.env with `--dart-define-from-file=.env`. Both are
/// public values (the publishable key only allows what Row Level Security
/// permits). Without them the app runs on sample data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// The MDRRMD gateway SIM's number for Tier 2 (an SOS by SMS). Without it
/// an SOS waits on the phone until there is internet.
const _smsGateway = String.fromEnvironment('SMS_GATEWAY_NUMBER');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty
      ? await _live()
      : mockOverrides(MockMobileBackend(withHistory: true));
  runApp(ProviderScope(overrides: overrides, child: const SagipMobileApp()));
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
  final sms = _smsGateway.isEmpty
      ? null
      : SmsTier(
          sender: const DeviceSmsSender(),
          gatewayNumber: _smsGateway,
          available: signal
              .watch()
              .map((s) => s == SignalState.smsOnly)
              .distinct(),
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
  backend.accounts.watchUser().listen((user) {
    // Records made by this account can go now; another account's wait.
    engine.accountChanged();
    if (user?.role == UserRole.responder) {
      sharer.start();
    } else {
      unawaited(sharer.stop());
    }
  });
  return liveOverrides(
    backend: backend,
    store: store,
    engine: engine,
    signal: signal,
    location: location,
    permissions: DevicePermissionService(store),
    recheckSignal: signal.checkNow,
    capabilities: DeviceCapabilities(
      smsTier: sms != null,
      relayTier: false,
      offlineMaps: false,
    ),
  );
}
