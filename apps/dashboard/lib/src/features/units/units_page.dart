import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../admin/accounts_page.dart' show createRequestedAccount;
import 'duty_widgets.dart';
import '../../router.dart';
import '../common_page.dart';

/// D7: real-time status of every unit (FR9), with what each carries as its
/// crew last reported it: a unit that is low on something says so here,
/// before a dispatcher sends it. Clicking a unit opens its crew beneath it,
/// like a tree: each member's name and MDRRMD personnel ID (Joshua,
/// 2026-10-28).
class UnitsPage extends ConsumerStatefulWidget {
  const UnitsPage({super.key});

  /// GPS older than this is flagged as stale.
  static const staleAfter = Duration(minutes: 3);

  @override
  ConsumerState<UnitsPage> createState() => _UnitsPageState();
}

class _UnitsPageState extends ConsumerState<UnitsPage> {
  /// The units whose crew is showing.
  final _open = <String>{};

  void _toggle(String unitId) => setState(
    () => _open.contains(unitId) ? _open.remove(unitId) : _open.add(unitId),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final unitsAsync = ref.watch(unitsProvider);
    final units = [...?unitsAsync.value]
      ..sort((a, b) => a.callSign.compareTo(b.callSign));
    final crew = <String, List<CrewMember>>{};
    for (final c in ref.watch(crewProvider).value ?? const <CrewMember>[]) {
      crew.putIfAbsent(c.unitId, () => []).add(c);
    }
    final idle = ref.watch(unitsWithNobodyOnDutyProvider);
    final quiet = ref.watch(dutyQuietProvider);
    final locale = Localizations.localeOf(context).toString();
    final branch = WidgetStatePropertyAll<Color?>(p.panelRaised);
    // Changing a crew is for admins (`set_responder_unit`); dispatchers see
    // the crew only.
    final admin = ref.watch(currentUserProvider).value?.isAdmin ?? false;
    // Before the table so the requests panel can name each unit.

    int count(bool Function(ResponseUnit) test) => units.where(test).length;

    return PageFrame(
      title: l10n.unitsTitle,
      headerTrailing: Wrap(
        spacing: SagipSpace.sm,
        children: [
          SagipChip(
            label: l10n.countAvailable(count((u) => u.isDispatchable)),
            tone: p.success,
            icon: Symbols.check_circle_rounded,
            dense: false,
          ),
          SagipChip(
            label: l10n.countEnRoute(
              count((u) => u.status == UnitStatus.enRoute),
            ),
            tone: p.info,
            icon: Symbols.navigation_rounded,
            dense: false,
          ),
          SagipChip(
            label: l10n.countOnScene(
              count((u) => u.status == UnitStatus.onScene),
            ),
            tone: p.onScene,
            icon: Symbols.location_on_rounded,
            dense: false,
          ),
          if (idle.isNotEmpty)
            SagipChip(
              key: const ValueKey('units-no-crew'),
              label: l10n.countNoCrewOnDuty(idle.length),
              tone: p.warning,
              icon: Symbols.person_off_rounded,
              dense: false,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Crew heads' requests wait here for an admin (2026-10-29).
          if (admin) _CrewRequestsPanel(units: units),
          AsyncBody(
            value: unitsAsync,
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(
              icon: Symbols.ambulance_rounded,
              title: l10n.unitsEmpty,
              message: l10n.unitsEmptyMessage,
            ),
            builder: (_) => TableCard(
              table: DataTable(
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: Text(l10n.colCallSign)),
                  DataColumn(label: Text(l10n.colUnitType)),
                  DataColumn(label: Text(l10n.colAgency)),
                  DataColumn(label: Text(l10n.colStation)),
                  DataColumn(label: Text(l10n.colCrew), numeric: true),
                  DataColumn(label: Text(l10n.colStatus)),
                  DataColumn(label: Text(l10n.colIncident)),
                  DataColumn(label: Text(l10n.colLastGps)),
                ],
                rows: [
                  for (final u in units) ...[
                    DataRow(
                      key: ValueKey('unit-row-${u.id}'),
                      selected: _open.contains(u.id),
                      onSelectChanged: (_) => _toggle(u.id),
                      cells: [
                        DataCell(
                          Semantics(
                            button: true,
                            expanded: _open.contains(u.id),
                            label: _open.contains(u.id)
                                ? l10n.crewHide(u.callSign)
                                : l10n.crewShow(u.callSign),
                            child: Row(
                              children: [
                                Icon(
                                  _open.contains(u.id)
                                      ? Symbols.expand_more_rounded
                                      : Symbols.chevron_right_rounded,
                                  size: 18,
                                  color: p.textSecondary,
                                ),
                                const SizedBox(width: SagipSpace.xs),
                                Icon(unitTypeIcon(u.type), size: 18),
                                const SizedBox(width: SagipSpace.sm),
                                Text(u.callSign, style: text.titleSmall),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text(l10n.unitType(u.type))),
                        DataCell(Text(l10n.unitAgency(u.agency))),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              u.station,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text('${u.crewSize ?? '–'}')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              u.status == UnitStatus.available &&
                                      !u.isDispatchable
                                  ? SagipChip.status(
                                      label: l10n.assignedNotStarted,
                                      visual: incidentStatusVisual(
                                        IncidentStatus.assigned,
                                        p,
                                      ),
                                    )
                                  : SagipChip.status(
                                      label: l10n.unitStatus(u.status),
                                      visual: unitStatusVisual(u.status, p),
                                    ),
                              // Who is on duty (2026-11-01); a unit with
                              // no crew accounts is not tracked.
                              if (crew[u.id] case final members?
                                  when members.isNotEmpty) ...[
                                const SizedBox(width: SagipSpace.sm),
                                if (idle.contains(u.id))
                                  SagipChip(
                                    key: ValueKey('no-crew-${u.id}'),
                                    label: l10n.noCrewOnDuty,
                                    tone: p.warning,
                                    icon: Symbols.person_off_rounded,
                                  )
                                else
                                  Text(
                                    l10n.dutyCount(
                                      members.where((m) => m.onDuty).length,
                                      members.length,
                                    ),
                                    key: ValueKey('duty-count-${u.id}'),
                                    style: TextStyle(color: p.textSecondary),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        DataCell(
                          u.currentIncidentId == null
                              ? const Text('')
                              : TextButton(
                                  key: ValueKey('unit-incident-${u.id}'),
                                  onPressed: () => context.go(
                                    Routes.incident(u.currentIncidentId!),
                                  ),
                                  child: Text(
                                    u.currentIncidentId!,
                                    semanticsLabel: l10n.openIncident(
                                      u.currentIncidentId!,
                                    ),
                                  ),
                                ),
                        ),
                        DataCell(
                          u.lastLocationAt == null
                              ? const Text('')
                              : Row(
                                  children: [
                                    Text(l10n.ago(u.lastLocationAt!, now)),
                                    if (now.difference(u.lastLocationAt!) >
                                        UnitsPage.staleAfter) ...[
                                      const SizedBox(width: SagipSpace.sm),
                                      SagipChip(
                                        label: l10n.staleGps,
                                        tone: p.warning,
                                        icon: Symbols.gps_off_rounded,
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    ),
                    if (_open.contains(u.id))
                      if (crew[u.id] case final members?
                          when members.isNotEmpty)
                        for (final m in members)
                          _crewRow(
                            m,
                            u,
                            branch,
                            p,
                            l10n,
                            admin: admin,
                            now: now,
                            quiet: quiet,
                            locale: locale,
                          )
                      else
                        DataRow(
                          key: ValueKey('crew-none-${u.id}'),
                          color: branch,
                          cells: [
                            DataCell(
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: SagipSpace.x3,
                                ),
                                child: Text(
                                  l10n.crewNone,
                                  style: TextStyle(color: p.textSecondary),
                                ),
                              ),
                            ),
                            for (var i = 1; i < 8; i++)
                              const DataCell(Text('')),
                          ],
                        ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Admins name [m] the unit's head or assistant head, or take the role
  /// away (`admin_set_unit_leads`).
  Future<void> _setRole(CrewMember m, ResponseUnit unit, _Role role) async {
    final l10n = AppLocalizations.of(context);
    var head = unit.crewHeadId;
    var assistant = unit.assistantHeadId;
    if (head == m.staffId) head = null;
    if (assistant == m.staffId) assistant = null;
    switch (role) {
      case _Role.head:
        head = m.staffId;
      case _Role.assistant:
        assistant = m.staffId;
      case _Role.none:
        break;
    }
    await runAction(
      context,
      () => ref
          .read(crewRepositoryProvider)
          .setLeads(unit.id, headId: head, assistantId: assistant),
      success: l10n.crewLeadsSaved(unit.callSign),
    );
  }

  /// One crew member under their unit: name (indented, like a branch of a
  /// tree), personnel ID, and duty; for admins, the menu that names the
  /// crew head (adding and taking off crew is the crew head's, by request).
  DataRow _crewRow(
    CrewMember m,
    ResponseUnit unit,
    WidgetStateProperty<Color?> color,
    SagipPalette p,
    AppLocalizations l10n, {
    required bool admin,
    required DateTime now,
    required Duration quiet,
    required String locale,
  }) => DataRow(
    key: ValueKey('crew-${m.staffId}'),
    color: color,
    cells: [
      DataCell(
        Padding(
          padding: const EdgeInsets.only(left: SagipSpace.x3),
          child: Row(
            children: [
              Icon(
                Symbols.subdirectory_arrow_right_rounded,
                size: 16,
                color: p.textSecondary,
              ),
              const SizedBox(width: SagipSpace.xs),
              Icon(Symbols.person_rounded, size: 18, color: p.textSecondary),
              const SizedBox(width: SagipSpace.sm),
              Text(m.displayName),
              if (m.staffId == unit.crewHeadId) ...[
                const SizedBox(width: SagipSpace.sm),
                SagipChip(label: l10n.crewHead, tone: p.info),
              ] else if (m.staffId == unit.assistantHeadId) ...[
                const SizedBox(width: SagipSpace.sm),
                SagipChip(label: l10n.crewAssistant, tone: p.neutral),
              ],
              // Next to the name, so they are reached without scrolling the
              // table sideways.
              if (admin) ...[
                const SizedBox(width: SagipSpace.xs),
                PopupMenuButton<_Role>(
                  key: ValueKey('crew-role-${m.staffId}'),
                  tooltip: l10n.crewRoleMenu(m.displayName),
                  icon: const Icon(Symbols.badge_rounded, size: 18),
                  onSelected: (role) => _setRole(m, unit, role),
                  itemBuilder: (context) => [
                    if (m.staffId != unit.crewHeadId)
                      PopupMenuItem(
                        value: _Role.head,
                        child: Text(l10n.crewMakeHead),
                      ),
                    if (m.staffId != unit.assistantHeadId)
                      PopupMenuItem(
                        value: _Role.assistant,
                        child: Text(l10n.crewMakeAssistant),
                      ),
                    if (unit.isLead(m.staffId))
                      PopupMenuItem(
                        value: _Role.none,
                        child: Text(l10n.crewClearRole),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      DataCell(
        Text(
          m.personnelId ?? l10n.personnelIdMissing,
          style: TextStyle(
            color: m.personnelId == null ? p.textSecondary : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const DataCell(Text('')),
      // Under the unit's station, status, and last GPS: since when, on or
      // off duty, and when the phone last reported (2026-11-01).
      DataCell(
        Text(
          m.onDuty && m.dutySince != null
              ? l10n.dutySince(formatTime(m.dutySince!, locale))
              : '',
          style: TextStyle(color: p.textSecondary),
        ),
      ),
      const DataCell(Text('')),
      DataCell(
        DutyChip(
          key: ValueKey('duty-${m.staffId}'),
          member: m,
          now: now,
          quiet: quiet,
        ),
      ),
      const DataCell(Text('')),
      DataCell(
        Text(
          m.lastSeenAt == null
              ? (m.onDuty ? l10n.dutyNeverSeen : '')
              : l10n.ago(m.lastSeenAt!, now),
          style: TextStyle(color: p.textSecondary),
        ),
      ),
    ],
  );
}

enum _Role { head, assistant, none }

/// The crew heads' requests waiting for an admin, at the top of Units
/// (2026-10-29): approve (a new member's account is made first, with what
/// the head gave filled in) or decline with a reason the head sees.
class _CrewRequestsPanel extends ConsumerWidget {
  const _CrewRequestsPanel({required this.units});

  final List<ResponseUnit> units;

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    CrewRequest r,
  ) async {
    final l10n = AppLocalizations.of(context);
    String? created;
    if (r.kind == CrewRequestKind.newMember) {
      created = await createRequestedAccount(
        context,
        ref,
        name: r.subjectName,
        email: r.newEmail!,
        unitId: r.unitId,
        personnelId: r.newPersonnelId,
      );
      if (created == null || !context.mounted) return;
    }
    await runAction(
      context,
      () => ref
          .read(crewRepositoryProvider)
          .decide(r.id, approve: true, createdStaffId: created),
      success: l10n.crewApprovedSnack,
    );
    ref.invalidate(crewProvider);
  }

  Future<void> _decline(
    BuildContext context,
    WidgetRef ref,
    CrewRequest r,
  ) async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DeclineDialog(),
    );
    if (reason == null || !context.mounted) return;
    await runAction(
      context,
      () => ref
          .read(crewRepositoryProvider)
          .decide(r.id, approve: false, note: reason),
      success: l10n.crewDeclinedSnack,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final online = ref.watch(isOnlineProvider);
    // The account form a new member's approval opens lists every unit
    // from here; it must be loaded before that form opens.
    ref.watch(allUnitsProvider);
    final waiting = [
      for (final r
          in ref.watch(crewRequestsProvider).value ?? const <CrewRequest>[])
        if (r.pending) r,
    ];
    if (waiting.isEmpty) return const SizedBox.shrink();
    final callSigns = {for (final u in units) u.id: u.callSign};
    return Padding(
      padding: const EdgeInsets.only(bottom: SagipSpace.lg),
      child: Card(
        key: const ValueKey('crew-requests'),
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.how_to_reg_rounded, color: p.textSecondary),
                  const SizedBox(width: SagipSpace.sm),
                  Text(l10n.crewRequestsTitle, style: text.titleMedium),
                  const SizedBox(width: SagipSpace.sm),
                  SagipChip(
                    label: l10n.crewRequestsWaiting(waiting.length),
                    tone: p.warning,
                  ),
                ],
              ),
              for (final r in waiting) ...[
                const Divider(height: SagipSpace.xl),
                Row(
                  key: ValueKey('crew-request-${r.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(switch (r.kind) {
                      CrewRequestKind.add => Symbols.person_add_rounded,
                      CrewRequestKind.remove => Symbols.person_remove_rounded,
                      CrewRequestKind.newMember => Symbols.badge_rounded,
                    }, color: p.textSecondary),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _line(l10n, r, callSigns[r.unitId] ?? r.unitId),
                            style: text.titleSmall,
                          ),
                          if (r.kind == CrewRequestKind.newMember)
                            Text(
                              [
                                r.newEmail!,
                                r.newPersonnelId ?? l10n.personnelIdMissing,
                              ].join(' · '),
                              style: text.bodyMedium,
                            ),
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
                        ],
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    TextButton(
                      key: ValueKey('crew-decline-${r.id}'),
                      onPressed: online
                          ? () => _decline(context, ref, r)
                          : null,
                      child: Text(l10n.crewDecline),
                    ),
                    const SizedBox(width: SagipSpace.sm),
                    FilledButton.tonal(
                      key: ValueKey('crew-approve-${r.id}'),
                      onPressed: online
                          ? () => _approve(context, ref, r)
                          : null,
                      child: Text(l10n.crewApprove),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What a request asks for, in one line.
String _line(
  AppLocalizations l10n,
  CrewRequest r,
  String callSign,
) => switch (r.kind) {
  CrewRequestKind.add => l10n.crewRequestAddLine(r.subjectName, callSign),
  CrewRequestKind.remove => l10n.crewRequestRemoveLine(r.subjectName, callSign),
  CrewRequestKind.newMember => l10n.crewRequestNewLine(r.subjectName, callSign),
};

/// Asks for the reason a request is declined; pops with it.
class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog();

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _reason = TextEditingController();
  var _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final empty = _reason.text.trim().isEmpty;
    return AlertDialog(
      title: Text(l10n.crewDeclineTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('crew-decline-reason'),
          controller: _reason,
          maxLength: 300,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            labelText: l10n.crewDeclineReason,
            errorText: _tried && empty ? l10n.crewDeclineReasonError : null,
          ),
          // The error goes as soon as a reason is typed.
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            setState(() => _tried = true);
            final reason = _reason.text.trim();
            if (reason.isNotEmpty) Navigator.pop(context, reason);
          },
          child: Text(l10n.crewDecline),
        ),
      ],
    );
  }
}
