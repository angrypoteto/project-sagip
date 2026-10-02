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
import 'settings_cards.dart';

/// A3 Configuration (admin, plan 7.4): the Triage Queue priority weights
/// with a live preview of the ranking, alert thresholds, the crowd report
/// limit, alert channels, the numbers the apps show, simulation mode, and
/// the thesis's algorithm parameters read-only. Every saved change is
/// audited by the database (FR11). The router asks before leaving the page
/// with unsaved changes.
class ConfigurationPage extends ConsumerWidget {
  const ConfigurationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PageFrame(
      title: l10n.navSettings,
      subtitle: l10n.configSubtitle,
      child: AsyncBody(
        value: ref.watch(settingsProvider),
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(icon: Symbols.tune_rounded, title: l10n.errorGeneric),
        builder: (settings) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PriorityEditor(settings: settings),
            const SizedBox(height: SagipSpace.xl),
            NumberSettingsCard(
              id: 'alerts',
              title: l10n.configAlertsTitle,
              note: l10n.configAlertsNote,
              labels: {
                SettingKeys.rainfallWarning: l10n.settingRainfallWarning,
                SettingKeys.rainfallCritical: l10n.settingRainfallCritical,
                SettingKeys.signalWarning: l10n.settingSignalWarning,
                SettingKeys.signalCritical: l10n.settingSignalCritical,
                SettingKeys.surgeWarning: l10n.settingSurgeWarning,
                SettingKeys.surgeCritical: l10n.settingSurgeCritical,
              },
              pairProblem: l10n.settingWarningAboveCritical,
              settings: settings,
            ),
            const SizedBox(height: SagipSpace.xl),
            SwitchSettingsCard(
              title: l10n.configChannelsTitle,
              note: l10n.configChannelsNote,
              switches: [
                (
                  key: SettingKeys.pushChannel,
                  label: l10n.channelPush,
                  caption: l10n.channelPushNote,
                ),
                (
                  key: SettingKeys.smsChannel,
                  label: l10n.channelSmsSetting,
                  caption: l10n.channelSmsNote,
                ),
                (
                  key: SettingKeys.facebookChannel,
                  label: l10n.channelFacebook,
                  caption: l10n.channelFacebookNote,
                ),
              ],
              settings: settings,
            ),
            const SizedBox(height: SagipSpace.xl),
            NumberSettingsCard(
              id: 'sms-cap',
              title: l10n.configSmsCapTitle,
              note: l10n.configSmsCapNote,
              labels: {SettingKeys.smsDailyCap: l10n.settingSmsDailyCap},
              settings: settings,
            ),
            const SizedBox(height: SagipSpace.xl),
            NumberSettingsCard(
              id: 'reports',
              title: l10n.configReportsTitle,
              note: l10n.configReportsNote,
              labels: {SettingKeys.reportsPerHour: l10n.settingReportsPerHour},
              settings: settings,
            ),
            const SizedBox(height: SagipSpace.xl),
            TextSettingsCard(
              id: 'contact',
              title: l10n.configContactTitle,
              note: l10n.configContactNote,
              fields: [
                (
                  key: SettingKeys.hotline,
                  label: l10n.settingHotline,
                  hint: l10n.settingHotlineHint,
                  problem: l10n.settingHotlineError,
                ),
                (
                  key: SettingKeys.smsGateway,
                  label: l10n.settingGateway,
                  hint: l10n.settingGatewayHint,
                  problem: l10n.settingGatewayError,
                ),
              ],
              settings: settings,
            ),
            const SizedBox(height: SagipSpace.xl),
            SimulationCard(settings: settings),
            const SizedBox(height: SagipSpace.xl),
            const _AlgorithmCard(),
          ],
        ),
      ),
    );
  }
}

class _PriorityEditor extends ConsumerStatefulWidget {
  const _PriorityEditor({required this.settings});

  final List<AppSetting> settings;

  @override
  ConsumerState<_PriorityEditor> createState() => _PriorityEditorState();
}

class _PriorityEditorState extends ConsumerState<_PriorityEditor> {
  final _fields = <String, TextEditingController>{};
  late final UnsavedChanges _unsaved;
  var _busy = false;
  var _syncing = false;

