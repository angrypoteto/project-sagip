import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/auth_header.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// MDRRMD personnel sign in with the email and password MDRRMD gave them.
class StaffSignInPage extends ConsumerStatefulWidget {
  const StaffSignInPage({super.key});

  @override
  ConsumerState<StaffSignInPage> createState() => _StaffSignInPageState();
}

class _StaffSignInPageState extends ConsumerState<StaffSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  var _busy = false;
  final _sealKey = GlobalKey();

  /// The eye in the password field shows what was typed (2026-11-10).
  var _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final l10n = AppLocalizations.of(context);
    // Readied now: once signed in, the router replaces this page.
    final flight = SealFlightLauncher(context, seal: _sealKey);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: _email.text, password: _password.text);
      flight.play();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = l10n.authFailure(e.reason));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final demo = ref.watch(mockBackendProvider) != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.staffSignInTitle)),
      body: ListView(
        padding: const EdgeInsets.all(SagipSpace.xl),
        children: [
          Center(
            child: AuthHeader(sealKey: _sealKey, busy: _busy),
          ),
          const SizedBox(height: SagipSpace.xl),
          Text(
            l10n.staffSignInBody,
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SagipSpace.xl),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(labelText: l10n.email),
          ),
          const SizedBox(height: SagipSpace.md),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.password],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              labelText: l10n.password,
              suffixIcon: IconButton(
                key: const ValueKey('show-password'),
                tooltip: _showPassword ? l10n.hidePassword : l10n.showPassword,
                icon: Icon(
                  _showPassword
                      ? Symbols.visibility_off_rounded
                      : Symbols.visibility_rounded,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          if (_error != null) ...[
            const SizedBox(height: SagipSpace.md),
            Text(
              _error!,
              style: text.bodyMedium!.copyWith(color: p.critical.text),
            ),
          ],
          const SizedBox(height: SagipSpace.xl),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(_busy ? l10n.signingIn : l10n.signInButton),
            ),
          ),
          if (demo) ...[
            const SizedBox(height: SagipSpace.lg),
            Text(
              l10n.staffDemoHint,
              style: text.bodySmall!.copyWith(color: p.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
