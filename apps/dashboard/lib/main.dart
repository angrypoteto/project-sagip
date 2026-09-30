import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'src/app.dart';
import 'src/providers.dart';

/// Set from apps/dashboard/.env with `--dart-define-from-file=.env`. Both
/// are public values (the publishable key only allows what Row Level
/// Security permits). Without them the dashboard runs on mock data.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final List<Override> overrides;
  if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
    overrides = supabaseOverrides(SupabaseBackend(Supabase.instance.client));
  } else {
    overrides = mockOverrides(MockBackend());
  }

  runApp(ProviderScope(overrides: overrides, child: const SagipDashboardApp()));
}
