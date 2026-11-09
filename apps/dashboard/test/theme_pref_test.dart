import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_dashboard/src/providers.dart';
import 'package:sagip_dashboard/src/webform/browser/browser_stub.dart';

void main() {
  test('the theme choice survives a reload (2026-11-10)', () {
    final store = MemoryDraftStore();
    ProviderContainer page() => ProviderContainer(
      overrides: [uiPrefsStoreProvider.overrideWithValue(store)],
    );

    final first = page();
    expect(first.read(themeModeProvider), ThemeMode.dark);
    first.read(themeModeProvider.notifier).set(ThemeMode.light);
    first.dispose();

    // A reload: a new container reading the same browser store.
    final second = page();
    expect(second.read(themeModeProvider), ThemeMode.light);
    second.read(themeModeProvider.notifier).toggle();
    second.dispose();

    expect(page().read(themeModeProvider), ThemeMode.dark);
  });
}
