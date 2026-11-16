import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/counter.dart';
import '../../common/labels.dart';
import '../../common/offline_banner.dart';
import '../../common/photo_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// What the responder has typed so far in F6. Kept while they move around
/// the app; Hive keeps it across restarts later (plan: drafts are saved).
@immutable
class CompletionDraft {
  const CompletionDraft({
    required this.incidentId,
    this.outcome,
    this.persons,
    this.houses = 0,
    this.injured = 0,
    this.missing = 0,
    this.families = 0,
    this.notes = '',
    this.details = const CompletionDetails(),
    this.photos = const [],
    this.whatHappened = '',
    this.narrative = '',
    this.filledByRag = false,
  });

  final String incidentId;
  final RescueOutcome? outcome;
  final int? persons;
  final int houses;
  final int injured;
  final int missing;
  final int families;
  final String notes;

  /// The answers MDRRMD's form for the incident's type asks (2026-11-17).
  final CompletionDetails details;

  /// Photos ready to send ([preparePhoto]).
  final List<Uint8List> photos;

  /// What the responder wrote or dictated for "Fill from notes" (RAG).
  final String whatHappened;

  /// The narrative for MDRRMD, from the fill, as the responder left it.
  final String narrative;

  /// "Fill from notes" filled the answers.
  final bool filledByRag;

  CompletionDraft copyWith({
    RescueOutcome? outcome,
    int? persons,
    int? houses,
    int? injured,
    int? missing,
    int? families,
    String? notes,
    CompletionDetails? details,
    List<Uint8List>? photos,
    String? whatHappened,
    String? narrative,
    bool? filledByRag,
  }) => CompletionDraft(
    incidentId: incidentId,
    outcome: outcome ?? this.outcome,
    persons: persons ?? this.persons,
    houses: houses ?? this.houses,
    injured: injured ?? this.injured,
    missing: missing ?? this.missing,
    families: families ?? this.families,
    notes: notes ?? this.notes,
    details: details ?? this.details,
    photos: photos ?? this.photos,
    whatHappened: whatHappened ?? this.whatHappened,
    narrative: narrative ?? this.narrative,
    filledByRag: filledByRag ?? this.filledByRag,
  );
}

class CompletionDraftController extends Notifier<CompletionDraft?> {
  @override
  CompletionDraft? build() => null;

  void update(CompletionDraft next) => state = next;
  void clear() => state = null;
}

final completionDraftProvider =
    NotifierProvider<CompletionDraftController, CompletionDraft?>(
      CompletionDraftController.new,
    );

/// What to answer first on MDRRMD's form, as the message to show, or null
/// when nothing is missing. A false report needs none of it.
String? missingAnswer(AppLocalizations l10n, String? type, CompletionDraft d) {
  if (d.outcome == RescueOutcome.falseReport) return null;
  final x = d.details;
  String bare(String title) => title.replaceAll('*', '').trim();
  String ask(String title) => l10n.crewFormMissing(bare(title));
  switch (type) {
    case 'medical':
      if (x.emrType == null) return ask(l10n.emrTypeTitle);
      if (x.emrType == EmrType.roadAccident && x.accidentCause == null) {
        return ask(l10n.accidentCauseTitle);
      }
      for (var i = 0; i < x.patients.length; i++) {
        if ((x.patients[i].hospital ?? '').isEmpty) {
          return l10n.crewFormMissingPatient(
            bare(l10n.patientHospital),
            l10n.patientHeading(i + 1),
          );
        }
      }
    case 'flood':
      if (x.floodCause == null) return ask(l10n.floodCauseTitle);
      if (x.floodLevel == null) return ask(l10n.floodLevelTitle);
      if (x.floodStatus == null) return ask(l10n.floodStatusTitle);
  }
  return null;
}

/// F6 Completion and damage report, with the questions of MDRRMD's form
/// for the incident's type (EMR, flood, fire) and photos (2026-11-17).
class CompletePage extends ConsumerStatefulWidget {
  const CompletePage({super.key});

  @override
  ConsumerState<CompletePage> createState() => _CompletePageState();
}

