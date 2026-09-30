import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'board_dialogs.dart';

/// D4: everything a dispatcher needs to decide on one incident, in the order
/// they need it: what and where, is it real, who is affected, why it ranks
/// here, which unit to send, and what has happened so far.
class IncidentDrawer extends ConsumerStatefulWidget {
  const IncidentDrawer({
    super.key,
    required this.incidentId,
    required this.onClose,
  });

  static const double width = 460;

  final String incidentId;
  final VoidCallback onClose;

  @override
  ConsumerState<IncidentDrawer> createState() => _IncidentDrawerState();
}

class _IncidentDrawerState extends ConsumerState<IncidentDrawer> {
  /// The unit picked by the dispatcher; null means the top suggestion.
  UnitSuggestion? _chosen;
  IncidentType? _typeChoice;
  bool _busy = false;

  IncidentRepository get _repo => ref.read(incidentRepositoryProvider);

  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final ok = await runAction(context, action, success: success);
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<void> _assign(
    Incident incident,
    List<UnitSuggestion> ranked,
    UnitSuggestion chosen,
  ) async {
    final l10n = AppLocalizations.of(context);
    String? reason;
    if (ranked.isNotEmpty && chosen.unit.id != ranked.first.unit.id) {
      reason = await showOverrideDialog(
        context,
        chosen: chosen,
        top: ranked.first,
      );
      if (reason == null || !mounted) return;
    }
    final ok = await _run(
      () =>
          _repo.assignUnit(incident.id, chosen.unit.id, overrideReason: reason),
      l10n.assignedSnack(chosen.unit.callSign),
    );
    if (ok && mounted) setState(() => _chosen = null);
  }

  Future<void> _chooseAnother(Incident incident) async {
    final units = ref.read(unitsProvider).value ?? const <ResponseUnit>[];
    final all = await ref
        .read(unitSuggesterProvider)
        .suggest(incident, units, limit: 100);
    if (!mounted) return;
    final pick = await showChooseUnitDialog(context, all);
    if (pick != null && mounted) setState(() => _chosen = pick);
  }

