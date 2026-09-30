import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'src/app.dart';
import 'src/providers.dart';

/// Phase 1 entry point: the dashboard runs on the in-memory mock backend.
/// Phase 3 swaps [mockOverrides] for Supabase repositories; no screen changes.
void main() {
  final backend = MockBackend();
  runApp(
    ProviderScope(
      overrides: mockOverrides(backend),
      child: const SagipDashboardApp(),
    ),
  );
}
