import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// MDRRMD's own process (Joshua, 2026-11-11): the crew sends its report,
// MDRRMD validates it, and only then is the incident over. Fires are
// followed stage by stage, as on MDRRMD's fire sheet.

class _Title extends StatelessWidget {
  const _Title(this.label, {this.trailing});

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

/// Asks MDRRMD to check the crew's figures, then validates the report.
/// True when it was validated.
Future<bool> validateCrewReportFlow(
  BuildContext context,
  WidgetRef ref,
  Incident incident,
  CrewReport report,
) async {
  final l10n = AppLocalizations.of(context);
  final correction = await showDialog<CrewReportCorrection>(
    context: context,
    builder: (_) => _ValidateDialog(report: report),
  );
  if (correction == null || !context.mounted) return false;
  final closes = incident.status != IncidentStatus.resolved;
  return runAction(
    context,
    () => ref
        .read(incidentRepositoryProvider)
        .validateCrewReport(report.id, correction: correction),
    success: closes ? l10n.validatedSnack : l10n.validatedOnlySnack,
  );
}

/// The crews' completion reports, with Validate on each that waits.
class CrewReportSection extends ConsumerWidget {
  const CrewReportSection({
    super.key,
    required this.incident,
    required this.enabled,
  });

  final Incident incident;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(l10n.crewReportTitle),
        for (final r in incident.crewReports)
          Padding(
            padding: const EdgeInsets.only(bottom: SagipSpace.sm),
            child: _CrewReportCard(
              key: ValueKey('crew-report-${r.id}'),
              report: r,
              onValidate: enabled && !r.validated
                  ? () => validateCrewReportFlow(context, ref, incident, r)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// The answers of MDRRMD's form on a crew report, as (question, answer)
/// rows in the form's order. A row with no question is a heading (a
/// patient).
List<(String, String)> crewFormRows(
  AppLocalizations l10n,
  CompletionDetails x,
) {
  String bare(String title) => title.replaceAll('*', '').trim();
  return [
    if (x.emrType case final v?)
      (bare(l10n.emrTypeTitle), l10n.emrTypeLabel(v.name)),
    if (x.accidentCause case final v?)
      (bare(l10n.accidentCauseTitle), l10n.accidentCauseLabel(v.name)),
    if (x.vehicles.isNotEmpty)
      (
        l10n.vehiclesTitle,
        [for (final v in x.vehicles) l10n.vehicleLabel(v.name)].join(', '),
      ),
    for (var i = 0; i < x.patients.length; i++) ...[
      ('', l10n.patientHeading(i + 1)),
      (bare(l10n.patientName), x.patients[i].name ?? l10n.patientUnnamed),
      if (x.patients[i].age case final v?)
        (l10n.patientAge, l10n.ageBracketLabel(v.name)),
      if (x.patients[i].gender case final v?)
        (l10n.patientGender, l10n.genderLabel(v.name)),
      if (x.patients[i].hospital case final v?) (bare(l10n.patientHospital), v),
      if (x.patients[i].chiefComplaint case final v?)
        (l10n.patientComplaint, v),
      if (x.patients[i].remarks case final v?) (l10n.patientRemarks, v),
    ],
    if (x.floodCause case final v?)
      (bare(l10n.floodCauseTitle), l10n.floodCauseLabel(v.name)),
    if (x.cycloneName case final v?) (l10n.cycloneName, v),
    if (x.windSignal case final v?)
      (l10n.windSignalTitle, l10n.windSignalLabel(v)),
    if (x.floodLevel case final v?)
      (bare(l10n.floodLevelTitle), l10n.floodLevelLabel(v.name)),
    if (x.floodStatus case final v?)
      (bare(l10n.floodStatusTitle), l10n.floodStatusLabel(v.name)),
    if (x.fireKind case final v?)
      (l10n.fireKindTitle, l10n.fireKindLabel(v.name)),
    if (x.highestAlarm case final v?)
      (l10n.highestAlarmTitle, l10n.fireStageName(v.name)),
    if (x.estimatedDamage case final v?) (l10n.estimatedDamage, '$v'),
    if (x.affectedIndividuals case final v?) (l10n.affectedIndividuals, '$v'),
  ];
}

class _CrewReportCard extends StatelessWidget {
  const _CrewReportCard({super.key, required this.report, this.onValidate});

  final CrewReport report;
  final VoidCallback? onValidate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final r = report;

    Widget figure(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(
            value,
            style: text.bodyMedium!.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(SagipRadius.card),
        border: Border.all(color: r.validated ? p.hairline : p.warning.text),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.crewReportFrom(
                r.unitLabel,
                formatClock(r.capturedAt, locale),
              ),
              style: text.titleSmall,
            ),
            const SizedBox(height: SagipSpace.sm),
            figure(
              l10n.historyOutcome,
              l10n.historyOutcomeName(r.outcome.name),
            ),
            figure(l10n.historyAssisted, '${r.personsAssisted}'),
            figure(l10n.historyInjured, '${r.injured}'),
            figure(l10n.historyMissing, '${r.missing}'),
            figure(l10n.historyFamilies, '${r.affectedFamilies}'),
            figure(l10n.historyHouses, '${r.housesDamaged}'),
            if (r.timeOnSceneSeconds > 0)
              figure(
                l10n.crewReportOnScene,
                l10n.crewReportMinutes((r.timeOnSceneSeconds / 60).round()),
              ),
            if (r.narrative case final story?) ...[
              const SizedBox(height: SagipSpace.md),
              Text(l10n.crewNarrative, style: text.labelMedium),
              Text(story, style: text.bodyMedium),
            ],
            if (r.filledByRag) ...[
              const SizedBox(height: SagipSpace.xs),
              Text(
                l10n.crewFilledByRag,
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
            ],
            if (!r.details.isEmpty) ...[
              const SizedBox(height: SagipSpace.md),
              Text(l10n.crewFormAnswers, style: text.labelMedium),
              const SizedBox(height: SagipSpace.xs),
              for (final (label, value) in crewFormRows(l10n, r.details))
                label.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: SagipSpace.sm),
                        child: Text(value, style: text.titleSmall),
                      )
                    : figure(label, value),
            ],
            if (r.notes case final notes?) ...[
              const SizedBox(height: SagipSpace.sm),
              Text(l10n.crewReportNotes, style: text.labelMedium),
              Text(notes, style: text.bodyMedium),
            ],
            const SizedBox(height: SagipSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  r.validated
                      ? Symbols.verified_rounded
                      : Symbols.hourglass_top_rounded,
                  size: 20,
                  color: r.validated ? p.success.text : p.warning.text,
                ),
                const SizedBox(width: SagipSpace.sm),
                Expanded(
                  child: Text(
                    r.validated
                        ? [
                            l10n.crewReportValidatedBy(
                              r.validatedByName ?? '',
                              formatClock(r.validatedAt!, locale),
                            ),
                            if (r.corrected) l10n.crewReportCorrected,
                          ].join('. ')
                        : l10n.crewReportWaiting,
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
            if (!r.validated) ...[
              const SizedBox(height: SagipSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: ValueKey('validate-${r.id}'),
                  onPressed: onValidate,
                  child: Text(l10n.crewReportReview),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One choice from a list, for MDRRMD's form answers in the dialog.
Widget _pick<T>(
  String key,
  String label,
  T? value,
  List<T> values,
  String Function(T v) name,
  void Function(T? v) set,
) => Padding(
  padding: const EdgeInsets.only(top: SagipSpace.md),
  child: DropdownButtonFormField<T>(
    key: ValueKey('validate-$key-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final v in values)
        DropdownMenuItem(
          value: v,
          child: Text(name(v), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: set,
  ),
);

class _ValidateDialog extends StatefulWidget {
  const _ValidateDialog({required this.report});

  final CrewReport report;

  @override
  State<_ValidateDialog> createState() => _ValidateDialogState();
}

class _ValidateDialogState extends State<_ValidateDialog> {
  late RescueOutcome _outcome = widget.report.outcome;
  late final _assisted = _field(widget.report.personsAssisted);
  late final _injured = _field(widget.report.injured);
  late final _missing = _field(widget.report.missing);
  late final _families = _field(widget.report.affectedFamilies);
  late final _houses = _field(widget.report.housesDamaged);

  /// MDRRMD's form answers and narrative, as MDRRMD corrects them
  /// (2026-11-17).
  late CompletionDetails _details = widget.report.details;
  late final _narrative = TextEditingController(
    text: widget.report.narrative ?? '',
  );
  late final _damage = TextEditingController(
    text: widget.report.details.estimatedDamage?.toString() ?? '',
  );
  late final _individuals = TextEditingController(
    text: widget.report.details.affectedIndividuals?.toString() ?? '',
  );

  static TextEditingController _field(int v) =>
      TextEditingController(text: '$v');

  @override
  void dispose() {
    for (final c in [
      _assisted,
      _injured,
      _missing,
      _families,
      _houses,
      _narrative,
      _damage,
      _individuals,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _value(TextEditingController c) => int.tryParse(c.text.trim());

  bool get _valid => [
    _assisted,
    _injured,
    _missing,
    _families,
    _houses,
  ].every((c) => (_value(c) ?? -1) >= 0);

  /// Only the figures that changed; the rest keep the crew's values.
  CrewReportCorrection _correction() {
    final r = widget.report;
    int? changed(TextEditingController c, int crew) {
      final v = _value(c)!;
      return v == crew ? null : v;
    }

    return CrewReportCorrection(
      outcome: _outcome == r.outcome ? null : _outcome,
      personsAssisted: changed(_assisted, r.personsAssisted),
      injured: changed(_injured, r.injured),
      missing: changed(_missing, r.missing),
      affectedFamilies: changed(_families, r.affectedFamilies),
      housesDamaged: changed(_houses, r.housesDamaged),
      details: _formDetails() == r.details ? null : _formDetails(),
      narrative: _narrative.text.trim() == (r.narrative ?? '').trim()
          ? null
          : _narrative.text.trim(),
    );
  }

  /// The answers with the two typed numbers (fire) read in.
  CompletionDetails _formDetails() {
    final damage = int.tryParse(_damage.text.trim());
    final individuals = int.tryParse(_individuals.text.trim());
    final d = _details;
    return CompletionDetails(
      emrType: d.emrType,
      accidentCause: d.accidentCause,
      vehicles: d.vehicles,
      patients: d.patients,
      floodCause: d.floodCause,
      cycloneName: d.cycloneName,
      windSignal: d.windSignal,
      floodLevel: d.floodLevel,
      floodStatus: d.floodStatus,
      fireKind: d.fireKind,
      highestAlarm: d.highestAlarm,
      estimatedDamage: damage,
      affectedIndividuals: individuals,
    );
  }

  /// MDRRMD's form answers for the report's incident type, and the
  /// narrative, editable (2026-11-17).
  List<Widget> _formEditor(AppLocalizations l10n) {
    final d = _details;
    String bare(String title) => title.replaceAll('*', '').trim();
    void set(CompletionDetails Function(CompletionDetails d) change) =>
        setState(() => _details = change(_details));
    final medical = d.emrType != null || d.patients.isNotEmpty;
    final flood =
        d.floodCause != null || d.floodLevel != null || d.floodStatus != null;
    final fire =
        d.fireKind != null ||
        d.highestAlarm != null ||
        d.estimatedDamage != null ||
        d.affectedIndividuals != null;
    final hasNarrative = (widget.report.narrative ?? '').isNotEmpty;
    if (!medical && !flood && !fire && !hasNarrative) return const [];

    TextField typed(
      String key,
      String label,
      TextEditingController c, {
      int maxLines = 1,
      bool digits = false,
    }) => TextField(
      key: ValueKey('validate-$key'),
      controller: c,
      maxLines: maxLines,
      keyboardType: digits ? TextInputType.number : null,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    );

    return [
      const SizedBox(height: SagipSpace.xl),
      Text(l10n.crewFormAnswers, style: Theme.of(context).textTheme.titleSmall),
      if (medical) ...[
        _pick(
          'emr',
          bare(l10n.emrTypeTitle),
          d.emrType,
          EmrType.values,
          (v) => l10n.emrTypeLabel(v.name),
          (v) => set((d) => d.copyWith(emrType: v)),
        ),
        if (d.emrType == EmrType.roadAccident)
          _pick(
            'cause',
            bare(l10n.accidentCauseTitle),
            d.accidentCause,
            AccidentCause.values,
            (v) => l10n.accidentCauseLabel(v.name),
            (v) => set((d) => d.copyWith(accidentCause: v)),
          ),
        for (var i = 0; i < d.patients.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(top: SagipSpace.lg),
            child: Text(l10n.patientHeading(i + 1)),
          ),
          _pick(
            'p$i-age',
            l10n.patientAge,
            d.patients[i].age,
            AgeBracket.values,
            (v) => l10n.ageBracketLabel(v.name),
            (v) => set(
              (d) => d.copyWith(
                patients: [
                  for (var j = 0; j < d.patients.length; j++)
                    j == i ? d.patients[j].copyWith(age: v) : d.patients[j],
                ],
              ),
            ),
          ),
          _pick(
            'p$i-gender',
            l10n.patientGender,
            d.patients[i].gender,
            PatientGender.values,
            (v) => l10n.genderLabel(v.name),
            (v) => set(
              (d) => d.copyWith(
                patients: [
                  for (var j = 0; j < d.patients.length; j++)
                    j == i ? d.patients[j].copyWith(gender: v) : d.patients[j],
                ],
              ),
            ),
          ),
          _pick(
            'p$i-hospital',
            bare(l10n.patientHospital),
            d.patients[i].hospital,
            receivingHospitals,
            (v) => v,
            (v) => set(
              (d) => d.copyWith(
                patients: [
                  for (var j = 0; j < d.patients.length; j++)
                    j == i
                        ? d.patients[j].copyWith(hospital: v)
                        : d.patients[j],
                ],
              ),
            ),
          ),
        ],
      ],
      if (flood) ...[
        _pick(
          'flood-cause',
          bare(l10n.floodCauseTitle),
          d.floodCause,
          FloodCause.values,
          (v) => l10n.floodCauseLabel(v.name),
          (v) => set((d) => d.copyWith(floodCause: v)),
        ),
        _pick(
          'flood-level',
          bare(l10n.floodLevelTitle),
          d.floodLevel,
          FloodLevel.values,
          (v) => l10n.floodLevelLabel(v.name),
          (v) => set((d) => d.copyWith(floodLevel: v)),
        ),
        _pick(
          'flood-status',
          bare(l10n.floodStatusTitle),
          d.floodStatus,
          FloodStatus.values,
          (v) => l10n.floodStatusLabel(v.name),
          (v) => set((d) => d.copyWith(floodStatus: v)),
        ),
      ],
      if (fire) ...[
        _pick(
          'fire-kind',
          l10n.fireKindTitle,
          d.fireKind,
          FireKind.values,
          (v) => l10n.fireKindLabel(v.name),
          (v) => set((d) => d.copyWith(fireKind: v)),
        ),
        _pick(
          'fire-alarm',
          l10n.highestAlarmTitle,
          d.highestAlarm,
          [
            for (final s in FireStage.values)
              if (s.isAlarm && s != FireStage.positiveAlarm) s,
          ],
          (v) => l10n.fireStageName(v.name),
          (v) => set((d) => d.copyWith(highestAlarm: v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: SagipSpace.md),
          child: typed('damage', l10n.estimatedDamage, _damage, digits: true),
        ),
        Padding(
          padding: const EdgeInsets.only(top: SagipSpace.md),
          child: typed(
            'individuals',
            l10n.affectedIndividuals,
            _individuals,
            digits: true,
          ),
        ),
      ],
      if (hasNarrative)
        Padding(
          padding: const EdgeInsets.only(top: SagipSpace.lg),
          child: typed(
            'narrative',
            l10n.crewNarrative,
            _narrative,
            maxLines: 5,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget number(String key, String label, TextEditingController c) => Padding(
      padding: const EdgeInsets.only(top: SagipSpace.md),
      child: TextField(
        key: ValueKey('validate-$key'),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );

    return AlertDialog(
      title: Text(l10n.validateTitle(widget.report.unitLabel)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.validateBody),
              const SizedBox(height: SagipSpace.lg),
              DropdownButtonFormField<RescueOutcome>(
                key: const ValueKey('validate-outcome'),
                initialValue: _outcome,
                decoration: InputDecoration(labelText: l10n.historyOutcome),
                items: [
                  for (final o in RescueOutcome.values)
                    DropdownMenuItem(
                      value: o,
                      child: Text(l10n.historyOutcomeName(o.name)),
                    ),
                ],
                onChanged: (o) => setState(() => _outcome = o ?? _outcome),
              ),
              number('assisted', l10n.historyAssisted, _assisted),
              number('injured', l10n.historyInjured, _injured),
              number('missing', l10n.historyMissing, _missing),
              number('families', l10n.historyFamilies, _families),
              number('houses', l10n.historyHouses, _houses),
              ..._formEditor(l10n),
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
          key: const ValueKey('validate-confirm'),
          onPressed: _valid
              ? () => Navigator.pop(context, _correction())
              : null,
          child: Text(l10n.validateConfirm),
        ),
      ],
    );
  }
}

/// The stages of a fire with the time each was declared, and Record stage.
class FireStagesSection extends ConsumerWidget {
  const FireStagesSection({
    super.key,
    required this.incident,
    required this.enabled,
  });

  final Incident incident;
  final bool enabled;

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<(FireStage, DateTime)>(
      context: context,
      builder: (_) => _FireStageDialog(
        recorded: incident.fireStages.keys,
        now: ref.read(clockProvider).value ?? DateTime.now(),
      ),
    );
    if (picked == null || !context.mounted) return;
    await runAction(
      context,
      () => ref
          .read(incidentRepositoryProvider)
          .recordFireStage(incident.id, picked.$1, at: picked.$2),
      success: l10n.fireStageRecordedSnack(l10n.fireStage(picked.$1)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final stages = incident.fireStages.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(
          l10n.fireStagesTitle,
          trailing: TextButton.icon(
            key: const ValueKey('fire-stage-record'),
            onPressed: enabled ? () => _record(context, ref) : null,
            icon: const Icon(Symbols.add_rounded, size: 20),
            label: Text(l10n.fireStageRecord),
          ),
        ),
        if (stages.isEmpty)
          Text(
            l10n.fireStagesNone,
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          )
        else
          for (final s in stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatClock(s.value, locale),
                      style: text.bodySmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l10n.fireStage(s.key),
                      style: text.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
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

class _FireStageDialog extends StatefulWidget {
  const _FireStageDialog({required this.recorded, required this.now});

  final Iterable<FireStage> recorded;

  /// The app's clock, not the computer's.
  final DateTime now;

  @override
  State<_FireStageDialog> createState() => _FireStageDialogState();
}

class _FireStageDialogState extends State<_FireStageDialog> {
  late FireStage _stage = _next();
  late final _time = TextEditingController(text: _hhmm(widget.now));

  /// The stage after the highest one recorded.
  FireStage _next() {
    var top = -1;
    for (final s in widget.recorded) {
      if (s.index > top) top = s.index;
    }
    return FireStage.values[(top + 1).clamp(0, FireStage.values.length - 1)];
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Today at HH:MM; a time later than now is taken as yesterday (a fire
  /// recorded after midnight).
  DateTime? _at() {
    final m = RegExp(r'^(\d{1,2}):?(\d{2})$').firstMatch(_time.text.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    final now = widget.now;
    var at = DateTime(now.year, now.month, now.day, h, min);
    if (at.isAfter(now.add(const Duration(minutes: 1)))) {
      at = at.subtract(const Duration(days: 1));
    }
    return at;
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final at = _at();
    return AlertDialog(
      title: Text(l10n.fireStageDialogTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<FireStage>(
              key: const ValueKey('fire-stage-field'),
              initialValue: _stage,
              decoration: InputDecoration(labelText: l10n.fireStageField),
              items: [
                for (final s in FireStage.values)
                  DropdownMenuItem(value: s, child: Text(l10n.fireStage(s))),
              ],
              onChanged: (s) => setState(() => _stage = s ?? _stage),
            ),
            const SizedBox(height: SagipSpace.lg),
            TextField(
              key: const ValueKey('fire-stage-time'),
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.fireStageTime,
                helperText: l10n.fireStageTimeHelp,
                helperMaxLines: 3,
                errorText: at == null ? l10n.fireStageTimeInvalid : null,
              ),
              onChanged: (_) => setState(() {}),
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
          key: const ValueKey('fire-stage-save'),
          onPressed: at == null
              ? null
              : () => Navigator.pop(context, (_stage, at)),
          child: Text(l10n.fireStageSave),
        ),
      ],
    );
  }
}
