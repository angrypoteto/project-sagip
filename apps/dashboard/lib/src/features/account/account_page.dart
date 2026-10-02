import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// D11 My account (dispatchers and admins): who is signed in, the theme,
/// a password change, and the keyboard shortcuts (plan 7.4).
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider).value;
    final theme = ref.watch(themeModeProvider);
    if (user == null) return const SizedBox.shrink();

    Widget card(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: SagipSpace.lg),
            ...children,
          ],
        ),
      ),
    );

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: SagipSpace.sm),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label, style: text.bodySmall)),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );

    return PageFrame(
      title: l10n.myAccount,
      subtitle: l10n.accountSubtitle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            card(l10n.accountDetails, [
              row(l10n.colAccount, user.displayName),
              row(l10n.accountEmail, user.email),
              row(l10n.accountRole, l10n.role(user.role)),
            ]),
            const SizedBox(height: SagipSpace.xl),
            card(l10n.displayTitle, [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.themeDark),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.themeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.themeSystem),
                    ),
                  ],
                  selected: {theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      ref.read(themeModeProvider.notifier).set(s.single),
                ),
              ),
            ]),
            const SizedBox(height: SagipSpace.xl),
            card(l10n.soundTitle, [
              SwitchListTile(
                key: const ValueKey('sos-sound'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.soundNewSos),
                subtitle: Text(l10n.soundNewSosNote),
                value: ref.watch(sosSoundProvider),
                onChanged: (on) => ref.read(sosSoundProvider.notifier).set(on),
              ),
            ]),
            const SizedBox(height: SagipSpace.xl),
            card(l10n.passwordTitle, const [_PasswordForm()]),
            const SizedBox(height: SagipSpace.xl),
            card(l10n.shortcutsTitle, [
              row(l10n.shortcutUpDown, l10n.shortcutQueue),
              row(l10n.shortcutEnter, l10n.shortcutOpenFirst),
              row(l10n.shortcutEsc, l10n.shortcutClose),
            ]),
          ],
        ),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  var _tried = false;
  var _busy = false;
  String? _wrongCurrent;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  String? _nextError(AppLocalizations l10n) {
    if (_next.text.length < StaffSessionRepository.minPasswordLength) {
      return l10n.passwordTooShort(StaffSessionRepository.minPasswordLength);
    }
    if (_next.text == _current.text) return l10n.passwordSame;
    return null;
  }

  String? _againError(AppLocalizations l10n) =>
      _again.text == _next.text ? null : l10n.passwordMismatch;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _tried = true;
      _wrongCurrent = null;
    });
    if (_nextError(l10n) != null || _againError(l10n) != null) return;
    setState(() => _busy = true);
    var wrong = false;
    final ok = await runAction(context, () async {
      try {
        await ref
            .read(staffSessionProvider)
            .changePassword(current: _current.text, next: _next.text);
      } on AuthException catch (e) {
        if (e.reason == AuthFailure.wrongCredentials) {
          wrong = true;
          return;
        }
        throw const ActionRejected(ActionRejection.offline);
      }
    }, success: null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wrongCurrent = wrong ? l10n.passwordWrong : null;
    });
    if (ok && !wrong) {
      _current.clear();
      _next.clear();
      _again.clear();
      setState(() => _tried = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(statusSnack(l10n.passwordChanged));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(isOnlineProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('password-current'),
          controller: _current,
          obscureText: true,
          enabled: online && !_busy,
          decoration: InputDecoration(
            labelText: l10n.passwordCurrent,
            errorText: _wrongCurrent,
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        TextField(
          key: const ValueKey('password-new'),
          controller: _next,
          obscureText: true,
          enabled: online && !_busy,
          decoration: InputDecoration(
            labelText: l10n.passwordNew,
            errorText: _tried ? _nextError(l10n) : null,
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        TextField(
          key: const ValueKey('password-again'),
          controller: _again,
          obscureText: true,
          enabled: online && !_busy,
          decoration: InputDecoration(
            labelText: l10n.passwordConfirm,
            errorText: _tried ? _againError(l10n) : null,
          ),
        ),
        if (!online) ...[
          const SizedBox(height: SagipSpace.sm),
          Text(
            l10n.offlineActionsDisabled,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: SagipSpace.lg),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: online && !_busy ? _save : null,
            child: Text(l10n.passwordSave),
          ),
        ),
      ],
    );
  }
}
