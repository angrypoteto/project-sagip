import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../common/map_markers.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// R3 Track responder: the resident's pin, the responder's marker gliding
/// between updates, and one floating card with the ETA (plan 7.4).
class TrackPage extends ConsumerWidget {
  const TrackPage({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final loading = ref.watch(mySosProvider).isLoading;
    final sos = ref.watch(sosByIdProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trackTitle)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: sos == null
                ? (loading
                      ? _Finding(label: l10n.trackFinding)
                      : EmptyState(
                          icon: Symbols.search_off_rounded,
                          title: l10n.sosNotFound,
                        ))
                : _TrackBody(sos: sos),
          ),
        ],
      ),
    );
  }
}

class _Finding extends StatelessWidget {
  const _Finding({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: SkeletonBox(height: double.infinity, radius: 0),
      ),
      Center(
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

class _TrackBody extends ConsumerWidget {
  const _TrackBody({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tiles = ref.watch(mapTilesEnabledProvider);
    final you = sos.location == null ? null : toLatLng(sos.location!);
    final unit = sos.responderLocation == null
        ? null
        : toLatLng(sos.responderLocation!);
    final points = [?you, ?unit];
    final fitBoth = you != null && unit != null && you != unit;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: points.isEmpty ? manilaCenter : points.first,
            initialZoom: 16,
            initialCameraFit: fitBoth
                ? CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.fromLTRB(60, 60, 60, 260),
                    maxZoom: 17,
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            SagipTiles(userAgentPackageName: 'ph.sagip.mobile', enabled: tiles),
            if (you != null && unit != null)
              GlidingLayer(
                target: unit,
                builder: (at) => PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [at, you],
                      strokeWidth: 4,
                      color: SagipPalette.of(context).info.fill,
                      pattern: StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ],
                ),
              ),
            if (you != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: you,
                    width: 44,
                    height: 44,
                    child: Semantics(
                      container: true,
                      label: l10n.youAreHere,
                      child: const SosPinMarker(),
                    ),
                  ),
                ],
              ),
            if (unit != null)
              GlidingLayer(
                target: unit,
                builder: (at) => MarkerLayer(
                  markers: [
                    Marker(
                      point: at,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        container: true,
                        label: l10n.responderMarker(sos.unitCallSign ?? ''),
                        child: UnitMarker(type: sos.unitType),
                      ),
                    ),
                  ],
                ),
              ),
            MapCredit(label: l10n.mapAttribution),
          ],
        ),
        Positioned(
          left: SagipSpace.lg,
          right: SagipSpace.lg,
          bottom: SagipSpace.lg,
          child: _TrackCard(sos: sos),
        ),
      ],
    );
  }
}

/// The one floating card: unit, big ETA, status, freshness, and a call
/// button.
class _TrackCard extends ConsumerWidget {
  const _TrackCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final locale = Localizations.localeOf(context).toString();
    final assigned = sos.unitCallSign != null;
    final arrived =
        sos.status == IncidentStatus.onScene ||
        sos.status == IncidentStatus.resolved;
    final at = sos.responderLocationAt;
    final stale = at != null && now.difference(at) > const Duration(minutes: 2);

    return Material(
      color: p.panel,
      elevation: 3,
      borderRadius: BorderRadius.circular(SagipRadius.sheet),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!assigned)
              Text(l10n.trackWaiting, style: text.titleMedium)
            else ...[
              // Arrived: one clear message. Otherwise the status sits above
              // the unit so the unit line has the full width.
              if (!arrived)
                Text(
                  l10n.sosState(sos),
                  style: text.labelLarge!.copyWith(color: p.info.text),
                ),
              Text(
                l10n.unitLine(
                  sos.unitCallSign!,
                  sos.unitType == null ? '' : l10n.unitType(sos.unitType!),
                ),
                style: text.titleMedium,
              ),
              const SizedBox(height: SagipSpace.sm),
              if (arrived)
                Text(l10n.trackArrived, style: text.headlineSmall)
              else if (sos.etaMinutes != null) ...[
                Text(
                  l10n.etaTitle,
                  style: text.bodyMedium!.copyWith(color: p.textSecondary),
                ),
                Text(
                  l10n.etaMinutes(sos.etaMinutes!),
                  style: text.displaySmall!.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (at != null) ...[
                const SizedBox(height: SagipSpace.xs),
                Text(
                  signal == SignalState.internet
                      ? l10n.trackUpdated(l10n.ago(at, now))
                      : l10n.trackOffline(formatTime(at, locale)),
                  style: text.bodySmall!.copyWith(
                    color: stale || signal != SignalState.internet
                        ? p.warning.text
                        : p.textSecondary,
                  ),
                ),
              ],
            ],
            const SizedBox(height: SagipSpace.lg),
            FilledButton.icon(
              onPressed: () => showHotlineDialog(context),
              icon: const Icon(Symbols.call_rounded),
              label: Text(l10n.callMdrrmd),
            ),
          ],
        ),
      ),
    );
  }
}