  Future<void> _markFalse(Incident incident) async {
    final l10n = AppLocalizations.of(context);
    if (!await confirmFalseReport(context) || !mounted) return;
    final ok = await _run(
      () => _repo.markFalseReport(incident.id),
      l10n.falseReportDone,
    );
    if (ok) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final incident = ref.watch(incidentByIdProvider(widget.incidentId));
    final canAct = ref.watch(isOnlineProvider) && !_busy;

    return Material(
      color: p.panel,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: p.hairline)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 40,
              offset: Offset(-16, 0),
            ),
          ],
        ),
        child: incident == null
            ? _Closed(onClose: widget.onClose)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopRow(incident: incident, onClose: widget.onClose),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        SagipSpace.xxl,
                        0,
                        SagipSpace.xxl,
                        SagipSpace.xxl,
                      ),
                      children: [
                        _Summary(incident: incident),
                        const SizedBox(height: SagipSpace.xl),
                        _TypeRow(
                          incident: incident,
                          choice: _typeChoice ?? incident.type,
                          enabled: canAct,
                          onChanged: (t) => setState(() => _typeChoice = t),
                          onConfirm: (t) => _run(
                            () => _repo.confirmType(incident.id, t),
                            l10n.typeConfirmedSnack(l10n.incidentType(t)),
                          ),
                        ),
                        const SizedBox(height: SagipSpace.xl),
                        _Verification(
                          incident: incident,
                          enabled: canAct,
                          onVerify: () => _run(
                            () => _repo.verify(
                              incident.id,
                              VerificationMethod.callback,
                            ),
                            l10n.verifiedSnack,
                          ),
                          onSmsCheck: () => _run(
                            () => _repo.sendSmsCheck(incident.id),
                            l10n.smsCheckSentSnack,
                          ),
                          onFalse: () => _markFalse(incident),
                        ),
                        if (incident.residentId != null) ...[
                          const SizedBox(height: SagipSpace.xl),
                          _ResidentSection(incident: incident),
                        ],
                        if (incident.origin == IncidentOrigin.crowdCluster) ...[
                          const SizedBox(height: SagipSpace.xl),
                          _ClusterReports(incident: incident),
                        ],
                        const SizedBox(height: SagipSpace.xl),
                        _PrioritySection(incident: incident),
                        const SizedBox(height: SagipSpace.xl),
                        _UnitsSection(
                          incident: incident,
                          chosen: _chosen,
                          enabled: canAct,
                          onChoose: (s) => setState(() => _chosen = s),
                          onChooseAnother: () => _chooseAnother(incident),
                        ),
                        const SizedBox(height: SagipSpace.xl),
                        _Timeline(incident: incident),
                      ],
                    ),
                  ),
                  _Footer(
                    incident: incident,
                    chosen: _chosen,
                    enabled: canAct,
                    busy: _busy,
                    onAssign: (ranked, chosen) =>
                        _assign(incident, ranked, chosen),
                    onResolve: () => _run(
                      () => _repo.resolve(incident.id),
                      l10n.resolvedSnack,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ----------------------------------------------------------------- sections

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SagipSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Symbols.task_alt_rounded,
      title: l10n.incidentClosed,
      action: OutlinedButton(onPressed: onClose, child: Text(l10n.close)),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.incident, required this.onClose});

  final Incident incident;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xxl,
        SagipSpace.sm,
        SagipSpace.md,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.drawerIncidentId(incident.id),
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          IconButton(
            tooltip: l10n.close,
            onPressed: onClose,
            icon: const Icon(Symbols.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final queue = ref.watch(triageQueueProvider).value ?? const <Incident>[];
    final rank = queue.indexWhere((i) => i.id == incident.id) + 1;
    final source = l10n.locationSource(incident.channel.name);
    final coords = formatCoordinates(incident.location);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SagipChip.status(
              label: l10n.incidentStatus(incident.status),
              visual: incidentStatusVisual(incident.status, p),
            ),
            if (rank > 0)
              SagipChip(
                label: l10n.rankOf(rank, queue.length),
                tone: p.neutral,
              ),
            Text(
              l10n.waitingFor(formatWait(now.difference(incident.capturedAt))),
              style: text.titleSmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.md),
        Text(l10n.incidentTitle(incident), style: text.headlineSmall),
        const SizedBox(height: SagipSpace.xs),
        Text(
          [?incident.address, incident.place].join(', '),
          style: text.bodyMedium,
        ),
        const SizedBox(height: SagipSpace.xs),
        Text(
          incident.accuracyMeters == null
              ? l10n.locationDetailNoAccuracy(coords, source)
              : l10n.locationDetail(
                  coords,
                  source,
                  incident.accuracyMeters!.round(),
                ),
          style: text.bodySmall!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.incident,
    required this.choice,
    required this.enabled,
    required this.onChanged,
    required this.onConfirm,
  });

  final Incident incident;
  final IncidentType? choice;
  final bool enabled;
  final ValueChanged<IncidentType?> onChanged;
  final ValueChanged<IncidentType> onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final unchanged =
        incident.typeConfirmed && choice == incident.confirmedType;

    String label(IncidentType t) =>
        !incident.typeConfirmed && t == incident.suggestedType
        ? l10n.typeSuggested(l10n.incidentType(t))
        : l10n.incidentType(t);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: DropdownButtonFormField<IncidentType>(
            initialValue: choice,
            isExpanded: true,
            hint: Text(l10n.typeNotSet),
            decoration: InputDecoration(labelText: l10n.incidentTypeLabel),
            dropdownColor: p.panelRaised,
            items: [
              for (final t in IncidentType.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(incidentTypeIcon(t), size: 18),
                      const SizedBox(width: SagipSpace.sm),
                      Flexible(
                        child: Text(label(t), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
        const SizedBox(width: SagipSpace.sm),
        OutlinedButton(
          onPressed: enabled && choice != null && !unchanged
              ? () => onConfirm(choice!)
              : null,
          child: Text(l10n.confirmType),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.icon, this.color, this.label);

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color, fill: 1),
          const SizedBox(width: SagipSpace.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Verification extends StatelessWidget {
  const _Verification({
    required this.incident,
    required this.enabled,
    required this.onVerify,
    required this.onSmsCheck,
    required this.onFalse,
  });

  final Incident incident;
  final bool enabled;
  final VoidCallback onVerify;
  final VoidCallback onSmsCheck;
  final VoidCallback onFalse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final isSos = incident.origin == IncidentOrigin.sos;

    final kinds = incident.events.map((e) => e.kind).toList();
    final smsSent = kinds.lastIndexOf(IncidentEventKind.smsCheckSent);
    final smsReply = kinds.lastIndexOf(IncidentEventKind.smsReplyReceived);

    return Container(
      padding: const EdgeInsets.all(SagipSpace.lg),
      decoration: BoxDecoration(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(l10n.verificationTitle),
          if (!isSos)
            _Check(
              Symbols.check_circle_rounded,
              p.success.text,
              l10n.checkClusterVerified,
            )
          else ...[
            incident.accountVerified
                ? _Check(
                    Symbols.check_circle_rounded,
                    p.success.text,
                    l10n.checkAccountVerified,
                  )
                : _Check(
                    Symbols.error_rounded,
                    p.warning.text,
                    l10n.checkAccountNotVerified,
                  ),
            incident.mockLocationSuspected
                ? _Check(
                    Symbols.gps_off_rounded,
                    p.warning.text,
                    l10n.checkGpsMock,
                  )
                : _Check(
                    Symbols.check_circle_rounded,
                    p.success.text,
                    l10n.checkGpsOk,
                  ),
            if (incident.verificationMethod != null)
              _Check(
                Symbols.verified_rounded,
                p.success.text,
                l10n.checkVerifiedBy(
                  l10n.verificationMethod(incident.verificationMethod!),
                ),
              )
            else ...[
              _Check(
                Symbols.hourglass_top_rounded,
                p.warning.text,
                l10n.checkNotVerified,
              ),
              if (smsReply > smsSent && smsReply >= 0)
                _Check(
                  Symbols.sms_rounded,
                  p.success.text,
                  l10n.smsReplyReceived,
                )
              else if (smsSent >= 0)
                _Check(Symbols.sms_rounded, p.info.text, l10n.smsCheckPending),
            ],
            if (incident.verificationMethod == null) ...[
              const SizedBox(height: SagipSpace.md),
              Wrap(
                spacing: SagipSpace.sm,
                runSpacing: SagipSpace.sm,
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final resident = ref
                          .watch(residentProvider(incident.residentId ?? ''))
                          .value;
                      return OutlinedButton.icon(
                        onPressed: resident == null
                            ? null
                            : () => showCallDialog(context, ref, resident),
                        icon: const Icon(Symbols.call_rounded, size: 16),
                        label: Text(l10n.callResident),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled ? onSmsCheck : null,
                    icon: const Icon(Symbols.sms_rounded, size: 16),
                    label: Text(l10n.sendSmsCheck),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.success.text,
                      side: BorderSide(color: p.success.text),
                    ),
                    onPressed: enabled ? onVerify : null,
                    icon: const Icon(Symbols.verified_rounded, size: 16),
                    label: Text(l10n.markVerified),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: p.textSecondary,
                    ),
                    onPressed: enabled ? onFalse : null,
                    child: Text(l10n.markFalse),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResidentSection extends ConsumerWidget {
  const _ResidentSection({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final resident = ref.watch(residentProvider(incident.residentId!)).value;
    if (resident == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.residentTitle),
        Row(
          children: [
            // The name gets all the space the button leaves; it only
            // truncates when it truly does not fit.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      resident.fullName,
                      style: text.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: SagipSpace.md),
                  Text(
                    resident.maskedContact,
                    style: text.bodySmall!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showCallDialog(context, ref, resident),
              child: Text(l10n.showNumber),
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            for (final v in incident.vulnerable)
              SagipChip(
                label: l10n.vulnerability(v),
                tone: p.neutral,
                icon: vulnerabilityIcon(v),
              ),
            if (incident.peopleCount != null)
              SagipChip(
                label: l10n.peopleCount(incident.peopleCount!),
                tone: p.neutral,
                icon: Symbols.group_rounded,
              ),
          ],
        ),
        if (incident.note != null) ...[
          const SizedBox(height: SagipSpace.md),
          Text(l10n.residentNote, style: text.bodySmall),
          const SizedBox(height: SagipSpace.xs),
          Text(incident.note!, style: text.bodyMedium),
        ],
        if (resident.household.any((m) => m.notes != null)) ...[
          const SizedBox(height: SagipSpace.sm),
          for (final m in resident.household)
            if (m.notes != null)
              Text(
                '${m.label}: ${m.notes}',
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
        ],
      ],
    );
  }
}

class _ClusterReports extends ConsumerWidget {
  const _ClusterReports({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final ids = incident.crowdReportIds.toSet();
    final reports = [
      for (final r
          in ref.watch(crowdReportsProvider).value ?? const <CrowdReport>[])
        if (ids.contains(r.id)) r,
    ]..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.clusterReportsTitle),
        for (final r in reports)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: SagipSpace.sm),
            padding: const EdgeInsets.all(SagipSpace.md),
            decoration: BoxDecoration(
              color: p.panelRaised,
              borderRadius: BorderRadius.circular(SagipRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"${r.description}"', style: text.bodyMedium),
                const SizedBox(height: SagipSpace.xs),
                Text(
                  l10n.reportMeta(
                    formatTime(r.submittedAt, locale),
                    l10n.channel(r.channel).toLowerCase(),
                    r.suggestedType == null
                        ? l10n.typeNotSet
                        : l10n.incidentType(r.suggestedType!).toLowerCase(),
                    ((r.suggestionConfidence ?? 0) * 100).round(),
                  ),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PrioritySection extends ConsumerWidget {
  const _PrioritySection({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final breakdown = ref.watch(priorityRulesProvider).score(incident, now);
    final tabular = text.bodyMedium!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          l10n.priorityTitle,
          trailing: SagipChip(
            label:
                '${l10n.severity(breakdown.severity)}, ${l10n.points(breakdown.total.round())}',
            tone: switch (breakdown.severity) {
              Severity.critical => p.critical,
              Severity.high => p.warning,
              Severity.normal => p.neutral,
            },
          ),
        ),
        for (final f in breakdown.factors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.priorityFactor(f.kind),
                    style: text.bodyMedium,
                  ),
                ),
                Text(
                  '${f.points > 0 ? '+' : ''}${f.points.round()}',
                  style: tabular,
                ),
              ],
            ),
          ),
        const SizedBox(height: SagipSpace.xs),
        Text(l10n.provisionalRules, style: text.bodySmall),
      ],
    );
  }
}

class _UnitsSection extends ConsumerWidget {
  const _UnitsSection({
    required this.incident,
    required this.chosen,
    required this.enabled,
    required this.onChoose,
    required this.onChooseAnother,
  });

  final Incident incident;
  final UnitSuggestion? chosen;
  final bool enabled;
  final ValueChanged<UnitSuggestion> onChoose;
  final VoidCallback onChooseAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final assigned = ref.watch(unitsByIdProvider)[incident.assignedUnitId];
    final ranked =
        ref.watch(suggestionsProvider(incident.id)).value ?? const [];
    final byRoad =
        ranked.isNotEmpty && ranked.first.method == RoutingMethod.roadNetwork;
    final selectedId =
        (chosen ?? (ranked.isEmpty ? null : ranked.first))?.unit.id;
    final tiles = [
      ...ranked,
      if (chosen != null && !ranked.any((s) => s.unit.id == chosen!.unit.id))
        chosen!,
    ];

    final chooseAnother = TextButton(
      onPressed: enabled ? onChooseAnother : null,
      child: Text(l10n.chooseAnotherUnit),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assigned != null) ...[
          _SectionTitle(l10n.assignedUnitTitle, trailing: chooseAnother),
          _UnitTile(
            unit: assigned,
            trailing: SagipChip.status(
              label: incident.status == IncidentStatus.assigned
                  ? l10n.assignedNotStarted
                  : l10n.unitStatus(assigned.status),
              visual: incident.status == IncidentStatus.assigned
                  ? incidentStatusVisual(IncidentStatus.assigned, p)
                  : unitStatusVisual(assigned.status, p),
            ),
            selected: false,
          ),
          if (chosen != null) ...[
            const SizedBox(height: SagipSpace.sm),
            _SuggestionTile(suggestion: chosen!, selected: true, onTap: null),
          ],
        ] else ...[
          _SectionTitle(l10n.suggestedUnitsTitle, trailing: chooseAnother),
          Text(
            byRoad ? l10n.suggestedByRoad : l10n.suggestedByDistance,
            style: text.bodySmall,
          ),
          const SizedBox(height: SagipSpace.sm),
          if (tiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(SagipSpace.lg),
              decoration: BoxDecoration(
                border: Border.all(color: p.hairline),
                borderRadius: BorderRadius.circular(SagipRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.noAvailableUnits, style: text.titleSmall),
                  Text(l10n.noAvailableUnitsMessage, style: text.bodySmall),
                ],
              ),
            )
          else
            for (final s in tiles)
              Padding(
                padding: const EdgeInsets.only(bottom: SagipSpace.sm),
                child: _SuggestionTile(
                  suggestion: s,
                  selected: s.unit.id == selectedId,
                  onTap: enabled ? () => onChoose(s) : null,
                ),
              ),
        ],
      ],
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.unit,
    required this.trailing,
    required this.selected,
  });

  final ResponseUnit unit;
  final Widget trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SagipSpace.md,
        vertical: SagipSpace.md,
      ),
      decoration: BoxDecoration(
        color: selected ? p.info.tint : null,
        border: Border.all(color: selected ? p.info.fill : p.hairlineStrong),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Row(
        children: [
          Icon(unitTypeIcon(unit.type), size: 20),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(unit.callSign, style: text.titleSmall),
                Text(
                  l10n.unitStationCrew(
                    '${l10n.unitType(unit.type)}, ${unit.station}',
                    unit.crewSize,
                  ),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.selected,
    required this.onTap,
  });

  final UnitSuggestion suggestion;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final tabular = const [FontFeature.tabularFigures()];
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        onTap: onTap,
        child: _UnitTile(
          unit: suggestion.unit,
          selected: selected,
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l10n.etaMinutes(suggestion.etaMinutes.round().clamp(1, 999)),
                style: text.titleMedium!.copyWith(fontFeatures: tabular),
              ),
              Text(
                l10n.distanceKm(suggestion.distanceKm.toStringAsFixed(1)),
                style: text.bodySmall!.copyWith(fontFeatures: tabular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.incident});

  final Incident incident;

  String? _detail(AppLocalizations l10n, IncidentEvent e) {
    final d = e.detail;
    if (d == null) return null;
    return switch (e.kind) {
      IncidentEventKind.typeConfirmed => l10n.incidentType(
        IncidentType.values.byName(d),
      ),
      IncidentEventKind.verified => l10n.verificationMethod(
        VerificationMethod.values.byName(d),
      ),
      _ => d,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.timelineTitle),
        for (final e in incident.events.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    formatClock(e.at, locale),
                    style: text.bodySmall!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: l10n.incidentEvent(e.kind),
                          style: text.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_detail(l10n, e) case final detail?)
                          TextSpan(text: ' $detail', style: text.bodyMedium),
                        if (e.actorName != null)
                          TextSpan(
                            text: '  ${e.actorName}',
                            style: text.bodySmall!.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.incident,
    required this.chosen,
    required this.enabled,
    required this.busy,
    required this.onAssign,
    required this.onResolve,
  });

  final Incident incident;
  final UnitSuggestion? chosen;
  final bool enabled;
  final bool busy;
  final void Function(List<UnitSuggestion> ranked, UnitSuggestion chosen)
  onAssign;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final online = ref.watch(isOnlineProvider);
    final ranked =
        ref.watch(suggestionsProvider(incident.id)).value ?? const [];
    final target = chosen ?? (ranked.isEmpty ? null : ranked.first);
    final hasUnit = incident.assignedUnitId != null;

    final (String? label, VoidCallback? action) = switch (incident.status) {
      _ when !hasUnit && target != null => (
        l10n.assignUnit(target.unit.callSign),
        () => onAssign(ranked, target),
      ),
      _ when hasUnit && chosen != null => (
        l10n.reassignUnit(chosen!.unit.callSign),
        () => onAssign(ranked, chosen!),
      ),
      IncidentStatus.onScene => (l10n.markResolved, onResolve),
      _ => (null, null),
    };
    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        SagipSpace.xxl,
        SagipSpace.lg,
        SagipSpace.xxl,
        SagipSpace.lg,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: enabled ? action : null,
            // Never a bare spinner on a critical action (design skill).
            child: busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: SagipSpace.sm),
                      Text(l10n.working),
                    ],
                  )
                : Text(label),
          ),
          if (!online) ...[
            const SizedBox(height: SagipSpace.sm),
            Text(
              l10n.offlineActionsDisabled,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
