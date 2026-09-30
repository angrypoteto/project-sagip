import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/map_markers.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// F4 Navigation: full-bleed map, one floating card, nothing else (design
/// skill). Until Dijkstra road routes arrive (Phase 4) it shows a straight
/// line and a compass direction.
class NavigatePage extends ConsumerStatefulWidget {
  const NavigatePage({super.key});

  @override
  ConsumerState<NavigatePage> createState() => _NavigatePageState();
}

class _NavigatePageState extends ConsumerState<NavigatePage> {
  final _map = MapController();
  var _follow = true;
  var _ready = false;

  void _recenter(ResponderState s) {
    final at = s.unit.location;
    if (at == null || !_ready) return;
    _map.move(toLatLng(at), 17);
    setState(() => _follow = true);
  }

  Future<void> _arrived() async {
    await ref.read(responderRepositoryProvider).arrive();
    if (mounted) context.pushReplacement(Routes.onScene);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(responderProvider).value;
    final a = state?.current;

    ref.listen(responderProvider, (_, next) {
      final at = next.value?.unit.location;
      if (_follow && _ready && at != null) {
        _map.move(toLatLng(at), _map.camera.zoom);
      }
    });

    if (state == null || a == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navigateTitle)),
        body: EmptyState(
          icon: Symbols.task_alt_rounded,
          title: l10n.noAssignmentTitle,
        ),
      );
    }

    final unit = state.unit.location;
    final estimate = routeEstimate(state, a);
    final heading = estimate?.bearing;
    final tiles = ref.watch(mapTilesEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navigateTitle)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: toLatLng(unit ?? a.location),
                    initialZoom: 17,
                    onMapReady: () => _ready = true,
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture && _follow) {
                        setState(() => _follow = false);
                      }
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    SagipTiles(
                      userAgentPackageName: 'ph.sagip.mobile',
                      enabled: tiles,
                    ),
                    if (unit != null)
                      GlidingLayer(
                        target: toLatLng(unit),
                        builder: (at) => PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [at, toLatLng(a.location)],
                              strokeWidth: 5,
                              color: SagipPalette.of(context).info.fill,
                              pattern: StrokePattern.dashed(
                                segments: const [12, 8],
                              ),
                            ),
                          ],
                        ),
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: toLatLng(a.location),
                          width: 44,
                          height: 44,
                          child: Semantics(
                            container: true,
                            label: l10n.destination,
                            child: const SosPinMarker(),
                          ),
                        ),
                      ],
                    ),
                    if (unit != null)
                      GlidingLayer(
                        target: toLatLng(unit),
                        builder: (at) => MarkerLayer(
                          markers: [
                            Marker(
                              point: at,
                              width: 44,
                              height: 44,
                              child: Semantics(
                                container: true,
                                label: l10n.yourUnit,
                                child: UnitMarker(
                                  type: state.unit.type,
                                  heading: heading,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    MapCredit(label: l10n.mapAttribution),
                  ],
                ),
                if (!_follow)
                  Positioned(
                    right: SagipSpace.lg,
                    top: SagipSpace.lg,
                    child: FloatingActionButton.small(
                      tooltip: l10n.recenter,
                      onPressed: () => _recenter(state),
                      child: const Icon(Symbols.my_location_rounded),
                    ),
                  ),
                Positioned(
                  left: SagipSpace.lg,
                  right: SagipSpace.lg,
                  bottom: SagipSpace.lg,
                  child: _NavCard(
                    state: state,
                    estimate: estimate,
                    onArrived: _arrived,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends ConsumerWidget {
  const _NavCard({
    required this.state,
    required this.estimate,
    required this.onArrived,
  });

  final ResponderState state;
  final ({double meters, int minutes, double bearing})? estimate;
  final VoidCallback onArrived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final e = estimate;
    final close = e != null && e.meters <= arrivalRadiusMeters;

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
            if (!state.gpsOn || e == null)
              Row(
                children: [
                  Icon(
                    Symbols.location_searching_rounded,
                    color: p.warning.text,
                  ),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(
                      l10n.waitingForGps,
                      style: text.titleMedium!.copyWith(color: p.warning.text),
                    ),
                  ),
                ],
              )
            else if (close) ...[
              // Within the arrival radius a direction and an ETA mean
              // nothing; say where they are instead.
              Text(l10n.atScene, style: text.headlineSmall),
              Text(
                l10n.distanceAway(formatDistance(e.meters)),
                style: text.bodyMedium!.copyWith(color: p.textSecondary),
              ),
            ] else ...[
              Text(
                '${l10n.heading(e.bearing)} · ${formatDistance(e.meters)}',
                style: text.titleMedium,
              ),
              const SizedBox(height: SagipSpace.sm),
              EtaHero(
                label: l10n.etaTitle,
                value: l10n.etaMinutes(e.minutes),
                caption: l10n.toGo(formatDistance(e.meters)),
              ),
            ],
            const SizedBox(height: SagipSpace.xs),
            Text(
              signal == SignalState.internet
                  ? l10n.straightLineNote
                  : l10n.offlineSavedMap,
              style: text.bodySmall!.copyWith(
                color: signal == SignalState.internet
                    ? p.textSecondary
                    : p.warning.text,
              ),
            ),
            if (close) ...[
              const SizedBox(height: SagipSpace.lg),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: onArrived,
                  icon: const Icon(Symbols.flag_rounded),
                  label: Text(l10n.arrived),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
