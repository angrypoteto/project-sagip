import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

enum _Tab { staff, responders, residents }

/// A1 Accounts (admin): staff logins (create, edit, reset password,
/// deactivate) and resident accounts (suspend for abuse). The database
/// checks every change and writes it to the audit log (FR10, FR11).
class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  var _tab = _Tab.staff;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(isOnlineProvider);
    return PageFrame(
      title: l10n.navAccounts,
      subtitle: l10n.accountsSubtitle,
      headerTrailing: FilledButton.icon(
        onPressed: online ? () => _createAccount(context, ref) : null,
        icon: const Icon(Symbols.person_add_rounded),
        label: Text(l10n.createAccount),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_Tab>(
              segments: [
                ButtonSegment(value: _Tab.staff, label: Text(l10n.tabStaff)),
                ButtonSegment(
                  value: _Tab.responders,
                  label: Text(l10n.tabResponders),
                ),
                ButtonSegment(
                  value: _Tab.residents,
                  label: Text(l10n.tabResidents),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.single),
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
          switch (_tab) {
            _Tab.staff => _StaffTable(responders: false, online: online),
            _Tab.responders => _StaffTable(responders: true, online: online),
            _Tab.residents => _ResidentTable(online: online),
          },
        ],
      ),
    );
  }
}

class _StaffTable extends ConsumerWidget {
  const _StaffTable({required this.responders, required this.online});

  final bool responders;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final me = ref.watch(currentUserProvider).value?.id;
    final units = ref.watch(allUnitsProvider).value ?? const <ResponseUnit>[];
    String unitName(String? id) => id == null
        ? l10n.noUnit
        : (units.where((u) => u.id == id).firstOrNull?.callSign ?? id);

