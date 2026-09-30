import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/brand.dart';
import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// S3 Sign in: residents use their mobile number and a code by SMS;
/// MDRRMD personnel have their own form. On sample data a Demo section
/// signs straight in.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _phone = TextEditingController();
  PhoneAuthFailure? _error;
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = normalizePhMobile(_phone.text);
      if (phone == null) {
        throw const PhoneAuthException(PhoneAuthFailure.invalidNumber);
      }
      await ref.read(residentAccountRepositoryProvider).sendCode(phone);
      if (mounted) context.push(Routes.verifyFor(phone));
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final offline =
        (ref.watch(signalProvider).value ?? SignalState.internet) !=
        SignalState.internet;
    final demo = ref.watch(mockBackendProvider) != null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SagipSpace.xl),
          children: [
            const SizedBox(height: SagipSpace.lg),
            const Align(
              alignment: Alignment.centerLeft,
              child: SagipMark(size: 48),
            ),
            const SizedBox(height: SagipSpace.xl),
            Text(l10n.residentSignInTitle, style: text.headlineMedium),
            const SizedBox(height: SagipSpace.sm),
            Text(
              l10n.residentSignInBody,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            if (offline) ...[
              const SizedBox(height: SagipSpace.lg),
              _Notice(text: l10n.offlineSignIn),
            ],
            const SizedBox(height: SagipSpace.xl),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
              ],
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: l10n.mobileNumber,
                hintText: l10n.mobileNumberHint,
                prefixText: '+63 ',
                errorText: _error == null
                    ? null
                    : l10n.phoneAuthFailure(_error!),
              ),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: SagipSpace.lg),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy || offline ? null : _sendCode,
                child: Text(_busy ? l10n.sendingCode : l10n.sendCode),
              ),
            ),
            const SizedBox(height: SagipSpace.sm),
            TextButton(
              onPressed: () => context.push(Routes.register),
              child: Text(l10n.createAccountPrompt),
            ),
            TextButton(
              onPressed: () => context.push(Routes.staffSignIn),
              child: Text(l10n.staffSignInLink),
            ),
            const SizedBox(height: SagipSpace.xl),
            const HotlineCard(),
            if (demo) ...[
              const SizedBox(height: SagipSpace.x3),
              const _DemoAccounts(),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.warning.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          children: [
            Icon(Symbols.cloud_off_rounded, color: p.warning.text),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: p.warning.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sample-data shortcuts: sign in as the demo resident or responder.
class _DemoAccounts extends ConsumerStatefulWidget {
  const _DemoAccounts();

  @override
  ConsumerState<_DemoAccounts> createState() => _DemoAccountsState();
}

class _DemoAccountsState extends ConsumerState<_DemoAccounts> {
  String? _error;

  Future<void> _signIn(AppUser account) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: account.email, password: MockSeed.demoPassword);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = l10n.authFailure(e.reason));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.demoAccounts, style: text.titleSmall),
        Text(
          l10n.demoSignInBody,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.sm),
        OutlinedButton(
          onPressed: () => _signIn(MockMobileBackend.resident),
          child: Text(l10n.continueAsResident),
        ),
        const SizedBox(height: SagipSpace.sm),
        OutlinedButton(
          onPressed: () => _signIn(MockMobileBackend.responder),
          child: Text(l10n.continueAsResponder),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: SagipSpace.sm),
            child: Text(
              _error!,
              style: text.bodySmall!.copyWith(color: p.critical.text),
            ),
          ),
      ],
    );
  }
}
