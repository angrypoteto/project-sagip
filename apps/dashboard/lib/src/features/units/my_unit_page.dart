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
import 'duty_widgets.dart';

/// A responder's own unit on the web: the unit, its crew and who is on
/// duty, and the crew head's requests. What it carries is reported on the
/// responder's Inventory page (2026-11-01, kept apart like dispatch's).
/// Both sit in the same frame as the dispatcher's and the admin's pages.
class MyUnitPage extends ConsumerWidget {
  const MyUnitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unitAsync = ref.watch(myUnitProvider);
    return PageFrame(
      title: l10n.myUnitTitle,
      subtitle: l10n.myUnitIntro,
      child: AsyncBody(
        value: unitAsync,
        isEmpty: (unit) => unit == null,
        empty: EmptyState(
          icon: Symbols.group_off_rounded,
          title: l10n.myUnitNone,
          message: l10n.myUnitNoneBody,
        ),
        onRetry: () => ref.invalidate(myUnitProvider),
        builder: (unit) => _Body(unit: unit!),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.unit});

  final ResponseUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            SagipChip.status(
              label: l10n.unitStatus(unit.status),
              visual: unitStatusVisual(unit.status, p),
              dense: false,
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Row(
              children: [
                Icon(unitTypeIcon(unit.type), size: 28),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.callSign, style: text.titleLarge),
                      Text(
                        '${l10n.unitType(unit.type)} · '
                        '${l10n.unitAgency(unit.agency)} · ${unit.station}',
                        style: text.bodyMedium!.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        _CrewCard(unit: unit),
        // A crew head's or assistant head's requests and the answers.
        if (unit.isLead(ref.watch(currentUserProvider).value?.id)) ...[
          const SizedBox(height: SagipSpace.md),
          const _RequestsCard(),
        ],
      ],
    );
  }
}

/// Who is on this unit (Joshua, 2026-10-28): each member's full name and
/// MDRRMD personnel ID, the signed-in responder marked "You". The crew
/// head and assistant head (2026-10-29) also ask here to add or remove
/// members; an admin approves or declines.
class _CrewCard extends ConsumerWidget {
  const _CrewCard({required this.unit});

  final ResponseUnit unit;

  Future<void> _askAdd(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ask = await showDialog<_AddAsk>(
      context: context,
      builder: (context) => _AskAddDialog(callSign: unit.callSign),
    );
    if (ask == null || !context.mounted) return;
    final repo = ref.read(crewRepositoryProvider);
    await runAction(
      context,
      () => repo.requestNew(
        name: ask.name,
        email: ask.email,
        personnelId: ask.personnelId,
        note: ask.note,
      ),
      success: l10n.crewAskSent,
    );
  }

  Future<void> _setDuty(
    BuildContext context,
    WidgetRef ref,
    CrewMember m,
    bool on,
  ) async {
    final l10n = AppLocalizations.of(context);
    await runAction(
      context,
      () => ref.read(crewRepositoryProvider).setDuty(m.staffId, onDuty: on),
      success: on
          ? l10n.dutyStartedSnack(m.displayName)
          : l10n.dutyEndedSnack(m.displayName),
    );
  }

