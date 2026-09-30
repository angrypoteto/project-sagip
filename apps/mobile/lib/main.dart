import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'src/app.dart';
import 'src/providers.dart';

/// Phase 1 entry point: the app runs on the in-memory mock backend.
/// Supabase and the Hive queue replace [mockOverrides] later; no screen
/// changes.
void main() {
  runApp(
    ProviderScope(
      overrides: mockOverrides(MockMobileBackend(withHistory: true)),
      child: const SagipMobileApp(),
    ),
  );
}
