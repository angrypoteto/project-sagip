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

  static TextEditingController _field(int v) =>
      TextEditingController(text: '$v');

  @override
  void dispose() {
    for (final c in [_assisted, _injured, _missing, _families, _houses]) {
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
    );
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