  Future<void> _askRemove(
    BuildContext context,
    WidgetRef ref,
    CrewMember m,
  ) async {
    final l10n = AppLocalizations.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _AskRemoveDialog(
        title: l10n.crewAskRemoveTitle(m.displayName, unit.callSign),
      ),
    );
    if (note == null || !context.mounted) return;
    await runAction(
      context,
      () => ref
          .read(crewRepositoryProvider)
          .requestRemove(m.staffId, note: note.isEmpty ? null : note),
      success: l10n.crewAskSent,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider).value?.id;
    final online = ref.watch(isOnlineProvider);
    final lead = unit.isLead(me);
    final crew = [
      for (final c in ref.watch(crewProvider).value ?? const <CrewMember>[])
        if (c.unitId == unit.id) c,
    ];
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final quiet = ref.watch(dutyQuietProvider);
    final locale = Localizations.localeOf(context).toString();
    // Duty (2026-11-01): the head switches it; the assistant head while
    // the head is off duty.
    final headOnDuty = crew.any(
      (c) => c.staffId == unit.crewHeadId && c.onDuty,
    );
    final switcher =
        me != null &&
        (me == unit.crewHeadId || (me == unit.assistantHeadId && !headOnDuty));
    // One waiting removal per member is enough.
    final asked = {
      if (lead)
        for (final r
            in ref.watch(crewRequestsProvider).value ?? const <CrewRequest>[])
          if (r.pending && r.kind == CrewRequestKind.remove) r.staffId,
    };
    return Card(
      key: const ValueKey('my-unit-crew'),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.groups_rounded, color: p.textSecondary),
                const SizedBox(width: SagipSpace.sm),
                Text(l10n.myUnitCrewTitle, style: text.titleMedium),
                const SizedBox(width: SagipSpace.sm),
                Text(
                  '${crew.length}',
                  style: text.titleMedium!.copyWith(
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                if (lead)
                  OutlinedButton.icon(
                    key: const ValueKey('crew-ask-add'),
                    onPressed: online ? () => _askAdd(context, ref) : null,
                    icon: const Icon(Symbols.person_add_rounded, size: 18),
                    label: Text(l10n.crewAskAdd),
                  ),
              ],
            ),
            if (lead) ...[
              const SizedBox(height: SagipSpace.xs),
              Text(
                l10n.myUnitLeadNote(
                  me == unit.crewHeadId ? 'head' : 'assistant',
                ),
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
              Text(
                me == unit.crewHeadId
                    ? l10n.myUnitDutyHead
                    : switcher
                    ? l10n.myUnitDutyActing
                    : l10n.myUnitDutyWait,
                key: const ValueKey('my-unit-duty-note'),
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
            ],
            const SizedBox(height: SagipSpace.sm),
            for (final c in crew)
              Padding(
                key: ValueKey('my-crew-${c.staffId}'),
                padding: const EdgeInsets.symmetric(vertical: SagipSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      Symbols.person_rounded,
                      size: 20,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: SagipSpace.sm,
                            runSpacing: SagipSpace.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(c.displayName, style: text.bodyLarge),
                              if (c.staffId == me)
                                SagipChip(
                                  label: l10n.myUnitCrewYou,
                                  tone: p.info,
                                ),
                              if (c.staffId == unit.crewHeadId)
                                SagipChip(label: l10n.crewHead, tone: p.info)
                              else if (c.staffId == unit.assistantHeadId)
                                SagipChip(
                                  label: l10n.crewAssistant,
                                  tone: p.neutral,
                                ),
                              DutyChip(
                                key: ValueKey('my-duty-${c.staffId}'),
                                member: c,
                                now: now,
                                quiet: quiet,
                              ),
                            ],
                          ),
                          if (dutyDetail(l10n, c, now, locale) case final detail
                              when detail.isNotEmpty)
                            Text(
                              detail,
                              style: text.bodySmall!.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      c.personnelId ?? l10n.personnelIdMissing,
                      style: text.bodyMedium!.copyWith(
                        color: c.personnelId == null ? p.textSecondary : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (switcher) ...[
                      const SizedBox(width: SagipSpace.sm),
                      Switch(
                        key: ValueKey('duty-switch-${c.staffId}'),
                        value: c.onDuty,
                        onChanged: online
                            ? (on) => _setDuty(context, ref, c, on)
                            : null,
                      ),
                    ],
                    // Never on one's own row: a lead cannot ask to take
                    // themself off.
                    if (lead) ...[
                      const SizedBox(width: SagipSpace.sm),
                      if (c.staffId == me)
                        // As wide as the button on the other rows.
                        const SizedBox(width: 48)
                      else
                        IconButton(
                          key: ValueKey('crew-ask-remove-${c.staffId}'),
                          tooltip: l10n.crewAskRemove(c.displayName),
                          onPressed: online && !asked.contains(c.staffId)
                              ? () => _askRemove(context, ref, c)
                              : null,
                          icon: const Icon(
                            Symbols.person_remove_rounded,
                            size: 20,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            if (crew.length <= 1)
              Text(
                l10n.myUnitCrewEmpty,
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// The lead's requests, newest first, with what the admin decided.
class _RequestsCard extends ConsumerWidget {
  const _RequestsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final requests = ref.watch(crewRequestsProvider).value ?? const [];
    if (requests.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('my-unit-requests'),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.how_to_reg_rounded, color: p.textSecondary),
                const SizedBox(width: SagipSpace.sm),
                Text(l10n.myUnitRequestsTitle, style: text.titleMedium),
              ],
            ),
            for (final r in requests) ...[
              const Divider(height: SagipSpace.xl),
              Row(
                key: ValueKey('my-request-${r.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_myLine(l10n, r), style: text.titleSmall),
                        Text(
                          l10n.crewRequestBy(
                            r.requestedByName,
                            l10n.ago(r.requestedAt, now),
                          ),
                          style: text.bodySmall!.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        if (r.note != null)
                          Text(
                            l10n.crewRequestNote(r.note!),
                            style: text.bodySmall,
                          ),
                        if (r.decidedByName != null)
                          Text(
                            l10n.crewDecidedBy(
                              _status(l10n, r.status),
                              r.decidedByName!,
                            ),
                            style: text.bodySmall!.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        if (r.decisionNote != null)
                          Text(
                            l10n.crewDecisionNote(r.decisionNote!),
                            style: text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SagipSpace.md),
                  SagipChip(
                    label: _status(l10n, r.status),
                    tone: switch (r.status) {
                      CrewRequestStatus.pending => p.warning,
                      CrewRequestStatus.approved => p.success,
                      CrewRequestStatus.declined => p.neutral,
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _myLine(AppLocalizations l10n, CrewRequest r) => switch (r.kind) {
  CrewRequestKind.add => l10n.crewMyAddLine(r.subjectName),
  CrewRequestKind.remove => l10n.crewMyRemoveLine(r.subjectName),
  CrewRequestKind.newMember => l10n.crewMyNewLine(r.subjectName),
};

String _status(AppLocalizations l10n, CrewRequestStatus s) => switch (s) {
  CrewRequestStatus.pending => l10n.crewStatusPending,
  CrewRequestStatus.approved => l10n.crewStatusApproved,
  CrewRequestStatus.declined => l10n.crewStatusDeclined,
};

/// What [_AskAddDialog] pops: the new person's details.
typedef _AddAsk = ({
  String name,
  String email,
  String? personnelId,
  String? note,
});

/// Asks for a new member of this unit (2026-11-01: only someone with no
/// account yet; the admin makes their account when approving). Moving a
/// responder from another unit is never a crew head's to ask for.
class _AskAddDialog extends StatefulWidget {
  const _AskAddDialog({required this.callSign});

  final String callSign;

  @override
  State<_AskAddDialog> createState() => _AskAddDialogState();
}

class _AskAddDialogState extends State<_AskAddDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _personnelId = TextEditingController();
  final _note = TextEditingController();
  var _tried = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _personnelId.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _personnelIdError(AppLocalizations l10n) {
    final v = normalizePersonnelId(_personnelId.text);
    if (v == null) return null;
    return isValidPersonnelId(v) ? null : l10n.fieldPersonnelIdError;
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _emailOk => _emailPattern.hasMatch(_email.text.trim());

  void _send() {
    final l10n = AppLocalizations.of(context);
    setState(() => _tried = true);
    if (!_nameOk || !_emailOk || _personnelIdError(l10n) != null) return;
    final note = _note.text.trim();
    Navigator.pop<_AddAsk>(context, (
      name: _name.text.trim(),
      email: _email.text.trim(),
      personnelId: normalizePersonnelId(_personnelId.text),
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.crewAskAddTitle(widget.callSign)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('crew-ask-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.fieldName,
                  errorText: _tried && !_nameOk ? l10n.fieldNameError : null,
                ),
              ),
              const SizedBox(height: SagipSpace.md),
              TextField(
                key: const ValueKey('crew-ask-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.fieldEmail,
                  errorText: _tried && !_emailOk ? l10n.fieldEmailError : null,
                ),
              ),
              const SizedBox(height: SagipSpace.md),
              TextField(
                key: const ValueKey('crew-ask-personnel-id'),
                controller: _personnelId,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.fieldPersonnelId,
                  helperText: l10n.fieldPersonnelIdHelp,
                  errorText: _tried ? _personnelIdError(l10n) : null,
                ),
              ),
              const SizedBox(height: SagipSpace.md),
              TextField(
                key: const ValueKey('crew-ask-note'),
                controller: _note,
                maxLength: 300,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(labelText: l10n.crewAskNote),
              ),
              Text(
                l10n.crewNewPersonHint,
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('crew-ask-send'),
          onPressed: _send,
          child: Text(l10n.crewAskSend),
        ),
      ],
    );
  }
}

/// Confirms a removal request, with an optional note. Pops with the note
/// ('' for none).
class _AskRemoveDialog extends StatefulWidget {
  const _AskRemoveDialog({required this.title});

  final String title;

  @override
  State<_AskRemoveDialog> createState() => _AskRemoveDialogState();
}

class _AskRemoveDialogState extends State<_AskRemoveDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.crewAskBody),
            const SizedBox(height: SagipSpace.md),
            TextField(
              key: const ValueKey('crew-ask-remove-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: l10n.crewAskNote),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('crew-ask-remove-send'),
          onPressed: () => Navigator.pop(context, _note.text.trim()),
          child: Text(l10n.crewAskSend),
        ),
      ],
    );
  }
}
