import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// D10 "Issue an advisory" (FR6, FR14): an MDRRMD notice, or one relayed by
/// hand from PAGASA, PHIVOLCS, or EFCOS. Two steps: write it, then review
/// it as residents will see it, with where it goes, before it is sent.
/// Returns true once the advisory is issued.
Future<bool> showAdvisoryDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const _AdvisoryDialog(),
    ) ??
    false;

class _AdvisoryDialog extends ConsumerStatefulWidget {
  const _AdvisoryDialog();

  @override
  ConsumerState<_AdvisoryDialog> createState() => _AdvisoryDialogState();
}

class _AdvisoryDialogState extends ConsumerState<_AdvisoryDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _steps = TextEditingController();
  var _source = AlertSource.mdrrmd;
  var _level = AlertLevel.warning;
  var _everywhere = true;
  final _barangays = <String>{};
  var _checked = false;
  var _reviewing = false;
  var _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _steps.dispose();
    super.dispose();
  }

  List<String> get _guidance => AdvisoryRules.steps(_steps.text);

  String? _titleProblem(AppLocalizations l10n) =>
      _title.text.trim().isEmpty ? l10n.advisoryTitleError : null;

  String? _bodyProblem(AppLocalizations l10n) =>
      _body.text.trim().isEmpty ? l10n.advisoryBodyError : null;

  String? _stepsProblem(AppLocalizations l10n) {
    final steps = _guidance;
    return steps.length > AdvisoryRules.maxSteps ||
            steps.any((s) => s.length > AdvisoryRules.maxStep)
        ? l10n.advisoryStepsError(AdvisoryRules.maxSteps, AdvisoryRules.maxStep)
        : null;
  }

  bool get _areaMissing => !_everywhere && _barangays.isEmpty;

  void _review() {
    final l10n = AppLocalizations.of(context);
    setState(() => _checked = true);
    if (_titleProblem(l10n) != null ||
        _bodyProblem(l10n) != null ||
        _stepsProblem(l10n) != null ||
        _areaMissing) {
      return;
    }
    setState(() => _reviewing = true);
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref
          .read(alertLogRepositoryProvider)
          .issue(
            source: _source,
            level: _level,
            title: _title.text,
            body: _body.text,
            guidance: _guidance,
            barangays: _everywhere ? const [] : (_barangays.toList()..sort()),
          ),
      success: l10n.advisoryIssued,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop(true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(isOnlineProvider);
    return AlertDialog(
      title: Text(_reviewing ? l10n.advisoryReviewTitle : l10n.advisoryTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _reviewing ? _reviewStep(l10n) : _writeStep(l10n),
        ),
      ),
      actions: _reviewing
          ? [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _reviewing = false),
                child: Text(l10n.advisoryBack),
              ),
              FilledButton(
                key: const ValueKey('advisory-send'),
                onPressed: _busy || !online ? null : _send,
                child: Text(_busy ? l10n.working : l10n.advisorySend),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('advisory-review'),
                onPressed: _review,
                child: Text(l10n.advisoryReview),
              ),
            ],
    );
  }

  Widget _writeStep(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.advisoryFrom, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            for (final s in AlertSource.values)
              ChoiceChip(
                label: Text(l10n.alertSource(s)),
                selected: _source == s,
                onSelected: (_) => setState(() => _source = s),
              ),
          ],
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(l10n.advisoryLevel, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            for (final level in AlertLevel.values)
              ChoiceChip(
                key: ValueKey('advisory-level-${level.name}'),
                label: Text(l10n.alertLevel(level)),
                selected: _level == level,
                onSelected: (_) => setState(() => _level = level),
              ),
          ],
        ),
        const SizedBox(height: SagipSpace.lg),
        TextField(
          key: const ValueKey('advisory-title'),
          controller: _title,
          maxLength: AdvisoryRules.maxTitle,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.advisoryTitleLabel,
            errorText: _checked ? _titleProblem(l10n) : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: SagipSpace.sm),
        TextField(
          key: const ValueKey('advisory-body'),
          controller: _body,
          minLines: 3,
          maxLines: 6,
          maxLength: AdvisoryRules.maxBody,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.advisoryBodyLabel,
            alignLabelWithHint: true,
            errorText: _checked ? _bodyProblem(l10n) : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: SagipSpace.sm),
        TextField(
          key: const ValueKey('advisory-steps'),
          controller: _steps,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.advisoryStepsLabel,
            hintText: l10n.advisoryStepsHint,
            alignLabelWithHint: true,
            errorText: _checked ? _stepsProblem(l10n) : null,
            errorMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(l10n.advisoryArea, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            ChoiceChip(
              key: const ValueKey('advisory-everywhere'),
              label: Text(l10n.alertAllManila),
              selected: _everywhere,
              onSelected: (_) => setState(() => _everywhere = true),
            ),
            ChoiceChip(
              key: const ValueKey('advisory-some'),
              label: Text(l10n.advisoryChosenBarangays),
              selected: !_everywhere,
              onSelected: (_) => setState(() => _everywhere = false),
            ),
          ],
        ),
        if (!_everywhere) ...[
          const SizedBox(height: SagipSpace.sm),
          Wrap(
            spacing: SagipSpace.sm,
            runSpacing: SagipSpace.sm,
            children: [
              for (final b in sampleManilaBarangays)
                FilterChip(
                  label: Text(b.name),
                  selected: _barangays.contains(b.name),
                  onSelected: (on) => setState(
                    () =>
                        on ? _barangays.add(b.name) : _barangays.remove(b.name),
                  ),
                ),
            ],
          ),
          if (_checked && _areaMissing)
            Padding(
              padding: const EdgeInsets.only(top: SagipSpace.sm),
              child: Text(
                l10n.advisoryAreaError,
                style: text.bodySmall!.copyWith(color: p.critical.text),
              ),
            ),
        ],
      ],
    );
  }

  /// The advisory as residents will see it, and where it goes.
  Widget _reviewStep(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final settings = ref.watch(settingsProvider).value ?? const <AppSetting>[];
    bool on(String key) =>
        settings.where((s) => s.key == key).firstOrNull?.value == true;
    final simulated = on(SettingKeys.simulation);
    final others = [
      if (on(SettingKeys.pushChannel)) l10n.alertChannelPush,
      if (on(SettingKeys.smsChannel)) l10n.alertChannelSms,
      if (on(SettingKeys.facebookChannel)) l10n.alertChannelFacebook,
    ];
    final areas = _barangays.toList()..sort();
    final tone = switch (_level) {
      AlertLevel.critical => p.critical,
      AlertLevel.warning => p.warning,
      AlertLevel.info => p.info,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.panelRaised,
            borderRadius: BorderRadius.circular(SagipRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: SagipSpace.sm,
                  children: [
                    SagipChip(
                      label: l10n.alertLevel(_level),
                      tone: tone,
                      icon: switch (_level) {
                        AlertLevel.critical => Symbols.warning_rounded,
                        AlertLevel.warning => Symbols.error_rounded,
                        AlertLevel.info => Symbols.info_rounded,
                      },
                    ),
                    SagipChip(
                      label: l10n.alertSource(_source),
                      tone: p.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: SagipSpace.sm),
                Text(_title.text.trim(), style: text.titleMedium),
                const SizedBox(height: SagipSpace.xs),
                Text(_body.text.trim(), style: text.bodyMedium),
                for (final step in _guidance)
                  Padding(
                    padding: const EdgeInsets.only(top: SagipSpace.xs),
                    child: Text(
                      l10n.advisoryStep(step),
                      style: text.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(
          _everywhere
              ? l10n.advisoryToEveryone
              : l10n.advisoryToBarangays(areas.join(', ')),
          style: text.bodyMedium,
        ),
        const SizedBox(height: SagipSpace.xs),
        Text(
          simulated
              ? l10n.advisorySimulated
              : others.isEmpty
              ? l10n.advisoryAppsOnly
              : l10n.advisoryChannels(others.join(', ')),
          style: text.bodyMedium!.copyWith(
            color: simulated ? p.warning.text : null,
          ),
        ),
      ],
    );
  }
}

/// "End this alert?" The apps stop showing it; it stays in the log.
Future<void> confirmEndAlert(
  BuildContext context,
  WidgetRef ref,
  PublicAlert alert,
) async {
  final l10n = AppLocalizations.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.endAlertTitle),
      content: SizedBox(
        width: 400,
        child: Text(l10n.endAlertBody(alert.title)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.endAlert),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  await runAction(
    context,
    () => ref.read(alertLogRepositoryProvider).end(alert.id),
    success: l10n.alertEndedSnack,
  );
}