class _CompletePageState extends ConsumerState<CompletePage> {
  final _fields = <String, TextEditingController>{};
  String? _error;
  var _saving = false;
  var _filling = false;
  String? _fillMessage;

  TextEditingController _field(String key, String initial) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The saved draft for [a], or a new one started from what the phone
  /// already knows: F5's check, the SOS (people, sender's name, household),
  /// PAGASA's reading, the fire alarms recorded (2026-11-17).
  CompletionDraft _draftFor(Assignment a, CompletionDraft? saved) {
    if (saved != null && saved.incidentId == a.incidentId) return saved;
    final details = prefillCompletionDetails(
      a,
      weather: ref.read(weatherProvider).value,
    );
    return CompletionDraft(
      incidentId: a.incidentId,
      outcome: a.realEmergency == false ? RescueOutcome.falseReport : null,
      persons: a.peopleFound ?? a.peopleCount,
      injured: details.patients.length,
      details: details,
    );
  }

  Assignment? get _assignment => ref.read(responderProvider).value?.current;

  void _update(CompletionDraft Function(CompletionDraft d) change) {
    final a = _assignment;
    if (a == null) return;
    final base = _draftFor(a, ref.read(completionDraftProvider));
    ref.read(completionDraftProvider.notifier).update(change(base));
    if (_error != null) setState(() => _error = null);
  }

  void _details(CompletionDetails Function(CompletionDetails x) change) =>
      _update((d) => d.copyWith(details: change(d.details)));

  void _patient(int i, PatientRecord Function(PatientRecord p) change) =>
      _details((x) {
        final list = [...x.patients];
        list[i] = change(list[i]);
        return x.copyWith(patients: list);
      });

  /// Changes the number of patients. Injured and persons assisted follow
  /// it while they still equal the old count (not typed over).
  void _setPatientCount(int n) {
    final count = n.clamp(0, 30);
    _update((d) {
      final old = d.details.patients.length;
      final injured = d.injured == old ? count : d.injured;
      final persons = (d.persons ?? 0) <= old ? count : d.persons;
      _fields['injured']?.text = '$injured';
      return d.copyWith(
        injured: injured,
        persons: persons,
        details: d.details.copyWith(
          patients: [
            for (var i = 0; i < count; i++)
              i < d.details.patients.length
                  ? d.details.patients[i]
                  : const PatientRecord(),
          ],
        ),
      );
    });
  }

  /// "Fill from notes" (RAG, 2026-11-17): the server fills in the form's
  /// answers and writes a narrative from what the responder wrote; they
  /// check them before submitting.
  Future<void> _fillFromNotes() async {
    final l10n = AppLocalizations.of(context);
    final a = _assignment;
    if (a == null) return;
    final notes = _draftFor(
      a,
      ref.read(completionDraftProvider),
    ).whatHappened.trim();
    if (notes.length < 10) {
      return setState(() => _fillMessage = l10n.ragShort);
    }
    setState(() {
      _filling = true;
      _fillMessage = null;
    });
    String message;
    try {
      final fill = await ref
          .read(responderRepositoryProvider)
          .fillFromNotes(notes);
      _update((d) {
        final f = fill.figures;
        final next = d.copyWith(
          details: fill.mergeInto(d.details),
          persons: f['persons_assisted'],
          injured: f['injured'],
          missing: f['missing'],
          families: f['affected_families'],
          houses: f['houses_damaged'],
          narrative: fill.narrative.isEmpty ? null : fill.narrative,
          filledByRag: true,
        );
        // The number fields keep their own text: set it to the new values.
        for (final (key, value) in [
          ('injured', next.injured),
          ('missing', next.missing),
          ('families', next.families),
          ('houses', next.houses),
          ('narrative', null),
        ]) {
          if (key == 'narrative') {
            _fields[key]?.text = next.narrative;
          } else {
            _fields[key]?.text = '$value';
          }
        }
        for (var i = 0; i < next.details.patients.length; i++) {
          final p = next.details.patients[i];
          _fields['p$i-complaint']?.text = p.chiefComplaint ?? '';
          _fields['p$i-remarks']?.text = p.remarks ?? '';
        }
        _fields['damage_php']?.text =
            next.details.estimatedDamage?.toString() ?? '';
        _fields['individuals']?.text =
            next.details.affectedIndividuals?.toString() ?? '';
        _fields['cyclone']?.text = next.details.cycloneName ?? '';
        return next;
      });
      message = l10n.ragDone(fill.filledCount);
    } on ActionRejected catch (e) {
      message = switch (e.reason) {
        ActionRejection.offline => l10n.ragOffline,
        ActionRejection.rateLimited => l10n.ragLimited,
        ActionRejection.notSetUp => l10n.ragNotSetUp,
        _ => l10n.ragFailed,
      };
    }
    if (!mounted) return;
    setState(() {
      _filling = false;
      _fillMessage = message;
    });
  }

