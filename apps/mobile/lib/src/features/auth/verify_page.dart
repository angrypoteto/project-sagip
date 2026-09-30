import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// S5 Code: the 6-digit code sent by SMS, a resend timer, and a way back to
/// change the number. The router moves on once the resident is signed in.
class VerifyPage extends ConsumerStatefulWidget {
  const VerifyPage({super.key, required this.phone});

  /// Normalized, for example "+639170004821".
  final String phone;

  @override
  ConsumerState<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends ConsumerState<VerifyPage> {
  static const _resendAfter = 60;
  final _code = TextEditingController();
  Timer? _timer;
  var _left = _resendAfter;
  var _busy = false;
  PhoneAuthFailure? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
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

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(residentAccountRepositoryProvider)
          .verifyCode(phone: widget.phone, code: _code.text);
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _error = null);
    try {
      await ref.read(residentAccountRepositoryProvider).sendCode(widget.phone);
      _startTimer();
      messenger.showSnackBar(SnackBar(content: Text(l10n.codeSent)));
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.reason);
    }
  }

  /// "+639170004821" as "+63 917 000 4821".
  String get _pretty {
    final d = widget.phone.substring(3);
    return '+63 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
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
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(SagipSpace.xl),
        children: [
          Text(l10n.verifyBody(_pretty), style: text.bodyLarge),
          const SizedBox(height: SagipSpace.xl),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: text.headlineMedium!.copyWith(
              letterSpacing: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (v) {
              setState(() {});
              if (v.length == 6 && !offline) _check();
            },
            decoration: InputDecoration(
              labelText: l10n.codeLabel,
              counterText: '',
              errorText: _error == null ? null : l10n.phoneAuthFailure(_error!),
            ),
          ),
          if (demo)
            Text(
              l10n.demoCodeHint(MockMobileBackend.demoCode),
              style: text.bodySmall!.copyWith(color: p.textSecondary),
            ),
          if (offline) ...[
            const SizedBox(height: SagipSpace.md),
            Text(
              l10n.waitingForConnection,
              style: text.bodyMedium!.copyWith(color: p.warning.text),
            ),
          ],
          const SizedBox(height: SagipSpace.xl),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _busy || offline || _code.text.length != 6
                  ? null
                  : _check,
              child: Text(_busy ? l10n.checkingCode : l10n.checkCode),
            ),
          ),
          const SizedBox(height: SagipSpace.md),
          Center(
            child: _left > 0
                ? Text(
                    l10n.resendIn('$mm:$ss'),
                    style: text.bodyMedium!.copyWith(
                      color: p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : TextButton(
                    onPressed: offline ? null : _resend,
                    child: Text(l10n.resendCode),
                  ),
          ),
          Center(
            child: TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.changeNumber),
            ),
          ),
        ],
      ),
    );
  }
}
