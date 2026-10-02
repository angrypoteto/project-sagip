import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

// The setting groups on A3 Configuration besides the priority weights:
// numbers with Save and Discard, switches that apply at once, text, and
// simulation mode. Each value is checked here with the same rules as the
// database (`checkSetting`), which checks again and audits the change.

String _plain(num? v) => v == null
    ? ''
    : (v == v.roundToDouble() ? v.round().toString() : v.toString());

Map<String, AppSetting> _byKey(List<AppSetting> settings) => {
  for (final s in settings) s.key: s,
};

/// A group of number settings with their own Save and Discard.
class NumberSettingsCard extends ConsumerStatefulWidget {
  const NumberSettingsCard({
    super.key,
    required this.id,
    required this.title,
    required this.note,
    required this.labels,
    required this.settings,
    this.pairProblem,
  });

  /// Names the buttons (`save-<id>`) and the unsaved-changes entry.
  final String id;
  final String title;
  final String note;

  /// Setting key to its label, in the order shown.
  final Map<String, String> labels;
  final List<AppSetting> settings;

  /// Shown on both fields when a value breaks a [SettingKeys.pairs] rule.
  final String? pairProblem;

  @override
  ConsumerState<NumberSettingsCard> createState() => _NumberSettingsCardState();
}

class _NumberSettingsCardState extends ConsumerState<NumberSettingsCard> {
  final _fields = <String, TextEditingController>{};
  late final UnsavedChanges _unsaved;
  var _busy = false;
  var _syncing = false;

  Map<String, AppSetting> get _saved => _byKey(widget.settings);

