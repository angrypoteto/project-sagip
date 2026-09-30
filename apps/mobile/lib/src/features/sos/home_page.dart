import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/alert_strip.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// R1 Home and SOS. The SOS button renders immediately and never waits for
/// data (plan 7.4); everything else fills in around it.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fix = ref.read(locationProvider).value?.lastFix;
      final sos = await ref.read(sosRepositoryProvider).send(fix: fix);
      if (context.mounted) context.push(Routes.sos(sos.clientId));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.sosSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final user = ref.watch(currentUserProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    final location = ref.watch(locationProvider).value;
    final active = ref.watch(activeSosProvider);
    final phase = sosPhase(active);
    final name = (profile?.fullName ?? user?.displayName ?? '')
        .split(' ')
        .first;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SagipSpace.xl,
                SagipSpace.xl,
                SagipSpace.xl,
                SagipSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.greeting(name), style: text.headlineSmall),
                  if (profile != null) ...[
                    const SizedBox(height: SagipSpace.xs),
                    Text(
                      l10n.place(profile.barangay, profile.district),
                      style: text.bodyMedium!.copyWith(color: p.textSecondary),
                    ),
                  ],
                  const SizedBox(height: SagipSpace.lg),
                  const AlertStrip(),
                  const Spacer(),
                  Center(
                    child: SosButton(
                      phase: phase,
                      semanticLabel: active == null
                          ? l10n.sosSemantic
                          : l10n.sosOpenSemantic,
                      onSend: () => _send(context, ref),
                      onOpen: active == null
                          ? null
                          : () => context.push(Routes.sos(active.clientId)),
                    ),
                  ),
                  const SizedBox(height: SagipSpace.sm),
                  Text(
                    l10n.sosCaption(phase),
                    style: text.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (location != null && !location.gpsOn) ...[
                    const SizedBox(height: SagipSpace.md),
                    _GpsOff(
                      onOpenSettings: () =>
                          ref.read(locationServiceProvider).openSettings(),
                    ),
                  ],
                  const Spacer(),
                  if (active != null) ...[
                    _ActiveSosCard(sos: active),
                    const SizedBox(height: SagipSpace.sm),
                  ],
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.go(Routes.report),
                      icon: const Icon(Symbols.report_rounded),
                      label: Text(l10n.reportHazard),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GpsOff extends StatelessWidget {
  const _GpsOff({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.location_off_rounded, color: p.warning.text),
            const SizedBox(width: SagipSpace.sm),
            Expanded(
              child: Text(
                l10n.gpsOff,
                style: text.bodyMedium!.copyWith(color: p.warning.text),
              ),
            ),
          ],
        ),
        TextButton(onPressed: onOpenSettings, child: Text(l10n.openSettings)),
      ],
    );
  }
}

class _ActiveSosCard extends ConsumerWidget {
  const _ActiveSosCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final elapsed = now.difference(sos.capturedAt);
    return Material(
      color: p.panelRaised,
      borderRadius: BorderRadius.circular(SagipRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        onTap: () => context.push(Routes.sos(sos.clientId)),
        child: Semantics(
          hint: l10n.viewStatus,
          child: Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Row(
              children: [
                Icon(Symbols.sos_rounded, color: p.critical.text),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.sosState(sos), style: text.titleMedium),
                      const SizedBox(height: SagipSpace.xs),
                      Text(
                        l10n.elapsed(
                          formatWait(
                            elapsed.isNegative ? Duration.zero : elapsed,
                          ),
                        ),
                        style: text.bodySmall!.copyWith(
                          color: p.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Symbols.chevron_right_rounded, color: p.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
