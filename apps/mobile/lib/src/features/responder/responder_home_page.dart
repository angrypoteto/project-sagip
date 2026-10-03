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

/// F1 Responder home: the unit's status control, the current assignment,
/// and whether the unit's location is being shared.
class ResponderHomePage extends ConsumerWidget {
  const ResponderHomePage({super.key});

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    UnitStatus status,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(responderRepositoryProvider).setStatus(status);
    } on StatusRejected catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.statusRejection(e.reason))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final state = ref.watch(responderProvider);
    final s = state.value;
    if (s == null) return const SkeletonList();

    final unit = s.unit;
    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        Text(unit.callSign, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.xs),
        Text(
          l10n.unitDetail(
            l10n.unitType(unit.type),
            unit.station,
            unit.crewSize,
          ),
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.xl),
        UnitStatusControl(
          value: unit.status,
          labels: {for (final u in UnitStatus.values) u: l10n.unitStatus(u)},
          onSelected: (status) {
            if (status != unit.status) _setStatus(context, ref, status);
          },
        ),
        const SizedBox(height: SagipSpace.md),
        _SharingLine(state: s),
        const _BatteryPrompt(),
        const SizedBox(height: SagipSpace.xl),
        if (s.offer != null) ...[
          _OfferCard(offer: s.offer!),
          const SizedBox(height: SagipSpace.lg),
        ],
        if (s.current != null)
          _AssignmentCard(state: s, assignment: s.current!)
        else if (s.offer == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SagipSpace.xl),
            child: EmptyState(
              icon: Symbols.task_alt_rounded,
              title: l10n.noAssignmentTitle,
              message: l10n.noAssignmentBody,
            ),
          ),
        const SizedBox(height: SagipSpace.lg),
        const AlertStrip(),
      ],
    );
  }
}

/// "Sharing location · sent 5 s ago", or why it is not being shared.
class _SharingLine extends ConsumerWidget {
  const _SharingLine({required this.state});

  final ResponderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final sent = state.locationSentAt ?? state.unit.lastLocationAt;
    final ago = sent == null ? '–' : l10n.ago(sent, now);
    final (String line, IconData icon, Color color) = !state.gpsOn
        ? (
            l10n.waitingForGps,
            Symbols.location_disabled_rounded,
            p.warning.text,
          )
        : signal != SignalState.internet
        ? (
            l10n.locationNotShared(ago),
            Symbols.location_off_rounded,
            p.warning.text,
          )
        : (
            l10n.sharingLocation(ago),
            Symbols.my_location_rounded,
            p.textSecondary,
          );
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: SagipSpace.sm),
        Expanded(
          child: Text(line, style: text.bodySmall!.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Asks to be left running in the background when the phone's battery
/// saver could stop location sharing. Gone once the phone says exempt.
class _BatteryPrompt extends ConsumerStatefulWidget {
  const _BatteryPrompt();

  @override
  ConsumerState<_BatteryPrompt> createState() => _BatteryPromptState();
}

class _BatteryPromptState extends ConsumerState<_BatteryPrompt> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The phone's question opens over the app; check again on return.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(batteryExemptProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _allow() async {
    await ref.read(batteryOptimizationProvider).requestExemption();
    ref.invalidate(batteryExemptProvider);
  }

  @override
  Widget build(BuildContext context) {
    final exempt = ref.watch(batteryExemptProvider).value ?? true;
    if (exempt) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SagipSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(SagipSpace.lg),
        decoration: BoxDecoration(
          color: p.panelRaised,
          borderRadius: BorderRadius.circular(SagipRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.battery_alert_rounded, color: p.warning.text),
                const SizedBox(width: SagipSpace.sm),
                Expanded(
                  child: Text(l10n.batteryTitle, style: text.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.sm),
            Text(l10n.batteryBody, style: text.bodyMedium),
            const SizedBox(height: SagipSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _allow,
                child: Text(l10n.batteryAllow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final Assignment offer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Material(
      color: p.critical.tint,
      borderRadius: BorderRadius.circular(SagipRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        onTap: () => context.push(Routes.incoming),
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.lg),
          child: Row(
            children: [
              Icon(
                Symbols.notifications_active_rounded,
                color: p.critical.text,
              ),
              const SizedBox(width: SagipSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newAssignment,
                      style: text.titleMedium!.copyWith(color: p.critical.text),
                    ),
                    Text(
                      '${l10n.typeOrEmergency(offer.type)} · ${offer.place}',
                      style: text.bodyMedium!.copyWith(color: p.critical.text),
                    ),
                  ],
                ),
              ),
              Icon(Symbols.chevron_right_rounded, color: p.critical.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// The current assignment as one card with a hero ETA (design skill).
class _AssignmentCard extends ConsumerWidget {
  const _AssignmentCard({required this.state, required this.assignment});

  final ResponderState state;
  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final estimate = routeEstimate(ref, state, assignment);
    final onScene = assignment.status == IncidentStatus.onScene;
    return Material(
      color: p.panelRaised,
      borderRadius: BorderRadius.circular(SagipRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        onTap: () => context.push(Routes.assignment),
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.currentAssignment,
                style: text.labelLarge!.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: SagipSpace.xs),
              Text(
                l10n.typeOrEmergency(assignment.type),
                style: text.titleLarge,
              ),
              Text(assignment.place, style: text.bodyMedium),
              if (assignment.vulnerable.isNotEmpty) ...[
                const SizedBox(height: SagipSpace.sm),
                SagipChip(
                  label: l10n.vulnerableTypes(
                    assignment.vulnerable.map(l10n.vulnerability).join(', '),
                  ),
                  tone: p.warning,
                  icon: Symbols.accessible_rounded,
                ),
              ],
              if (!onScene && estimate != null) ...[
                const SizedBox(height: SagipSpace.md),
                EtaHero(
                  label: l10n.etaTitle,
                  value: l10n.etaMinutes(estimate.minutes),
                  caption: l10n.toGo(formatDistance(estimate.meters)),
                ),
              ],
              const SizedBox(height: SagipSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => context.push(Routes.assignment),
                  child: Text(l10n.openAssignment),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
