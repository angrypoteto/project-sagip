import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'web_barangay_dialog.dart';
import 'web_frame.dart';
import 'web_providers.dart';

enum _Step { number, register, code }

/// W1 Sign in: the resident's mobile number and a code by SMS, the same as
/// the app (plan 7.2). The number stays in this page's memory and is never
/// put in the address bar. Once the code is right the router opens W2.
class WebSignInPage extends ConsumerStatefulWidget {
  const WebSignInPage({super.key});

  @override
  ConsumerState<WebSignInPage> createState() => _WebSignInPageState();
}

class _WebSignInPageState extends ConsumerState<WebSignInPage> {
  static const _resendAfter = 60;

  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  var _step = _Step.number;
  var _busy = false;
  PhoneAuthFailure? _error;

  // Register form.
  Barangay? _barangay;
  var _agreed = false;
  var _checked = false;

  /// The number the code was sent to, for example "+639170004821".
  String? _sentTo;
  Timer? _timer;
  var _left = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _resendAfter);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  void _go(_Step step, {PhoneAuthFailure? error}) {
    _timer?.cancel();
    setState(() {
      _step = step;
      _error = error;
      _checked = false;
      _code.clear();
    });
  }

  /// Runs one sign-in step and shows why it failed.
  Future<bool> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
      return true;
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } on Object {
      if (mounted) setState(() => _error = PhoneAuthFailure.unavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _sendCode() async {
    final phone = normalizePhMobile(_phone.text);
    final sent = await _run(() async {
      if (phone == null) {
        throw const PhoneAuthException(PhoneAuthFailure.invalidNumber);
      }
      await ref.read(webAccountsProvider).sendCode(phone);
    });
    if (!sent || !mounted) return;
    _sentTo = phone;
    _go(_Step.code);
    _startTimer();
  }

  Future<void> _register() async {
    setState(() => _checked = true);
    final phone = normalizePhMobile(_phone.text);
    final barangay = _barangay;
    if (_name.text.trim().isEmpty || barangay == null || !_agreed) return;
    final sent = await _run(() async {
      if (phone == null) {
        throw const PhoneAuthException(PhoneAuthFailure.invalidNumber);
      }
      await ref
          .read(webAccountsProvider)
          .register(fullName: _name.text, phone: phone, barangay: barangay);
    });
    if (!sent || !mounted) return;
    _sentTo = phone;
    _go(_Step.code);
    _startTimer();
  }

  Future<void> _checkCode() async {
    final phone = _sentTo;
    if (phone == null || _code.text.length != 6 || _busy) return;
    final allowRegistration = ref.read(webConfigProvider).allowRegistration;
    await _run(
      () => ref
          .read(webAccountsProvider)
          .verifyCode(phone: phone, code: _code.text),
    );
    // The code was right but the number has no account: offer to make one.
    if (mounted &&
        _error == PhoneAuthFailure.notRegistered &&
        allowRegistration) {
      _go(_Step.register, error: PhoneAuthFailure.notRegistered);
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final phone = _sentTo;
    if (phone == null) return;
    final sent = await _run(
      () => ref.read(webAccountsProvider).sendCode(phone),
    );
    if (!sent || !mounted) return;
    _startTimer();
    messenger.showSnackBar(SnackBar(content: Text(l10n.webCodeSent)));
  }

  String _failure(
    AppLocalizations l10n,
    PhoneAuthFailure f,
    bool canRegister,
  ) => switch (f) {
    PhoneAuthFailure.invalidNumber => l10n.webPhoneInvalid,
    PhoneAuthFailure.notRegistered =>
      canRegister ? l10n.webPhoneNotRegistered : l10n.webPhoneNotRegisteredApp,
    PhoneAuthFailure.numberTaken => l10n.webPhoneTaken,
    PhoneAuthFailure.wrongCode => l10n.webCodeWrong,
    PhoneAuthFailure.tooManyAttempts => l10n.webTooManyAttempts,
    PhoneAuthFailure.offline => l10n.webOffline,
    PhoneAuthFailure.unavailable => l10n.webSmsUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(webConfigProvider);
    final online = ref.watch(webIsOnlineProvider);
    final error = _error == null
        ? null
        : _failure(l10n, _error!, config.allowRegistration);
    return WebFrame(
      children: [
        ...switch (_step) {
          _Step.number => _numberStep(l10n, config, online, error),
          _Step.register => _registerStep(l10n, online, error),
          _Step.code => _codeStep(l10n, online, error),
        },
        const SizedBox(height: SagipSpace.x3),
        const SosNotice(),
      ],
    );
  }

  Widget _phoneField(AppLocalizations l10n, String? error, VoidCallback go) =>
      TextField(
        key: const ValueKey('web-phone'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
        ],
        decoration: InputDecoration(
          labelText: l10n.webMobileNumber,
          hintText: l10n.webMobileNumberHint,
          prefixText: '+63 ',
          errorText: error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => go(),
      );

  List<Widget> _numberStep(
    AppLocalizations l10n,
    WebFormConfig config,
    bool online,
    String? error,
  ) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final demo = ref.watch(webMockBackendProvider) != null;
    return [
      Text(l10n.webSignInTitle, style: text.headlineSmall),
      const SizedBox(height: SagipSpace.sm),
      Text(
        l10n.webSignInBody,
        style: text.bodyMedium!.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: SagipSpace.xxl),
      _phoneField(l10n, error, _sendCode),
      const SizedBox(height: SagipSpace.lg),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: _busy || !online ? null : _sendCode,
          child: Text(_busy ? l10n.webSendingCode : l10n.webSendCode),
        ),
      ),
      if (config.allowRegistration) ...[
        const SizedBox(height: SagipSpace.sm),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.register),
          child: Text(l10n.webCreateAccount),
        ),
      ],
      if (demo) ...[
        const SizedBox(height: SagipSpace.lg),
        Text(
          l10n.webDemoHint(MockMobileBackend.demoCode),
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
      ],
    ];
  }

  List<Widget> _registerStep(
    AppLocalizations l10n,
    bool online,
    String? error,
  ) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final barangay = _barangay;
    // "No account yet" explains why the resident landed here; the other
    // failures belong to the number.
    final arrived = _error == PhoneAuthFailure.notRegistered;
    return [
      Text(l10n.webRegisterTitle, style: text.headlineSmall),
      const SizedBox(height: SagipSpace.sm),
      Text(
        l10n.webRegisterBody,
        style: text.bodyMedium!.copyWith(color: p.textSecondary),
      ),
      if (arrived) ...[
        const SizedBox(height: SagipSpace.lg),
        WebMessage(text: error!, tone: p.info, icon: Symbols.info_rounded),
      ],
      const SizedBox(height: SagipSpace.xxl),
      TextField(
        key: const ValueKey('web-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        decoration: InputDecoration(
          labelText: l10n.webFullName,
          errorText: _checked && _name.text.trim().isEmpty
              ? l10n.webFullNameError
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: SagipSpace.lg),
      _phoneField(l10n, arrived ? null : error, _register),
      const SizedBox(height: SagipSpace.lg),
      InkWell(
        key: const ValueKey('web-barangay'),
        borderRadius: BorderRadius.circular(SagipRadius.control),
        onTap: () async {
          final picked = await showWebBarangayDialog(context);
          if (picked != null && mounted) setState(() => _barangay = picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.webBarangay,
            suffixIcon: const Icon(Symbols.expand_more_rounded),
            errorText: _checked && barangay == null
                ? l10n.webBarangayError
                : null,
          ),
          child: Text(
            barangay == null
                ? l10n.webChooseBarangay
                : l10n.webPlace(barangay.name, barangay.district),
            style: text.bodyLarge!.copyWith(
              color: barangay == null ? p.textSecondary : null,
            ),
          ),
        ),
      ),
      const SizedBox(height: SagipSpace.md),
      CheckboxListTile(
        key: const ValueKey('web-terms'),
        value: _agreed,
        onChanged: (v) => setState(() => _agreed = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.webAgreeTerms, style: text.bodyMedium),
        subtitle: _checked && !_agreed
            ? Text(
                l10n.webTermsError,
                style: text.bodySmall!.copyWith(color: p.critical.text),
              )
            : null,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => showWebPrivacyNotice(context),
          child: Text(l10n.webReadPrivacy),
        ),
      ),
      const SizedBox(height: SagipSpace.lg),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: _busy || !online ? null : _register,
          child: Text(_busy ? l10n.webSendingCode : l10n.webSendCode),
        ),
      ),
      const SizedBox(height: SagipSpace.sm),
      TextButton(
        onPressed: _busy ? null : () => _go(_Step.number),
        child: Text(l10n.webHaveAccount),
      ),
    ];
  }

  /// "+639170004821" as "+63 917 000 4821".
  String get _pretty {
    final d = _sentTo!.substring(3);
    return '+63 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }

  List<Widget> _codeStep(AppLocalizations l10n, bool online, String? error) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final demo = ref.watch(webMockBackendProvider) != null;
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');
    return [
      Text(l10n.webCodeTitle, style: text.headlineSmall),
      const SizedBox(height: SagipSpace.sm),
      Text(
        l10n.webCodeBody(_pretty),
        style: text.bodyMedium!.copyWith(color: p.textSecondary),
      ),
      const SizedBox(height: SagipSpace.xxl),
      TextField(
        key: const ValueKey('web-code'),
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: text.headlineSmall!.copyWith(
          letterSpacing: 8,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          labelText: l10n.webCodeLabel,
          counterText: '',
          errorText: error,
          errorMaxLines: 3,
        ),
        onChanged: (v) {
          setState(() {});
          if (v.length == 6 && online) _checkCode();
        },
      ),
      const SizedBox(height: SagipSpace.lg),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: _busy || !online || _code.text.length != 6
              ? null
              : _checkCode,
          child: Text(_busy ? l10n.webCheckingCode : l10n.webCheckCode),
        ),
      ),
      const SizedBox(height: SagipSpace.md),
      Center(
        child: _left > 0
            ? Text(
                l10n.webResendIn('$mm:$ss'),
                style: text.bodyMedium!.copyWith(
                  color: p.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              )
            : TextButton(
                onPressed: _busy || !online ? null : _resend,
                child: Text(l10n.webResendCode),
              ),
      ),
      Center(
        child: TextButton(
          onPressed: _busy ? null : () => _go(_Step.number),
          child: Text(l10n.webChangeNumber),
        ),
      ),
      if (demo)
        Text(
          l10n.webDemoHint(MockMobileBackend.demoCode),
          textAlign: TextAlign.center,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
    ];
  }
}

/// The privacy notice a resident agrees to when creating an account
/// (RA 10173). The text is a draft until MDRRMD's data protection officer
/// reviews it, like the app's.
Future<void> showWebPrivacyNotice(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final text = Theme.of(context).textTheme;
  final sections = [
    (l10n.webPrivacyCollectTitle, l10n.webPrivacyCollectBody),
    (l10n.webPrivacyWhyTitle, l10n.webPrivacyWhyBody),
    (l10n.webPrivacyWhoTitle, l10n.webPrivacyWhoBody),
    (l10n.webPrivacyKeepTitle, l10n.webPrivacyKeepBody),
    (l10n.webPrivacyRightsTitle, l10n.webPrivacyRightsBody),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.webPrivacyTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, body) in sections) ...[
                Text(title, style: text.titleSmall),
                const SizedBox(height: SagipSpace.xs),
                Text(body, style: text.bodyMedium),
                const SizedBox(height: SagipSpace.lg),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
