import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Phase 1 sign-in: pick a demo account. The real S3 (mobile number and a
/// code by SMS for residents, credentials for personnel) comes later.
class DemoSignInPage extends ConsumerStatefulWidget {
  const DemoSignInPage({super.key});

  @override
  ConsumerState<DemoSignInPage> createState() => _DemoSignInPageState();
}

class _DemoSignInPageState extends ConsumerState<DemoSignInPage> {
  AppUser? _busy;
  String? _error;

  Future<void> _signIn(AppUser account) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = account;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: account.email, password: MockSeed.demoPassword);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = l10n.authFailure(e.reason));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SagipSpace.xl),
          children: [
            const SizedBox(height: SagipSpace.x4),
            Text(l10n.appTitle, style: text.titleMedium),
            const SizedBox(height: SagipSpace.x3),
            Text(l10n.signInTitle, style: text.headlineMedium),
            const SizedBox(height: SagipSpace.sm),
            Text(
              l10n.demoSignInBody,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: SagipSpace.x3),
            _AccountButton(
              icon: Symbols.home_rounded,
              title: l10n.continueAsResident,
              detail: l10n.continueAsResidentDetail,
              busy: _busy == MockMobileBackend.resident,
              busyLabel: l10n.signingIn,
              onPressed: _busy == null
                  ? () => _signIn(MockMobileBackend.resident)
                  : null,
            ),
            const SizedBox(height: SagipSpace.md),
            _AccountButton(
              icon: Symbols.medical_services_rounded,
              title: l10n.continueAsResponder,
              detail: l10n.continueAsResponderDetail,
              busy: _busy == MockMobileBackend.responder,
              busyLabel: l10n.signingIn,
              onPressed: _busy == null
                  ? () => _signIn(MockMobileBackend.responder)
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: SagipSpace.lg),
              Text(
                _error!,
                style: text.bodyMedium!.copyWith(color: p.critical.text),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.icon,
    required this.title,
    required this.detail,
    required this.busy,
    required this.busyLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool busy;
  final String busyLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(SagipSpace.lg),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: SagipSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(busy ? busyLabel : title, style: text.titleMedium),
                const SizedBox(height: SagipSpace.xs),
                Text(
                  detail,
                  style: text.bodySmall!.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