  Future<void> _addPhoto() async {
    final jpeg = await pickPhoto(context, ref);
    if (jpeg == null || !mounted) return;
    _update(
      (d) => d.photos.length >= maxCrewPhotos
          ? d
          : d.copyWith(photos: [...d.photos, jpeg]),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final a = _assignment;
    if (a == null) return;
    final d = _draftFor(a, ref.read(completionDraftProvider));
    if (d.outcome == null) return setState(() => _error = l10n.chooseOutcome);
    final type = a.type?.name;
    final missing = missingAnswer(l10n, type, d);
    if (missing != null) return setState(() => _error = missing);
    final minPhotos = d.outcome == RescueOutcome.falseReport
        ? 0
        : minimumCrewPhotos(type);
    if (d.photos.length < minPhotos) {
      return setState(() => _error = l10n.crewPhotosMissing(minPhotos));
    }
    setState(() => _saving = true);
    await ref
        .read(responderRepositoryProvider)
        .complete(
          outcome: d.outcome!,
          personsAssisted: d.persons ?? 0,
          housesDamaged: d.houses,
          injured: d.injured,
          missing: d.missing,
          affectedFamilies: d.families,
          notes: d.notes.trim().isEmpty ? null : d.notes.trim(),
          details: d.details,
          photos: d.photos,
          narrative: d.narrative.trim().isEmpty ? null : d.narrative.trim(),
          filledByRag: d.filledByRag,
        );
    ref.read(completionDraftProvider.notifier).clear();
    final online =
        (ref.read(signalProvider).value ?? SignalState.internet) ==
        SignalState.internet;
    messenger.showSnackBar(
      SnackBar(
        content: Text(online ? l10n.reportSubmitted : l10n.reportSavedOffline),
      ),
    );
    if (mounted) context.go(Routes.duty);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final a = ref.watch(responderProvider).value?.current;
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.completeTitle)),
        body: EmptyState(
          icon: Symbols.task_alt_rounded,
          title: l10n.noAssignmentTitle,
        ),
      );
    }
    // The saved draft for this assignment, or a fresh one.
    final d = _draftFor(a, ref.watch(completionDraftProvider));
    final type = a.type?.name;
    final minutes = a.onSceneAt == null
        ? 0
        : now.difference(a.onSceneAt!).inMinutes.clamp(0, 9999);

    Widget number(
      String key,
      String label,
      int? value,
      void Function(int) set,
    ) => TextField(
      controller: _field(key, value == null ? '' : '$value'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => set(int.tryParse(v) ?? 0),
    );

    Widget words(
      String key,
      String label,
      String? value,
      void Function(String) set, {
      int maxLines = 1,
    }) => TextField(
      controller: _field(key, value ?? ''),
      maxLines: maxLines,
      maxLength: maxLines > 1 ? 1000 : 100,
      buildCounter: (
        _, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => null,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(labelText: label),
      onChanged: set,
    );

    Widget title(String s) => Padding(
      padding: const EdgeInsets.only(top: SagipSpace.xl, bottom: SagipSpace.sm),
      child: Text(s, style: text.titleMedium),
    );

    /// One choice of several, as chips.
    Widget choose<T>(
      List<T> values,
      T? selected,
      String Function(T v) label,
      void Function(T v) set,
    ) => Wrap(
      spacing: SagipSpace.sm,
      runSpacing: SagipSpace.sm,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: selected == v,
            onSelected: (_) => set(v),
          ),
      ],
    );

    final x = d.details;
    final form = <Widget>[
      if (type == 'medical') ...[
        title(l10n.emrTypeTitle),
        choose(
          EmrType.values,
          x.emrType,
          (v) => l10n.emrTypeLabel(v.name),
          (v) => _details((x) => x.copyWith(emrType: v)),
        ),
        if (x.emrType == EmrType.roadAccident) ...[
          title(l10n.accidentCauseTitle),
          choose(
            AccidentCause.values,
            x.accidentCause,
            (v) => l10n.accidentCauseLabel(v.name),
            (v) => _details((x) => x.copyWith(accidentCause: v)),
          ),
          title(l10n.vehiclesTitle),
          Wrap(
            spacing: SagipSpace.sm,
            runSpacing: SagipSpace.sm,
            children: [
              for (final v in VehicleKind.values)
                FilterChip(
                  label: Text(l10n.vehicleLabel(v.name)),
                  selected: x.vehicles.contains(v),
                  onSelected: (on) => _details(
                    (x) => x.copyWith(
                      vehicles: on
                          ? [...x.vehicles, v]
                          : [
                              for (final k in x.vehicles)
                                if (k != v) k,
                            ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        title(l10n.patientsTitle),
        Counter(
          value: x.patients.length,
          label: l10n.patientCount(x.patients.length),
          fewerLabel: l10n.fewerPatients,
          moreLabel: l10n.morePatients,
          onChanged: _setPatientCount,
        ),
        for (var i = 0; i < x.patients.length; i++)
          _PatientCard(
            index: i,
            patient: x.patients[i],
            field: _field,
            onChanged: (change) => _patient(i, change),
          ),
      ],
      if (type == 'flood') ...[
        title(l10n.floodCauseTitle),
        choose(
          FloodCause.values,
          x.floodCause,
          (v) => l10n.floodCauseLabel(v.name),
          (v) => _details((x) => x.copyWith(floodCause: v)),
        ),
        if (x.floodCause == FloodCause.tropicalCyclone) ...[
          const SizedBox(height: SagipSpace.md),
          words(
            'cyclone',
            l10n.cycloneName,
            x.cycloneName,
            (v) => _details((x) => x.copyWith(cycloneName: v)),
          ),
          title(l10n.windSignalTitle),
          choose(
            const [1, 2, 3, 4, 5],
            x.windSignal,
            l10n.windSignalLabel,
            (v) => _details((x) => x.copyWith(windSignal: v)),
          ),
        ],
        title(l10n.floodLevelTitle),
        choose(
          FloodLevel.values,
          x.floodLevel,
          (v) => l10n.floodLevelLabel(v.name),
          (v) => _details((x) => x.copyWith(floodLevel: v)),
        ),
        title(l10n.floodStatusTitle),
        choose(
          FloodStatus.values,
          x.floodStatus,
          (v) => l10n.floodStatusLabel(v.name),
          (v) => _details((x) => x.copyWith(floodStatus: v)),
        ),
      ],
      if (type == 'fire') ...[
        title(l10n.fireKindTitle),
        choose(
          FireKind.values,
          x.fireKind,
          (v) => l10n.fireKindLabel(v.name),
          (v) => _details((x) => x.copyWith(fireKind: v)),
        ),
        title(l10n.highestAlarmTitle),
        choose(
          [
            for (final s in FireStage.values)
              if (s.isAlarm && s != FireStage.positiveAlarm) s,
          ],
          x.highestAlarm,
          (v) => l10n.fireStageName(v.name),
          (v) => _details((x) => x.copyWith(highestAlarm: v)),
        ),
        const SizedBox(height: SagipSpace.lg),
        Row(
          children: [
            Expanded(
              child: number(
                'damage_php',
                l10n.estimatedDamage,
                x.estimatedDamage,
                (v) => _details((x) => x.copyWith(estimatedDamage: v)),
              ),
            ),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: number(
                'individuals',
                l10n.affectedIndividuals,
                x.affectedIndividuals,
                (v) => _details((x) => x.copyWith(affectedIndividuals: v)),
              ),
            ),
          ],
        ),
      ],
    ];

    final minPhotos = minimumCrewPhotos(type);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.completeTitle)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SagipSpace.xl),
              children: [
                Text(a.address ?? a.place, style: text.titleLarge),
                Text(
                  l10n.timeOnScene(minutes),
                  style: text.bodyMedium!.copyWith(
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: SagipSpace.xl),
                Text(l10n.outcome, style: text.titleMedium),
                const SizedBox(height: SagipSpace.sm),
                choose(
                  RescueOutcome.values,
                  d.outcome,
                  l10n.outcomeLabel,
                  (o) => _update((d) => d.copyWith(outcome: o)),
                ),
                const SizedBox(height: SagipSpace.xl),
                Text(l10n.personsAssisted, style: text.titleMedium),
                const SizedBox(height: SagipSpace.sm),
                Counter(
                  value: d.persons ?? 0,
                  label: l10n.peopleCount(d.persons ?? 0),
                  onChanged: (v) => _update((d) => d.copyWith(persons: v)),
                ),
                const SizedBox(height: SagipSpace.xxl),
                Text(l10n.ragTitle, style: text.titleLarge),
                const SizedBox(height: SagipSpace.xs),
                Text(
                  l10n.ragHint,
                  style: text.bodyMedium!.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: SagipSpace.md),
                words(
                  'what_happened',
                  l10n.ragNotesLabel,
                  d.whatHappened,
                  (v) => _update((d) => d.copyWith(whatHappened: v)),
                  maxLines: 4,
                ),
                const SizedBox(height: SagipSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('rag-fill'),
                    onPressed: _filling ? null : _fillFromNotes,
                    icon: _filling
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.auto_awesome_rounded),
                    label: Text(_filling ? l10n.ragWorking : l10n.ragButton),
                  ),
                ),
                if (_fillMessage != null) ...[
                  const SizedBox(height: SagipSpace.sm),
                  Text(
                    _fillMessage!,
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  ),
                ],
                if (d.narrative.isNotEmpty || d.filledByRag) ...[
                  const SizedBox(height: SagipSpace.md),
                  words(
                    'narrative',
                    l10n.narrativeLabel,
                    d.narrative,
                    (v) => _update((d) => d.copyWith(narrative: v)),
                    maxLines: 5,
                  ),
                ],
                if (form.isNotEmpty) ...[
                  const SizedBox(height: SagipSpace.xxl),
                  Text(l10n.crewFormTitle(type ?? ''), style: text.titleLarge),
                  const SizedBox(height: SagipSpace.xs),
                  Text(
                    l10n.crewFormHint,
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  ),
                  ...form,
                ],
                const SizedBox(height: SagipSpace.xl),
                Text(l10n.damageTitle, style: text.titleMedium),
                const SizedBox(height: SagipSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: number(
                        'houses',
                        l10n.housesDamaged,
                        d.houses,
                        (v) => _update((d) => d.copyWith(houses: v)),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: number(
                        'injured',
                        l10n.injured,
                        d.injured,
                        (v) => _update((d) => d.copyWith(injured: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SagipSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: number(
                        'missing',
                        l10n.missing,
                        d.missing,
                        (v) => _update((d) => d.copyWith(missing: v)),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: number(
                        'families',
                        l10n.affectedFamilies,
                        d.families,
                        (v) => _update((d) => d.copyWith(families: v)),
                      ),
                    ),
                  ],
                ),
                title(l10n.crewPhotosTitle),
                Text(
                  [
                    l10n.crewPhotosHint(minPhotos),
                    if (type == 'medical') l10n.crewPhotosPcr,
                  ].join(' '),
                  style: text.bodyMedium!.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: SagipSpace.md),
                Wrap(
                  spacing: SagipSpace.sm,
                  runSpacing: SagipSpace.sm,
                  children: [
                    for (var i = 0; i < d.photos.length; i++)
                      _Thumb(
                        jpeg: d.photos[i],
                        removeLabel: l10n.photoRemove,
                        onRemove: () => _update(
                          (d) => d.copyWith(photos: [...d.photos]..removeAt(i)),
                        ),
                      ),
                    if (d.photos.length < maxCrewPhotos)
                      OutlinedButton.icon(
                        key: const ValueKey('crew-photo-add'),
                        onPressed: _addPhoto,
                        icon: const Icon(Symbols.add_a_photo_rounded),
                        label: Text(l10n.photoAdd),
                      ),
                  ],
                ),
                const SizedBox(height: SagipSpace.lg),
                words(
                  'notes',
                  l10n.reportNotes,
                  d.notes,
                  (v) => _update((d) => d.copyWith(notes: v)),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            SagipSpace.sm,
            SagipSpace.xl,
            SagipSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Next to the button, so it is seen on a long form.
              if (_error != null) ...[
                Text(
                  _error!,
                  style: text.bodyMedium!.copyWith(color: p.critical.text),
                ),
                const SizedBox(height: SagipSpace.sm),
              ],
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Symbols.send_rounded),
                  label: Text(l10n.submitReport),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One patient on an EMR report: name (optional), age, gender, receiving
/// hospital, chief complaint, remarks.
class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.index,
    required this.patient,
    required this.field,
    required this.onChanged,
  });

  final int index;
  final PatientRecord patient;
  final TextEditingController Function(String key, String initial) field;
  final void Function(PatientRecord Function(PatientRecord p)) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);

    TextField words(
      String key,
      String label,
      String? value,
      void Function(String) set,
    ) => TextField(
      controller: field('p$index-$key', value ?? ''),
      maxLength: 100,
      buildCounter: (
        _, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => null,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(labelText: label),
      onChanged: set,
    );

    return Container(
      margin: const EdgeInsets.only(top: SagipSpace.md),
      padding: const EdgeInsets.all(SagipSpace.lg),
      decoration: BoxDecoration(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(SagipRadius.card),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.patientHeading(index + 1), style: text.titleSmall),
          const SizedBox(height: SagipSpace.sm),
          words(
            'name',
            l10n.patientName,
            patient.name,
            (v) => onChanged((p) => p.copyWith(name: v)),
          ),
          const SizedBox(height: SagipSpace.md),
          DropdownButtonFormField<AgeBracket>(
            // Redrawn when the value changes from outside (Fill from notes).
            key: ValueKey('p$index-age-${patient.age}'),
            initialValue: patient.age,
            decoration: InputDecoration(labelText: l10n.patientAge),
            items: [
              for (final a in AgeBracket.values)
                DropdownMenuItem(
                  value: a,
                  child: Text(l10n.ageBracketLabel(a.name)),
                ),
            ],
            onChanged: (a) => onChanged((p) => p.copyWith(age: a)),
          ),
          const SizedBox(height: SagipSpace.md),
          Text(l10n.patientGender, style: text.labelLarge),
          const SizedBox(height: SagipSpace.xs),
          Wrap(
            spacing: SagipSpace.sm,
            children: [
              for (final g in PatientGender.values)
                ChoiceChip(
                  label: Text(l10n.genderLabel(g.name)),
                  selected: patient.gender == g,
                  onSelected: (_) => onChanged((p) => p.copyWith(gender: g)),
                ),
            ],
          ),
          const SizedBox(height: SagipSpace.md),
          DropdownButtonFormField<String>(
            key: ValueKey('p$index-hospital-${patient.hospital}'),
            initialValue: patient.hospital,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.patientHospital),
            items: [
              for (final h in receivingHospitals)
                DropdownMenuItem(
                  value: h,
                  child: Text(h, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (h) => onChanged((p) => p.copyWith(hospital: h)),
          ),
          const SizedBox(height: SagipSpace.md),
          words(
            'complaint',
            l10n.patientComplaint,
            patient.chiefComplaint,
            (v) => onChanged((p) => p.copyWith(chiefComplaint: v)),
          ),
          const SizedBox(height: SagipSpace.md),
          words(
            'remarks',
            l10n.patientRemarks,
            patient.remarks,
            (v) => onChanged((p) => p.copyWith(remarks: v)),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.jpeg,
    required this.removeLabel,
    required this.onRemove,
  });

  final Uint8List jpeg;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(SagipRadius.chip),
        child: Image.memory(jpeg, width: 72, height: 72, fit: BoxFit.cover),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: removeLabel,
          onPressed: onRemove,
          icon: const Icon(Symbols.close_rounded, size: 16),
        ),
      ),
    ],
  );
}
