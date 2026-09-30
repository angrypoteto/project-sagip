import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// G2: the session ended without signing out. Sign in again returns to the
/// page the person was on ([from]).
class SessionExpiredPage extends ConsumerWidget {
  const SessionExpiredPage({super.key, this.from});

  final String? from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final back = from != null && from!.startsWith('/') ? from! : Routes.board;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(SagipSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.lock_clock_rounded,
                    size: 32,
                    color: p.info.text,
                  ),
                  const SizedBox(height: SagipSpace.lg),
                  Text(l10n.sessionExpiredTitle, style: text.headlineSmall),
                  const SizedBox(height: SagipSpace.sm),
                  Text(l10n.sessionExpiredMessage, style: text.bodyMedium),
                  const SizedBox(height: SagipSpace.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        ref.read(sessionExpiredProvider.notifier).set(false);
                        context.go(
                          Uri(
                            path: Routes.signIn,
                            queryParameters: {'from': back},
                          ).toString(),
                        );
                      },
                      child: Text(l10n.signInAgain),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
