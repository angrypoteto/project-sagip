import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../common/map_markers.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// F3 Assignment detail. Works from the copy cached on the phone, so it
/// stays usable without a signal; actions are queued (plan 7.4).
class AssignmentPage extends ConsumerWidget {
  const AssignmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(responderProvider).value;
    final assignment = state?.current ?? state?.offer;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          assignment == null
              ? l10n.currentAssignment
              : l10n.assignmentTitle(assignment.incidentId),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: state == null
                ? const SkeletonList()
                : assignment == null
                ? EmptyState(
                    icon: Symbols.task_alt_rounded,
                    title: l10n.noAssignmentTitle,
                  )
                : _Body(state: state, assignment: assignment),
          ),
        ],
      ),
      bottomNavigationBar: assignment == null
          ? null
          : _Actions(state: state!, assignment: assignment),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.assignment});

  final ResponderState state;
  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final tiles = ref.watch(mapTilesEnabledProvider);
    final unit = state.unit.location;
    final points = [
      toLatLng(assignment.location),
      if (unit != null) toLatLng(unit),
    ];
    // The phone's own road route, else the one saved at dispatch.
    final road =
        routeEstimate(ref, state, assignment)?.road ?? assignment.route;

    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        if (assignment.closedByDispatcher) ...[
          _Banner(text: l10n.assignmentReassigned),
          const SizedBox(height: SagipSpace.lg),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(SagipRadius.card),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 15,
                initialCameraFit: points.length == 2 && points[0] != points[1]
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(40),
                        maxZoom: 17,
                      )
                    : null,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                SagipTiles(
                  userAgentPackageName: 'ph.sagip.mobile',
                  enabled: tiles,
                  tileProvider: ref.watch(tileProviderProvider),
                ),
                if (road != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [for (final q in road.points) toLatLng(q)],
                        strokeWidth: 4,
                        color: p.info.fill,
                      ),
                    ],
                  )
                else if (unit != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points.reversed.toList(),
                        strokeWidth: 3,
                        color: p.info.fill,
                        pattern: StrokePattern.dashed(segments: const [8, 6]),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        container: true,
                        label: l10n.destination,
                        child: const SosPinMarker(),
                      ),
                    ),
                    if (unit != null)
                      Marker(
                        point: toLatLng(unit),
                        width: 40,
                        height: 40,
                        child: Semantics(
                          container: true,
                          label: l10n.yourUnit,
                          child: UnitMarker(type: state.unit.type),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        _MapReadiness(assignment: assignment),
        const SizedBox(height: SagipSpace.xl),
        Text(l10n.victimLocation, style: text.titleMedium),
        const SizedBox(height: SagipSpace.sm),
        if (assignment.address != null)
          Text(assignment.address!, style: text.bodyLarge),
        Text(assignment.place, style: text.bodyMedium),
        Text(
          formatCoordinates(assignment.location),
          style: text.bodySmall!.copyWith(
            color: p.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: SagipSpace.xl),
        Text(l10n.incidentDetails, style: text.titleMedium),
        const SizedBox(height: SagipSpace.sm),
        Text(l10n.typeOrEmergency(assignment.type), style: text.bodyLarge),
        Text(l10n.reportedBy(assignment.channel), style: text.bodyMedium),
        if (assignment.peopleCount != null)
          Text(
            l10n.peopleCount(assignment.peopleCount!),
            style: text.bodyMedium,
          ),
        if (assignment.residentNote != null) ...[
          const SizedBox(height: SagipSpace.sm),
          Text(
            l10n.residentSaid(assignment.residentNote!),
            style: text.bodyMedium!.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        if (assignment.vulnerable.isNotEmpty) ...[
          const SizedBox(height: SagipSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SagipChip(
              label: l10n.vulnerableTypes(
                assignment.vulnerable.map(l10n.vulnerability).join(', '),
              ),
              tone: p.warning,
              icon: Symbols.accessible_rounded,
              dense: false,
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.warning.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          children: [
            Icon(Symbols.info_rounded, color: p.warning.text),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: p.warning.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Map saved for offline use", or how far saving has got.
class _MapReadiness extends ConsumerWidget {
  const _MapReadiness({required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (assignment.status == IncidentStatus.assigned) {
      return const SizedBox.shrink(); // not accepted yet
    }
    // Saving the map for offline use comes in Phase 5 on the real app.
    if (!ref.watch(capabilitiesProvider).offlineMaps) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final percent = (assignment.mapSaved * 100).round();
    if (percent >= 100) {
      return Row(
        children: [
          Icon(Symbols.offline_pin_rounded, color: p.success.text, fill: 1),
          const SizedBox(width: SagipSpace.sm),
          Expanded(
            child: Text(
              l10n.mapSaved,
              style: text.bodyMedium!.copyWith(color: p.success.text),
            ),
          ),
        ],
      );
    }
    final offline = signal != SignalState.internet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          offline ? l10n.mapNotSaved(percent) : l10n.mapSaving(percent),
          style: text.bodyMedium!.copyWith(
            color: offline ? p.warning.text : p.textSecondary,
          ),
        ),
        const SizedBox(height: SagipSpace.xs),
        LinearProgressIndicator(value: assignment.mapSaved),
      ],
    );
  }
}

/// The actions for where the responder is in the job.
class _Actions extends ConsumerWidget {
  const _Actions({required this.state, required this.assignment});

  final ResponderState state;
  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(responderRepositoryProvider);
    final offered = state.current == null;
    final onScene = assignment.status == IncidentStatus.onScene;

    final Widget primary;
    Widget? secondary;
    if (offered) {
      primary = FilledButton.icon(
        onPressed: () => repo.accept(assignment.incidentId),
        icon: const Icon(Symbols.play_arrow_rounded),
        label: Text(l10n.acceptAndStart),
      );
    } else if (!onScene) {
      primary = FilledButton.icon(
        onPressed: () => context.push(Routes.navigate),
        icon: const Icon(Symbols.navigation_rounded),
        label: Text(l10n.startNavigation),
      );
      secondary = OutlinedButton.icon(
        onPressed: () async {
          await repo.arrive();
          if (context.mounted) context.push(Routes.onScene);
        },
        icon: const Icon(Symbols.location_on_rounded),
        label: Text(l10n.markOnScene),
      );
    } else if (assignment.realEmergency == null) {
      primary = FilledButton(
        onPressed: () => context.push(Routes.onScene),
        child: Text(l10n.continueOnScene),
      );
    } else {
      primary = FilledButton(
        onPressed: () => context.push(Routes.complete),
        child: Text(l10n.fileReport),
      );
    }

    return SafeArea(
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
            SizedBox(height: 56, child: primary),
            if (secondary != null) ...[
              const SizedBox(height: SagipSpace.sm),
              secondary,
            ],
            TextButton.icon(
              onPressed: () => showHotlineDialog(context),
              icon: const Icon(Symbols.call_rounded),
              label: Text(l10n.callDispatcher),
            ),
          ],
        ),
      ),
    );
  }
}
