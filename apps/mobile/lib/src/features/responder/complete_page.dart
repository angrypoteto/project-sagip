import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/counter.dart';
import '../../common/labels.dart';
import '../../common/offline_banner.dart';
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
  });

  final String incidentId;
  final RescueOutcome? outcome;
  final int? persons;
  final int houses;
  final int injured;
  final int missing;
  final int families;
  final String notes;

  CompletionDraft copyWith({
    RescueOutcome? outcome,
    int? persons,
    int? houses,
    int? injured,
    int? missing,
    int? families,
    String? notes,
  }) => CompletionDraft(
    incidentId: incidentId,
    outcome: outcome ?? this.outcome,
    persons: persons ?? this.persons,
    houses: houses ?? this.houses,
    injured: injured ?? this.injured,
    missing: missing ?? this.missing,
    families: families ?? this.families,
    notes: notes ?? this.notes,
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

/// F6 Completion and damage report.
class CompletePage extends ConsumerStatefulWidget {
  const CompletePage({super.key});

  @override
  ConsumerState<CompletePage> createState() => _CompletePageState();
}

class _CompletePageState extends ConsumerState<CompletePage> {
  final _fields = <String, TextEditingController>{};
  String? _error;
  var _saving = false;

  TextEditingController _field(String key, String initial) =>
      _fields.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The saved draft for [a], or a new one started from what F5 recorded.
  CompletionDraft _draftFor(Assignment a, CompletionDraft? saved) =>
      saved != null && saved.incidentId == a.incidentId
      ? saved
      : CompletionDraft(
          incidentId: a.incidentId,
          outcome: a.realEmergency == false ? RescueOutcome.falseReport : null,
          persons: a.peopleFound ?? a.peopleCount,
        );

  Assignment? get _assignment => ref.read(responderProvider).value?.current;

  void _update(CompletionDraft Function(CompletionDraft d) change) {
    final a = _assignment;
    if (a == null) return;
    final base = _draftFor(a, ref.read(completionDraftProvider));
    ref.read(completionDraftProvider.notifier).update(change(base));
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final a = _assignment;
    if (a == null) return;
    final d = _draftFor(a, ref.read(completionDraftProvider));
    if (d.outcome == null) return setState(() => _error = l10n.chooseOutcome);
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
    final minutes = a.onSceneAt == null
        ? 0
        : now.difference(a.onSceneAt!).inMinutes.clamp(0, 9999);

    Widget number(
      String key,
      String label,
      int value,
      void Function(int) set,
    ) => TextField(
      controller: _field(key, '$value'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => set(int.tryParse(v) ?? 0),
    );

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
                Wrap(
                  spacing: SagipSpace.sm,
                  runSpacing: SagipSpace.sm,
                  children: [
                    for (final o in RescueOutcome.values)
                      ChoiceChip(
                        label: Text(l10n.outcomeLabel(o)),
                        selected: d.outcome == o,
                        onSelected: (_) {
                          setState(() => _error = null);
                          _update((d) => d.copyWith(outcome: o));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: SagipSpace.xl),
                Text(l10n.personsAssisted, style: text.titleMedium),
                const SizedBox(height: SagipSpace.sm),
                Counter(
                  value: d.persons ?? 0,
                  label: l10n.peopleCount(d.persons ?? 0),
                  onChanged: (v) => _update((d) => d.copyWith(persons: v)),
                ),
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
                const SizedBox(height: SagipSpace.md),
                TextField(
                  controller: _field('notes', d.notes),
                  maxLines: 3,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(labelText: l10n.reportNotes),
                  onChanged: (v) => _update((d) => d.copyWith(notes: v)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: SagipSpace.lg),
                  Text(
                    _error!,
                    style: text.bodyMedium!.copyWith(color: p.critical.text),
                  ),
                ],
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
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Symbols.send_rounded),
              label: Text(l10n.submitReport),
            ),
          ),
        ),
      ),
    );
  }
}
