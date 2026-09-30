import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/barangay_picker.dart';
import '../../common/labels.dart';
import '../../common/privacy_notice.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// S4 Register: name, mobile number, barangay, and agreeing to the terms
/// and privacy notice. A code by SMS (S5) finishes it.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Barangay? _barangay;
  var _agreed = false;
  var _busy = false;
  var _tried = false;
  PhoneAuthFailure? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      normalizePhMobile(_phone.text) != null &&
      _barangay != null &&
      _agreed;

  Future<void> _continue() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_valid) return;
    setState(() => _busy = true);
    final phone = normalizePhMobile(_phone.text)!;
    try {
      await ref
          .read(residentAccountRepositoryProvider)
          .register(fullName: _name.text, phone: phone, barangay: _barangay!);
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
    final phoneInvalid = _tried && normalizePhMobile(_phone.text) == null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerTitle)),
      body: ListView(
        padding: const EdgeInsets.all(SagipSpace.xl),
        children: [
          Text(
            l10n.registerBody,
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: SagipSpace.xl),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.fullName,
              errorText: _tried && _name.text.trim().isEmpty
                  ? l10n.nameRequired
                  : null,
            ),
          ),
          const SizedBox(height: SagipSpace.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
            ],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.mobileNumber,
              hintText: l10n.mobileNumberHint,
              prefixText: '+63 ',
              errorText: phoneInvalid
                  ? l10n.phoneInvalid
                  : (_error == null ? null : l10n.phoneAuthFailure(_error!)),
            ),
          ),
          if (_error == PhoneAuthFailure.numberTaken)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go(Routes.signIn),
                child: Text(l10n.residentSignInTitle),
              ),
            ),
          const SizedBox(height: SagipSpace.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.location_city_rounded),
            title: Text(_barangay?.name ?? l10n.barangay),
            subtitle: Text(
              _barangay?.district ??
                  (_tried && _barangay == null
                      ? l10n.barangayRequired
                      : l10n.chooseBarangay),
              style: _tried && _barangay == null
                  ? text.bodySmall!.copyWith(color: p.critical.text)
                  : null,
            ),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () async {
              final picked = await showBarangayPicker(context);
              if (picked != null) setState(() => _barangay = picked);
            },
          ),
          const SizedBox(height: SagipSpace.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: Text(l10n.agreeTerms),
            subtitle: _tried && !_agreed
                ? Text(
                    l10n.termsRequired,
                    style: text.bodySmall!.copyWith(color: p.critical.text),
                  )
                : null,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showPrivacyNotice(context),
              child: Text(l10n.readPrivacy),
            ),
          ),
          const SizedBox(height: SagipSpace.xl),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _busy ? null : _continue,
              child: Text(_busy ? l10n.creatingAccount : l10n.continueButton),
            ),
          ),
        ],
      ),
    );
  }
}
