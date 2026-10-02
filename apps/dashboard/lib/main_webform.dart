import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, SharedPreferencesLocalStorage, Supabase;

import 'src/webform/web_app.dart';
import 'src/webform/web_providers.dart';

// The resident web form (W1 to W3), a second entry point of this package:
//
//   flutter run -d chrome -t lib/main_webform.dart
//   flutter build web -t lib/main_webform.dart -o build/webform
//
// It is deployed to its own address, apart from the command dashboard.

/// The same public values as the dashboard (apps/dashboard/.env). Without
/// them the form runs on sample data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final List<Override> overrides;
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseKey,
      // Its own saved session: on a shared address the form never picks up
      // (or signs out) a dispatcher's dashboard session.
      authOptions: FlutterAuthClientOptions(
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: 'sagip-webform-auth',
        ),
      ),
    );
    overrides = webSupabaseOverrides(
      SupabaseWebFormBackend(Supabase.instance.client),
    );
  } else {
    overrides = webMockOverrides(
      MockMobileBackend(
        withHistory: true,
        autoOffers: false,
        classifier: await loadIncidentClassifier(),
      ),
    );
  }

  runApp(ProviderScope(overrides: overrides, child: const SagipWebFormApp()));
}
