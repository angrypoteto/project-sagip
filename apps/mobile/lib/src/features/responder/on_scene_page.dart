import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/counter.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// F5 On scene: the on-scene check (FR8) and the number of people found.
/// Answers are saved on the phone and sent when online.
class OnScenePage extends ConsumerStatefulWidget {
  const OnScenePage({super.key});

  @override
  ConsumerState<OnScenePage> createState() => _OnScenePageState();
}

class _OnScenePageState extends ConsumerState<OnScenePage> {
  bool? _real;
  int? _people;
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _continue(Assignment a) async {
    final l10n = AppLocalizations.of(context);
    if (_real == null) return setState(() => _error = l10n.answerRealFirst);
    if (_real == false && _reason.text.trim().isEmpty) {
      return setState(() => _error = l10n.reasonRequired);
    }
    await ref
        .read(responderRepositoryProvider)
        .confirmOnScene(
          realEmergency: _real!,
          reason: _real! ? null : _reason.text.trim(),
          peopleFound: _people ?? a.peopleCount ?? 1,
        );
    if (mounted) context.pushReplacement(Routes.complete);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final a = ref.watch(responderProvider).value?.current;
    final locale = Localizations.localeOf(context).toString();

    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.onSceneTitle)),
        body: EmptyState(
          icon: Symbols.task_alt_rounded,
          title: l10n.noAssignmentTitle,
        ),
      );
    }
    final people = _people ?? a.peopleCount ?? 1;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.onSceneTitle)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SagipSpace.xl),
              children: [
                Text(a.address ?? a.place, style: text.titleLarge),
                if (a.onSceneAt != null)
                  Text(
                    l10n.onSceneAt(formatTime(a.onSceneAt!, locale)),
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  ),
                const SizedBox(height: SagipSpace.x3),
                Text(l10n.realEmergencyQuestion, style: text.titleMedium),
                const SizedBox(height: SagipSpace.md),
                SizedBox(
                  height: 56,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(l10n.yes)),
                      ButtonSegment(value: false, label: Text(l10n.no)),
                    ],
                    selected: {?_real},
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _real = s.isEmpty ? null : s.single;
                      _error = null;
                    }),
                  ),
                ),
                if (_real == false) ...[
                  const SizedBox(height: SagipSpace.lg),
                  TextField(
                    controller: _reason,
                    maxLines: 2,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      labelText: l10n.notRealReason,
                      hintText: l10n.notRealReasonHint,
                    ),
                  ),
                ],
                const SizedBox(height: SagipSpace.xl),
                Text(l10n.peopleFound, style: text.titleMedium),
                const SizedBox(height: SagipSpace.sm),
                Counter(
                  value: people,
                  label: l10n.peopleCount(people),
                  onChanged: (v) => setState(() => _people = v),
                  minimum: 0,
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
            child: FilledButton(
              onPressed: () => _continue(a),
              child: Text(l10n.completeRescue),
            ),
          ),
        ),
      ),
    );
  }
}