  Map<String, AppSetting> get _saved => {
    for (final s in widget.settings) s.key: s,
  };

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(unsavedChangesProvider);
    for (final key in PriorityRules.settingKeys) {
      _fields[key] = TextEditingController(text: _savedText(key))
        ..addListener(_changed);
    }
  }

  String _savedText(String key) {
    final value = _saved[key]?.value;
    return _plain(value is num ? value : null);
  }

  void _changed() {
    // Text set while the widget rebuilds is already part of that build.
    if (_syncing) return;
    _unsaved.set('priority', dirty: _dirty);
    setState(() {});
  }

  @override
  void didUpdateWidget(_PriorityEditor old) {
    super.didUpdateWidget(old);
    // Another admin saved: take the new values unless this one is editing.
    final before = {for (final s in old.settings) s.key: s.value};
    _syncing = true;
    for (final key in PriorityRules.settingKeys) {
      final was = before[key];
      final wasText = _plain(was is num ? was : null);
      final now = _savedText(key);
      if (wasText != now && _fields[key]!.text == wasText) {
        _fields[key]!.text = now;
      }
    }
    _syncing = false;
    _unsaved.set('priority', dirty: _dirty);
  }

  @override
  void dispose() {
    _unsaved.set('priority', dirty: false);
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _plain(num? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.round().toString() : v.toString());

  /// Null for a value that is not a number, and for settings this editor
  /// has no field for (other groups share the table).
  num? _draftValue(String key) {
    final field = _fields[key];
    return field == null ? null : num.tryParse(field.text.trim());
  }

  bool get _dirty =>
      PriorityRules.settingKeys.any((k) => _draftValue(k) != _saved[k]?.value);

  /// The settings as they would be after saving.
  Map<String, AppSetting> get _draft => {
    for (final s in widget.settings)
      s.key: _draftValue(s.key) == null
          ? s
          : s.copyWith(value: _draftValue(s.key)),
  };

  String? _problem(String key, AppLocalizations l10n) {
    final s = _saved[key];
    final v = _draftValue(key);
    if (s == null) return null;
    if (v == null) return l10n.settingNotNumber;
    return switch (checkSetting(_draft, key, v)) {
      null => null,
      _ when key == 'priority.high_at' || key == 'priority.critical_at' =>
        (s.min != null && v < s.min!) || (s.max != null && v > s.max!)
            ? l10n.settingOutOfRange(_plain(s.min), _plain(s.max))
            : l10n.settingHighAboveCritical,
      _ => l10n.settingOutOfRange(_plain(s.min), _plain(s.max)),
    };
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final changed = [
      for (final k in PriorityRules.settingKeys)
        if (_draftValue(k) != _saved[k]?.value) k,
    ];
    // Keep High at or below Critical after every single step: raise
    // Critical before High, lower High before Critical.
    final newCritical = _draftValue('priority.critical_at');
    final oldHigh = _saved['priority.high_at']?.value;
    final criticalFirst =
        newCritical != null && oldHigh is num && newCritical >= oldHigh;
    changed.sort((a, b) {
      int rank(String k) => switch (k) {
        'priority.critical_at' => criticalFirst ? 0 : 2,
        'priority.high_at' => criticalFirst ? 2 : 0,
        _ => 1,
      };
      return rank(a).compareTo(rank(b));
    });
    setState(() => _busy = true);
    await runAction(context, () async {
      for (final k in changed) {
        await repo.set(k, _draftValue(k)!);
      }
    }, success: l10n.settingsSaved);
    if (mounted) setState(() => _busy = false);
  }

  void _discard() {
    for (final key in PriorityRules.settingKeys) {
      _fields[key]!.text = _savedText(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final online = ref.watch(isOnlineProvider);
    final problems = {
      for (final k in PriorityRules.settingKeys) k: _problem(k, l10n),
    };
    final valid = problems.values.every((e) => e == null);
    final canSave = online && valid && _dirty && !_busy;

    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.configPriorityTitle, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.provisionalRules, style: text.bodySmall),
            const SizedBox(height: SagipSpace.lg),
            for (final key in PriorityRules.settingKeys)
              if (_saved[key] case final s?)
                Padding(
                  padding: const EdgeInsets.only(bottom: SagipSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: SagipSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_label(l10n, key), style: text.bodyLarge),
                              Text(
                                l10n.settingRange(_plain(s.min), _plain(s.max)),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: SagipSpace.lg),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          key: ValueKey('setting-$key'),
                          controller: _fields[key],
                          enabled: online && !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          style: text.bodyLarge!.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          decoration: InputDecoration(
                            labelText: _label(l10n, key),
                            errorText: problems[key],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            if (_lastChange(widget.settings) case final s?)
              Text(
                l10n.settingLastChanged(s.updatedBy!),
                style: text.bodySmall,
              ),
            if (!online) ...[
              const SizedBox(height: SagipSpace.sm),
              Text(
                l10n.offlineActionsDisabled,
                style: text.bodySmall!.copyWith(color: p.warning.text),
              ),
            ],
            const SizedBox(height: SagipSpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _dirty && !_busy ? _discard : null,
                  child: Text(l10n.discardChanges),
                ),
                const SizedBox(width: SagipSpace.sm),
                FilledButton(
                  key: const ValueKey('save-priority'),
                  onPressed: canSave ? _save : null,
                  child: Text(l10n.saveChanges),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final rules = valid
        ? PriorityRules.fromSettings(_draft.values)
        : ref.watch(priorityRulesProvider);
    final preview = _Preview(rules: rules);

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 1000
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(width: SagipSpace.xl),
                Expanded(child: preview),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                form,
                const SizedBox(height: SagipSpace.xl),
                preview,
              ],
            ),
    );
  }

  static AppSetting? _lastChange(List<AppSetting> settings) {
    AppSetting? last;
    for (final s in settings) {
      if (s.updatedBy == null || s.updatedAt == null) continue;
      if (last == null || s.updatedAt!.isAfter(last.updatedAt!)) last = s;
    }
    return last;
  }

  static String _label(AppLocalizations l10n, String key) => switch (key) {
    'priority.sos' => l10n.settingSos,
    'priority.cluster' => l10n.settingCluster,
    'priority.vulnerable' => l10n.settingVulnerable,
    'priority.waiting_per_minute' => l10n.settingWaitingPerMinute,
    'priority.waiting_max' => l10n.settingWaitingMax,
    'priority.mock_location' => l10n.settingMockLocation,
    'priority.critical_at' => l10n.settingCriticalAt,
    'priority.high_at' => l10n.settingHighAt,
    _ => key,
  };
}

/// The live preview (plan 7.4 A3): the active incidents ranked now with
/// the values being edited.
class _Preview extends ConsumerWidget {
  const _Preview({required this.rules});

  final PriorityRules rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final incidents = ref.watch(activeIncidentsProvider).value ?? const [];
    final ranked = rules.order(incidents, now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.previewTitle, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.previewNote, style: text.bodySmall),
            const SizedBox(height: SagipSpace.lg),
            if (ranked.isEmpty)
              Text(l10n.previewEmpty, style: text.bodyMedium)
            else
              for (final (n, i) in ranked.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: SagipSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${n + 1}',
                          style: text.titleSmall!.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.incidentTitle(i),
                              style: text.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${i.id} · ${i.barangay}, ${i.district}',
                              style: text.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: SagipSpace.sm),
                      _ScoreChip(breakdown: rules.score(i, now), p: p),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.breakdown, required this.p});

  final PriorityBreakdown breakdown;
  final SagipPalette p;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SagipChip(
      label:
          '${l10n.severity(breakdown.severity)}, '
          '${l10n.points(breakdown.total.round())}',
      tone: switch (breakdown.severity) {
        Severity.critical => p.critical,
        Severity.high => p.warning,
        Severity.normal => p.neutral,
      },
    );
  }
}

/// The thesis's algorithm parameters, read-only (CLAUDE.md: do not change
/// without team agreement).
class _AlgorithmCard extends ConsumerWidget {
  const _AlgorithmCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final router = ref.watch(roadRouterProvider).value;
    final rows = [
      (l10n.algDbscan, l10n.algDbscanValue),
      (
        l10n.algDijkstra,
        router == null
            ? l10n.algDijkstraLoading
            : l10n.algDijkstraValue(
                router.graph.nodeCount,
                router.graph.edgeCount,
                dateOnly(router.graph.built),
              ),
      ),
      (l10n.algSpeeds, l10n.algSpeedsValue),
      (l10n.algLstm, l10n.algLstmValue),
      (l10n.algKde, l10n.algKdeValue),
      (l10n.algClassifier, l10n.algClassifierValue),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.algorithmsTitle, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.algorithmsNote, style: text.bodySmall),
            const SizedBox(height: SagipSpace.lg),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: SagipSpace.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 240,
                      child: Text(label, style: text.bodyMedium),
                    ),
                    Expanded(child: Text(value, style: text.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
