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

class SagipMobileApp extends ConsumerWidget {
  const SagipMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tell the user when a record saved on the phone reaches the server,
    // with its original capture time (NFR1).
    ref.listen(deliveriesProvider, (_, next) {
      final record = next.value;
      final messenger = rootMessengerKey.currentState;
      if (record == null || messenger == null) return;
      final l10n = AppLocalizations.of(messenger.context);
      final time = formatTime(
        record.capturedAt,
        Localizations.localeOf(messenger.context).toString(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deliveredNotice(record.kind, time))),
      );
    });

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: SagipTheme.light(SagipDensity.mobile),
      darkTheme: SagipTheme.dark(SagipDensity.mobile),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
