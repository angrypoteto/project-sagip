import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// D1 Staff sign in. Redirects happen in the router once the user changes.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: _email.text, password: _password.text);
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
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final isMock = ref.watch(mockBackendProvider) != null;
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SagipSpace.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(SagipSpace.x3),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.brandName, style: text.titleMedium),
                        const SizedBox(height: SagipSpace.xxl),
                        Text(l10n.signInTitle, style: text.headlineSmall),
                        const SizedBox(height: SagipSpace.sm),
                        Text(
                          l10n.signInSubtitle,
                          style: text.bodyMedium!.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: SagipSpace.xxl),
                        TextFormField(
                          controller: _email,
                          decoration: InputDecoration(
                            labelText: l10n.emailLabel,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          validator: required,
                        ),
                        const SizedBox(height: SagipSpace.lg),
                        TextFormField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: l10n.passwordLabel,
                          ),
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          validator: required,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: SagipSpace.lg),
                          Text(
                            _error!,
                            style: text.bodyMedium!.copyWith(
                              color: p.critical.text,
                            ),
                          ),
                        ],
                        const SizedBox(height: SagipSpace.xxl),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy ? l10n.signingIn : l10n.signInButton,
                          ),
                        ),
                        const SizedBox(height: SagipSpace.lg),
                        Text(l10n.forgotPassword, style: text.bodySmall),
                        if (isMock) ...[
                          const SizedBox(height: SagipSpace.lg),
                          Container(
                            padding: const EdgeInsets.all(SagipSpace.md),
                            decoration: BoxDecoration(
                              color: p.panelRaised,
                              borderRadius: BorderRadius.circular(
                                SagipRadius.control,
                              ),
                            ),
                            child: SelectableText(
                              l10n.demoAccountsHint(MockSeed.demoPassword),
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
