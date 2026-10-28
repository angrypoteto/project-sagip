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
import 'supply_widgets.dart';

/// A responder's own unit on the web: what it carries, reported by its
/// crew (unit inventory). It sits in the same frame as the dispatcher's
/// and the admin's pages, is the one page in a responder's menu, and is
/// the only place a unit's supplies are changed.
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
    final supplies = ref.watch(mySuppliesProvider).value ?? const [];
    final lowPercent = ref.watch(inventoryLowPercentProvider);
    final online = ref.watch(isOnlineProvider);
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final byItem = {for (final s in supplies) s.item: s};

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
        const SizedBox(height: SagipSpace.lg),
        Text(
          l10n.suppliesLowRule(lowPercent.round()),
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.lg),
        // Two cards across on a wide window, one on a narrow one.
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = SagipSpace.md;
            final across = constraints.maxWidth >= 900 ? 2 : 1;
            final width = (constraints.maxWidth - gap * (across - 1)) / across;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in SupplyItem.values)
                  SizedBox(
                    width: width,
                    child: _SupplyEditor(
                      key: ValueKey('supply-${item.name}'),
                      item: item,
                      current: byItem[item],
                      lowPercent: lowPercent,
                      now: now,
                      enabled: online,
                    ),
                  ),
              ],
            );
          },
        ),
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
      () => ask.who != null
          ? repo.requestAdd(ask.who!.staffId, note: ask.note)
          : repo.requestNew(
              name: ask.name!,
              email: ask.email!,
              personnelId: ask.personnelId,
              note: ask.note,
            ),
      success: l10n.crewAskSent,
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
                      child: Wrap(
                        spacing: SagipSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(c.displayName, style: text.bodyLarge),
                          if (c.staffId == me)
                            SagipChip(label: l10n.myUnitCrewYou, tone: p.info),
                          if (c.staffId == unit.crewHeadId)
                            SagipChip(label: l10n.crewHead, tone: p.info)
                          else if (c.staffId == unit.assistantHeadId)
                            SagipChip(
                              label: l10n.crewAssistant,
                              tone: p.neutral,
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
                    // Never on one's own row: a lead cannot ask to take
                    // themself off.
                    if (lead) ...[
                      const SizedBox(width: SagipSpace.sm),
                      if (c.staffId == me)
                        const SizedBox(width: 40)
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

/// What [_AskAddDialog] pops: someone with an account ([who]), or a new
/// person's [name], [email] and [personnelId].
typedef _AddAsk = ({
  CrewCandidate? who,
  String? name,
  String? email,
  String? personnelId,
  String? note,
});

/// Asks to add a member: a responder who has an account (on another unit
/// or none), or a new person whose account the admin makes on approving.
class _AskAddDialog extends ConsumerStatefulWidget {
  const _AskAddDialog({required this.callSign});

  final String callSign;

  @override
  ConsumerState<_AskAddDialog> createState() => _AskAddDialogState();
}

class _AskAddDialogState extends ConsumerState<_AskAddDialog> {
  var _newPerson = false;
  CrewCandidate? _who;
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
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (!_newPerson) {
      if (_who == null) return;
      Navigator.pop<_AddAsk>(context, (
        who: _who,
        name: null,
        email: null,
        personnelId: null,
        note: note,
      ));
      return;
    }
    if (!_nameOk || !_emailOk || _personnelIdError(l10n) != null) return;
    Navigator.pop<_AddAsk>(context, (
      who: null,
      name: _name.text.trim(),
      email: _email.text.trim(),
      personnelId: normalizePersonnelId(_personnelId.text),
      note: note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final candidates = ref.watch(crewCandidatesProvider).value ?? const [];
    return AlertDialog(
      title: Text(l10n.crewAskAddTitle(widget.callSign)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                key: const ValueKey('crew-ask-kind'),
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.crewHasAccount)),
                  ButtonSegment(value: true, label: Text(l10n.crewNewPerson)),
                ],
                selected: {_newPerson},
                onSelectionChanged: (v) => setState(() {
                  _newPerson = v.first;
                  _tried = false;
                }),
              ),
              const SizedBox(height: SagipSpace.lg),
              if (!_newPerson) ...[
                if (candidates.isEmpty)
                  Text(
                    l10n.crewNoCandidates,
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('crew-ask-who'),
                    initialValue: _who?.staffId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.crewAskWho,
                      errorText: _tried && _who == null
                          ? l10n.crewAskWhoError
                          : null,
                    ),
                    items: [
                      for (final c in candidates)
                        DropdownMenuItem(
                          value: c.staffId,
                          child: Text(
                            [
                              c.displayName,
                              c.personnelId ?? l10n.personnelIdMissing,
                              c.callSign ?? l10n.crewNoUnit,
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(
                      () =>
                          _who = candidates.firstWhere((c) => c.staffId == id),
                    ),
                  ),
              ] else ...[
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
                    errorText: _tried && !_emailOk
                        ? l10n.fieldEmailError
                        : null,
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
                const SizedBox(height: SagipSpace.sm),
                Text(
                  l10n.crewNewPersonHint,
                  style: text.bodySmall!.copyWith(color: p.textSecondary),
                ),
              ],
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
                l10n.crewAskBody,
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
          onPressed: !_newPerson && candidates.isEmpty ? null : _send,
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

/// One supply: how it stands, and the fields to report it again.
class _SupplyEditor extends ConsumerStatefulWidget {
  const _SupplyEditor({
    super.key,
    required this.item,
    required this.current,
    required this.lowPercent,
    required this.now,
    required this.enabled,
  });

  final SupplyItem item;
  final UnitSupply? current;
  final double lowPercent;
  final DateTime now;
  final bool enabled;

  @override
  ConsumerState<_SupplyEditor> createState() => _SupplyEditorState();
}

class _SupplyEditorState extends ConsumerState<_SupplyEditor> {
  late double _percent = widget.current?.quantity ?? 100;
  late final _have = TextEditingController(
    text: widget.current == null ? '' : '${widget.current!.quantity.round()}',
  );
  late final _full = TextEditingController(
    text: widget.current == null ? '' : '${widget.current!.capacity.round()}',
  );
  var _busy = false;

  /// A newer report (this crew's own, or a crewmate's) replaces what is in
  /// the fields: they always start from what dispatch sees.
  @override
  void didUpdateWidget(_SupplyEditor old) {
    super.didUpdateWidget(old);
    final now = widget.current;
    if (now != null && now.updatedAt != old.current?.updatedAt) {
      _percent = now.quantity;
      _have.text = '${now.quantity.round()}';
      _full.text = '${now.capacity.round()}';
    }
  }

  @override
  void dispose() {
    _have.dispose();
    _full.dispose();
    super.dispose();
  }

  int? get _haveN => int.tryParse(_have.text.trim());
  int? get _fullN => int.tryParse(_full.text.trim());

  bool get _countOk {
    final have = _haveN, full = _fullN;
    return have != null &&
        full != null &&
        full >= 1 &&
        full <= 100000 &&
        have >= 0 &&
        have <= full;
  }

  bool get _changed {
    final c = widget.current;
    if (widget.item.isPercent) return c == null || c.quantity != _percent;
    return c == null ||
        c.quantity.round() != _haveN ||
        c.capacity.round() != _fullN;
  }

  Future<void> _report() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(unitInventoryRepositoryProvider);
    final item = widget.item;
    setState(() => _busy = true);
    await runAction(
      context,
      () => item.isPercent
          ? repo.setSupply(item, _percent.round())
          : repo.setSupply(item, _haveN!, capacity: _fullN),
      success: l10n.myUnitSaved(l10n.supplyItem(item)),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final current = widget.current;
    final valid = item.isPercent || _countOk;
    final typed = _have.text.isNotEmpty || _full.text.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current == null)
              Row(
                children: [
                  Icon(supplyIcon(item), size: 18, color: p.textSecondary),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(l10n.supplyItem(item), style: text.titleSmall),
                  ),
                  Text(
                    l10n.myUnitNotYet,
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                ],
              )
            else
              SupplyLine(
                supply: current,
                lowPercent: widget.lowPercent,
                now: widget.now,
              ),
            const SizedBox(height: SagipSpace.sm),
            if (item.isPercent)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _percent,
                      max: 100,
                      divisions: 20,
                      label: l10n.supplyPercent(_percent.round()),
                      semanticFormatterCallback: (v) => l10n.myUnitPercentLabel(
                        l10n.supplyItem(item),
                        v.round(),
                      ),
                      onChanged: widget.enabled
                          ? (v) => setState(() => _percent = v)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      l10n.supplyPercent(_percent.round()),
                      textAlign: TextAlign.end,
                      style: text.titleSmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (controller, label, key) in [
                    (_have, l10n.myUnitOnBoard, 'have'),
                    (_full, l10n.myUnitFullLoad, 'full'),
                  ]) ...[
                    SizedBox(
                      width: 150,
                      child: TextField(
                        key: ValueKey('supply-${item.name}-$key'),
                        controller: controller,
                        enabled: widget.enabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(labelText: label),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                  ],
                ],
              ),
            if (!item.isPercent && typed && !valid) ...[
              const SizedBox(height: SagipSpace.xs),
              Text(
                l10n.myUnitCountError,
                style: text.bodySmall!.copyWith(color: p.critical.text),
              ),
            ],
            const SizedBox(height: SagipSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: ValueKey('report-${item.name}'),
                onPressed: widget.enabled && !_busy && valid && _changed
                    ? _report
                    : null,
                child: Text(_busy ? l10n.working : l10n.myUnitReport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
