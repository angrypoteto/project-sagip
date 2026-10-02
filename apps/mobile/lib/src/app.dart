import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'common/labels.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

/// Shows app-wide notices, such as "Your SOS from 3:42 PM was delivered",
/// on whatever screen is open.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// How recent a rescue confirmation must be to be announced on screen.
const rescueNoticeWindow = Duration(minutes: 5);

class SagipMobileApp extends ConsumerWidget {
  const SagipMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tell the user when a record that waited on the phone reaches the
    // server, with its original capture time (NFR1). Records sent at once
    // already show their status on screen.
    ref.listen(deliveriesProvider, (_, next) {
      final record = next.value;
      final messenger = rootMessengerKey.currentState;
      if (record == null || !record.waitedOffline || messenger == null) {
        return;
      }
      final l10n = AppLocalizations.of(messenger.context);
      final time = formatTime(
        record.capturedAt,
        Localizations.localeOf(messenger.context).toString(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deliveredNotice(record.kind, time))),
      );
    });

    // A rescue confirmation that just arrived (FR6): said on whatever
    // screen is open. Older ones wait on the Alerts tab.
    ref.listen(alertFeedProvider, (previous, next) {
      final before = previous?.value;
      final feed = next.value;
      final messenger = rootMessengerKey.currentState;
      if (before == null || feed == null || messenger == null) return;
      final known = {for (final c in before.confirmations) c.id};
      final now = ref.read(clockProvider).value ?? DateTime.now();
      for (final c in feed.confirmations.reversed) {
        final fresh =
            !c.read &&
            !known.contains(c.id) &&
            now.difference(c.at) < rescueNoticeWindow;
        if (!fresh) continue;
        final l10n = AppLocalizations.of(messenger.context);
        messenger.showSnackBar(SnackBar(content: Text(l10n.rescueBody(c))));
      }
    });

    // Fetched when the app starts and kept for as long as it runs: the
    // hotline and the SMS gateway number an administrator set on A3.
    ref.listen(clientConfigProvider, (_, _) {});

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: SagipTheme.light(SagipDensity.mobile),
      darkTheme: SagipTheme.dark(SagipDensity.mobile),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      // flutter_map still uses package:flutter/material.dart; the bridge lets
      // its widgets read our material_ui theme. Remove once flutter_map
      // migrates to material_ui.
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
    );
  }
}
