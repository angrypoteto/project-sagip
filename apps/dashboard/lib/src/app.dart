import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

class SagipDashboardApp extends ConsumerWidget {
  const SagipDashboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: SagipTheme.light(SagipDensity.dashboard),
      darkTheme: SagipTheme.dark(SagipDensity.dashboard),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      // flutter_map still uses package:flutter/material.dart; the bridge lets
      // its widgets read our material_ui theme (material_ui migration guide).
      // Remove once flutter_map migrates to material_ui.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
    );
  }
}
