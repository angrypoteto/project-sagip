import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'web_router.dart';

/// The resident web form (W1 to W3): crowd reports from a browser, for
/// residents who have not installed the app yet (FR15). It follows the
/// device's light or dark setting and uses the phone-sized type, because
/// most residents open it on a phone.
class SagipWebFormApp extends ConsumerWidget {
  const SagipWebFormApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).webAppTitle,
      debugShowCheckedModeBanner: false,
      theme: SagipTheme.light(SagipDensity.mobile),
      darkTheme: SagipTheme.dark(SagipDensity.mobile),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(webRouterProvider),
      // flutter_map still uses package:flutter/material.dart; the bridge lets
      // its widgets read our material_ui theme. Remove once flutter_map
      // migrates to material_ui.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
    );
  }
}