  Iterable<String> get _keys =>
      widget.labels.keys.where((k) => _saved[k]?.value is num);

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(unsavedChangesProvider);
    for (final key in widget.labels.keys) {
      final value = _saved[key]?.value;
      _fields[key] = TextEditingController(
        text: _plain(value is num ? value : null),
      )..addListener(_changed);
    }
  }

  void _changed() {
    // Text set while the widget rebuilds (new values from the server) is
    // already part of that build.
    if (_syncing) return;
    _unsaved.set(widget.id, dirty: _dirty);
    setState(() {});
  }

  @override
  void didUpdateWidget(NumberSettingsCard old) {
    super.didUpdateWidget(old);
    // Another admin saved: take the new values unless this one is editing.
    final before = _byKey(old.settings);
    _syncing = true;
    for (final key in _keys) {
      final was = _plain(before[key]?.value as num?);
      final now = _plain(_saved[key]!.number);
      if (was != now && _fields[key]!.text == was) _fields[key]!.text = now;
    }
    _syncing = false;
    _unsaved.set(widget.id, dirty: _dirty);
  }

  @override
  void dispose() {
    _unsaved.set(widget.id, dirty: false);
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  num? _draft(String key) => num.tryParse(_fields[key]!.text.trim());

  bool get _dirty => _keys.any((k) => _draft(k) != _saved[k]!.value);

  /// The settings as they would be after saving.
  Map<String, AppSetting> get _draftSettings => {
    for (final s in widget.settings)
      s.key: _fields.containsKey(s.key) && _draft(s.key) != null
          ? s.copyWith(value: _draft(s.key))
          : s,
  };

  String? _problem(String key, AppLocalizations l10n) {
    final s = _saved[key]!;
    final v = _draft(key);
    if (v == null) return l10n.settingNotNumber;
    final range = l10n.settingOutOfRange(_plain(s.min), _plain(s.max));
    if ((s.min != null && v < s.min!) || (s.max != null && v > s.max!)) {
      return range;
    }
    return checkSetting(_draftSettings, key, v) == null
        ? null
        : (widget.pairProblem ?? range);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final changed = {
      for (final k in _keys)
        if (_draft(k) != _saved[k]!.value) k: _draft(k)!,
    };
    // A warning must stay at or below its critical value after every
    // single step: raise the critical one first, or lower the warning first.
    final order = changed.keys.toList();
    for (final (low, high) in SettingKeys.pairs) {
      if (!changed.containsKey(low) || !changed.containsKey(high)) continue;
      final highFirst = changed[high]! >= _saved[low]!.number;
      order
        ..remove(low)
        ..remove(high)
        ..addAll(highFirst ? [high, low] : [low, high]);
    }
    setState(() => _busy = true);
    await runAction(context, () async {
      for (final key in order) {
        await repo.set(key, changed[key]!);
      }
    }, success: l10n.settingsSaved);
    if (mounted) setState(() => _busy = false);
  }

  void _discard() {
    for (final key in _keys) {
      _fields[key]!.text = _plain(_saved[key]!.number);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final online = ref.watch(isOnlineProvider);
    if (_keys.isEmpty) return const SizedBox.shrink();
    final problems = {for (final k in _keys) k: _problem(k, l10n)};
    final valid = problems.values.every((e) => e == null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(widget.note, style: text.bodySmall),
            const SizedBox(height: SagipSpace.lg),
            for (final key in _keys)
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
                            Text(widget.labels[key]!, style: text.bodyLarge),
                            Text(
                              l10n.settingRange(
                                _plain(_saved[key]!.min),
                                _plain(_saved[key]!.max),
                              ),
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
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                        style: text.bodyLarge!.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          labelText: widget.labels[key],
                          errorText: problems[key],
                          errorMaxLines: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!online)
              Text(
                l10n.offlineActionsDisabled,
                style: text.bodySmall!.copyWith(color: p.warning.text),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: ValueKey('discard-${widget.id}'),
                  onPressed: _dirty && !_busy ? _discard : null,
                  child: Text(l10n.discardChanges),
                ),
                const SizedBox(width: SagipSpace.sm),
                FilledButton(
                  key: ValueKey('save-${widget.id}'),
                  onPressed: online && valid && _dirty && !_busy ? _save : null,
                  child: Text(l10n.saveChanges),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One switch on a [SwitchSettingsCard].
typedef SettingSwitch = ({String key, String label, String caption});

/// A group of switches. A switch applies as soon as it is flipped (and is
/// audited); there is nothing to save.
class SwitchSettingsCard extends ConsumerStatefulWidget {
  const SwitchSettingsCard({
    super.key,
    required this.title,
    required this.note,
    required this.switches,
    required this.settings,
    this.below,
  });

  final String title;
  final String note;
  final List<SettingSwitch> switches;
  final List<AppSetting> settings;

  /// Extra content under the switches (the simulation tools).
  final Widget? below;

  @override
  ConsumerState<SwitchSettingsCard> createState() => _SwitchSettingsCardState();
}

class _SwitchSettingsCardState extends ConsumerState<SwitchSettingsCard> {
  String? _busyKey;

  Future<void> _set(String key, bool value) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyKey = key);
    await runAction(
      context,
      () => ref.read(settingsRepositoryProvider).set(key, value),
      success: l10n.settingsSaved,
    );
    if (mounted) setState(() => _busyKey = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final online = ref.watch(isOnlineProvider);
    final saved = _byKey(widget.settings);
    final shown = [
      for (final s in widget.switches)
        if (saved[s.key]?.value is bool) s,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(widget.note, style: text.bodySmall),
            const SizedBox(height: SagipSpace.sm),
            for (final s in shown)
              SwitchListTile(
                key: ValueKey('switch-${s.key}'),
                contentPadding: EdgeInsets.zero,
                title: Text(s.label, style: text.bodyLarge),
                subtitle: Text(s.caption, style: text.bodySmall),
                value: saved[s.key]!.flag,
                onChanged: online && _busyKey == null
                    ? (v) => _set(s.key, v)
                    : null,
              ),
            ?widget.below,
          ],
        ),
      ),
    );
  }
}

/// One field on a [TextSettingsCard].
typedef SettingText = ({String key, String label, String hint, String problem});

/// A group of text settings (the hotline and the SMS gateway number) with
/// Save and Discard.
class TextSettingsCard extends ConsumerStatefulWidget {
  const TextSettingsCard({
    super.key,
    required this.id,
    required this.title,
    required this.note,
    required this.fields,
    required this.settings,
  });

  final String id;
  final String title;
  final String note;
  final List<SettingText> fields;
  final List<AppSetting> settings;

  @override
  ConsumerState<TextSettingsCard> createState() => _TextSettingsCardState();
}

class _TextSettingsCardState extends ConsumerState<TextSettingsCard> {
  final _fields = <String, TextEditingController>{};
  late final UnsavedChanges _unsaved;
  var _busy = false;
  var _syncing = false;

  Map<String, AppSetting> get _saved => _byKey(widget.settings);

  Iterable<SettingText> get _shown =>
      widget.fields.where((f) => _saved[f.key]?.value is String);

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(unsavedChangesProvider);
    for (final f in widget.fields) {
      final value = _saved[f.key]?.value;
      _fields[f.key] = TextEditingController(text: value is String ? value : '')
        ..addListener(_changed);
    }
  }

  void _changed() {
    // Text set while the widget rebuilds (new values from the server) is
    // already part of that build.
    if (_syncing) return;
    _unsaved.set(widget.id, dirty: _dirty);
    setState(() {});
  }

  @override
  void didUpdateWidget(TextSettingsCard old) {
    super.didUpdateWidget(old);
    // After a save, show the value as the database keeps it (the gateway
    // number becomes +639...).
    _syncing = true;
    for (final f in _shown) {
      final now = _saved[f.key]!.text;
      final field = _fields[f.key]!;
      if (field.text != now && _draft(f.key) == now) field.text = now;
    }
    _syncing = false;
    _unsaved.set(widget.id, dirty: _dirty);
  }

  @override
  void dispose() {
    _unsaved.set(widget.id, dirty: false);
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// What is typed, as it would be stored.
  String _draft(String key) =>
      normalizeSetting(key, _fields[key]!.text) as String;

  bool _changedKey(String key) => _draft(key) != _saved[key]!.value;

  bool get _dirty => _shown.any((f) => _changedKey(f.key));

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(settingsRepositoryProvider);
    final changed = [
      for (final f in _shown)
        if (_changedKey(f.key)) f.key,
    ];
    setState(() => _busy = true);
    await runAction(context, () async {
      for (final key in changed) {
        await repo.set(key, _fields[key]!.text);
      }
    }, success: l10n.settingsSaved);
    if (mounted) setState(() => _busy = false);
  }

  void _discard() {
    for (final f in _shown) {
      _fields[f.key]!.text = _saved[f.key]!.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final online = ref.watch(isOnlineProvider);
    if (_shown.isEmpty) return const SizedBox.shrink();
    final problems = {
      for (final f in _shown)
        f.key: checkSetting(_saved, f.key, _fields[f.key]!.text) == null
            ? null
            : f.problem,
    };
    final valid = problems.values.every((e) => e == null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(widget.note, style: text.bodySmall),
            const SizedBox(height: SagipSpace.lg),
            for (final f in _shown)
              Padding(
                padding: const EdgeInsets.only(bottom: SagipSpace.md),
                child: TextField(
                  key: ValueKey('setting-${f.key}'),
                  controller: _fields[f.key],
                  enabled: online && !_busy,
                  keyboardType: TextInputType.phone,
                  style: text.bodyLarge!.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    labelText: f.label,
                    hintText: f.hint,
                    errorText: problems[f.key],
                    errorMaxLines: 2,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: ValueKey('discard-${widget.id}'),
                  onPressed: _dirty && !_busy ? _discard : null,
                  child: Text(l10n.discardChanges),
                ),
                const SizedBox(width: SagipSpace.sm),
                FilledButton(
                  key: ValueKey('save-${widget.id}'),
                  onPressed: online && valid && _dirty && !_busy ? _save : null,
                  child: Text(l10n.saveChanges),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Simulation mode (plan section 12): the switch, and while it is on,
/// simulated PAGASA readings. The threshold engine treats them like any
/// reading; the alerts they raise are marked simulated and are never
/// texted or posted.
class SimulationCard extends ConsumerStatefulWidget {
  const SimulationCard({super.key, required this.settings});

  final List<AppSetting> settings;

  @override
  ConsumerState<SimulationCard> createState() => _SimulationCardState();
}

class _SimulationCardState extends ConsumerState<SimulationCard> {
  var _busy = false;

  Future<void> _send({
    required int signal,
    required double rain,
    double? surge,
  }) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref
          .read(simulationRepositoryProvider)
          .simulateWeather(
            signal: signal,
            rainfallMmPerHour: rain,
            surgeMeters: surge,
          ),
      success: l10n.simulationSent,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final online = ref.watch(isOnlineProvider);
    final on = _byKey(widget.settings)[SettingKeys.simulation]?.value == true;
    final ready = on && online && !_busy;

    return SwitchSettingsCard(
      title: l10n.configSimulationTitle,
      note: l10n.configSimulationNote,
      switches: [
        (
          key: SettingKeys.simulation,
          label: l10n.simulationSwitch,
          caption: on ? l10n.simulationOnCaption : l10n.simulationOffCaption,
        ),
      ],
      settings: widget.settings,
      below: Padding(
        padding: const EdgeInsets.only(top: SagipSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.simulateTitle, style: text.titleSmall),
            const SizedBox(height: SagipSpace.sm),
            Wrap(
              spacing: SagipSpace.sm,
              runSpacing: SagipSpace.sm,
              children: [
                OutlinedButton(
                  key: const ValueKey('simulate-typhoon'),
                  onPressed: ready
                      ? () => _send(signal: 3, rain: 35, surge: 2.5)
                      : null,
                  child: Text(l10n.simulateTyphoon),
                ),
                OutlinedButton(
                  key: const ValueKey('simulate-rain'),
                  onPressed: ready ? () => _send(signal: 0, rain: 22) : null,
                  child: Text(l10n.simulateRain),
                ),
                OutlinedButton(
                  key: const ValueKey('simulate-calm'),
                  onPressed: ready ? () => _send(signal: 0, rain: 2) : null,
                  child: Text(l10n.simulateCalm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