    return AsyncBody(
      value: ref.watch(staffAccountsProvider),
      isEmpty: (list) =>
          !list.any((s) => (s.role == UserRole.responder) == responders),
      empty: EmptyState(icon: Symbols.group_rounded, title: l10n.accountsEmpty),
      builder: (all) {
        final rows = [
          for (final s in all)
            if ((s.role == UserRole.responder) == responders) s,
        ];
        return TableCard(
          table: DataTable(
            columnSpacing: SagipSpace.xl,
            columns: [
              DataColumn(label: Text(l10n.colName)),
              DataColumn(label: Text(l10n.accountEmail)),
              DataColumn(label: Text(responders ? l10n.colUnit : l10n.colRole)),
              DataColumn(label: Text(l10n.colStatus)),
              const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final s in rows)
                DataRow(
                  cells: [
                    DataCell(Text(s.displayName)),
                    DataCell(Text(s.email)),
                    DataCell(
                      Text(responders ? unitName(s.unitId) : l10n.role(s.role)),
                    ),
                    DataCell(
                      SagipChip(
                        label: s.active
                            ? l10n.statusActive
                            : l10n.statusDeactivated,
                        tone: s.active ? p.success : p.neutral,
                      ),
                    ),
                    DataCell(
                      s.id == me
                          ? Tooltip(
                              message: l10n.ownAccountHint,
                              child: Icon(
                                Symbols.person_rounded,
                                color: p.textSecondary,
                              ),
                            )
                          : _StaffActions(account: s, online: online),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StaffActions extends ConsumerWidget {
  const _StaffActions({required this.account, required this.online});

  final StaffAccount account;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(accountRepositoryProvider);
    final s = account;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('edit-${s.id}'),
          tooltip: l10n.editAccount,
          onPressed: online ? () => _editAccount(context, ref, s) : null,
          icon: const Icon(Symbols.edit_rounded),
        ),
        IconButton(
          key: ValueKey('reset-${s.id}'),
          tooltip: l10n.resetPassword,
          onPressed: online
              ? () async {
                  final ok = await _confirm(
                    context,
                    l10n.resetTitle(s.displayName),
                    l10n.resetBody,
                    l10n.resetPassword,
                  );
                  if (!ok || !context.mounted) return;
                  String? pw;
                  final done = await runAction(context, () async {
                    pw = await repo.resetPassword(s.id);
                  });
                  if (done && pw != null && context.mounted) {
                    await _showTemporaryPassword(context, s.displayName, pw!);
                  }
                }
              : null,
          icon: const Icon(Symbols.key_rounded),
        ),
        IconButton(
          key: ValueKey('active-${s.id}'),
          tooltip: s.active ? l10n.deactivate : l10n.reactivate,
          onPressed: !online
              ? null
              : () async {
                  if (s.active) {
                    final ok = await _confirm(
                      context,
                      l10n.deactivateTitle(s.displayName),
                      l10n.deactivateBody,
                      l10n.deactivate,
                    );
                    if (!ok || !context.mounted) return;
                  }
                  await runAction(
                    context,
                    () => repo.setStaffActive(s.id, active: !s.active),
                    success: s.active
                        ? l10n.accountDeactivatedSnack(s.displayName)
                        : l10n.accountReactivatedSnack(s.displayName),
                  );
                },
          icon: Icon(
            s.active
                ? Symbols.person_off_rounded
                : Symbols.person_check_rounded,
          ),
        ),
      ],
    );
  }
}

class _ResidentTable extends ConsumerWidget {
  const _ResidentTable({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final repo = ref.read(accountRepositoryProvider);
    return AsyncBody(
      value: ref.watch(residentAccountsProvider),
      isEmpty: (list) => list.isEmpty,
      empty: EmptyState(
        icon: Symbols.groups_rounded,
        title: l10n.residentsEmpty,
      ),
      builder: (residents) => TableCard(
        table: DataTable(
          columnSpacing: SagipSpace.xl,
          columns: [
            DataColumn(label: Text(l10n.colName)),
            DataColumn(label: Text(l10n.colBarangay)),
            DataColumn(label: Text(l10n.colNumber)),
            DataColumn(label: Text(l10n.colStatus)),
            const DataColumn(label: SizedBox.shrink()),
          ],
          rows: [
            for (final r in residents)
              DataRow(
                cells: [
                  DataCell(Text(r.fullName)),
                  DataCell(Text(r.place)),
                  DataCell(Text(r.maskedContact)),
                  DataCell(
                    SagipChip(
                      label: r.suspended
                          ? l10n.statusSuspended
                          : l10n.statusActive,
                      tone: r.suspended ? p.warning : p.success,
                    ),
                  ),
                  DataCell(
                    TextButton(
                      key: ValueKey('suspend-${r.id}'),
                      onPressed: !online
                          ? null
                          : () async {
                              if (!r.suspended) {
                                final ok = await _confirm(
                                  context,
                                  l10n.suspendTitle(r.fullName),
                                  l10n.suspendBody,
                                  l10n.suspend,
                                );
                                if (!ok || !context.mounted) return;
                              }
                              await runAction(
                                context,
                                () => repo.setResidentSuspended(
                                  r.id,
                                  suspended: !r.suspended,
                                ),
                                success: r.suspended
                                    ? l10n.residentRestoredSnack(r.fullName)
                                    : l10n.residentSuspendedSnack(r.fullName),
                              );
                            },
                      child: Text(
                        r.suspended ? l10n.liftSuspension : l10n.suspend,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String action,
) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 420, child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _showTemporaryPassword(
  BuildContext context,
  String name,
  String password,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.tempPasswordTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tempPasswordBody(name)),
            const SizedBox(height: SagipSpace.lg),
            SelectableText(
              password,
              key: const ValueKey('temporary-password'),
              style: text.headlineSmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: password));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(statusSnack(l10n.copied));
            }
          },
          icon: const Icon(Symbols.content_copy_rounded),
          label: Text(l10n.copy),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.done),
        ),
      ],
    );
  },
);

Future<void> _createAccount(BuildContext context, WidgetRef ref) async {
  final made = await showDialog<({String name, String password})>(
    context: context,
    builder: (context) => _AccountDialog(ref: ref),
  );
  if (made != null && context.mounted) {
    await _showTemporaryPassword(context, made.name, made.password);
  }
}

Future<void> _editAccount(
  BuildContext context,
  WidgetRef ref,
  StaffAccount account,
) => showDialog<void>(
  context: context,
  builder: (context) => _AccountDialog(ref: ref, account: account),
);

/// Create ([account] null) or edit an account. Pops with the name and the
/// temporary password after creating.
class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.ref, this.account});

  final WidgetRef ref;
  final StaffAccount? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _email = TextEditingController(text: widget.account?.email);
  late final _name = TextEditingController(text: widget.account?.displayName);
  late UserRole _role = widget.account?.role ?? UserRole.dispatcher;
  String? _unitId;
  var _tried = false;
  var _busy = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _creating => widget.account == null;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _tried = true);
    final emailOk = !_creating || _emailPattern.hasMatch(_email.text.trim());
    if (!emailOk || _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final repo = widget.ref.read(accountRepositoryProvider);
    ({String id, String temporaryPassword})? made;
    final ok = await runAction(context, () async {
      if (_creating) {
        made = await repo.createStaff(
          email: _email.text.trim(),
          displayName: _name.text.trim(),
          role: _role,
          unitId: _role == UserRole.responder ? _unitId : null,
        );
      } else {
        await repo.updateStaff(
          widget.account!.id,
          displayName: _name.text.trim(),
          role: _role,
        );
      }
    }, success: _creating ? null : l10n.accountSaved(_name.text.trim()));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    Navigator.pop(
      context,
      made == null
          ? null
          : (name: _name.text.trim(), password: made!.temporaryPassword),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final units = [
      for (final u
          in widget.ref.watch(allUnitsProvider).value ?? const <ResponseUnit>[])
        if (!u.retired) u,
    ]..sort((a, b) => a.callSign.compareTo(b.callSign));
    return AlertDialog(
      title: Text(_creating ? l10n.createAccount : l10n.editAccount),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('account-email'),
              controller: _email,
              enabled: _creating,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.fieldEmail,
                errorText:
                    _tried &&
                        _creating &&
                        !_emailPattern.hasMatch(_email.text.trim())
                    ? l10n.fieldEmailError
                    : null,
              ),
            ),
            const SizedBox(height: SagipSpace.md),
            TextField(
              key: const ValueKey('account-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.fieldName,
                errorText: _tried && _name.text.trim().isEmpty
                    ? l10n.fieldNameError
                    : null,
              ),
            ),
            const SizedBox(height: SagipSpace.md),
            DropdownButtonFormField<UserRole>(
              key: const ValueKey('account-role'),
              initialValue: _role,
              decoration: InputDecoration(labelText: l10n.fieldRole),
              items: [
                for (final r in const [
                  UserRole.dispatcher,
                  UserRole.admin,
                  UserRole.responder,
                ])
                  DropdownMenuItem(value: r, child: Text(l10n.role(r))),
              ],
              onChanged: (r) => setState(() => _role = r ?? _role),
            ),
            if (_creating && _role == UserRole.responder) ...[
              const SizedBox(height: SagipSpace.md),
              DropdownButtonFormField<String?>(
                key: const ValueKey('account-unit'),
                initialValue: _unitId,
                decoration: InputDecoration(labelText: l10n.fieldUnitOptional),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.noUnit)),
                  for (final u in units)
                    DropdownMenuItem(value: u.id, child: Text(u.callSign)),
                ],
                onChanged: (id) => setState(() => _unitId = id),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_creating ? l10n.createAccount : l10n.save),
        ),
      ],
    );
  }
}
