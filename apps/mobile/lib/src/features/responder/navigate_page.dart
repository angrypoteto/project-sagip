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
import 'voice_guide.dart';

/// F4 Navigation: full-bleed map, one floating card, nothing else (design
/// skill). The route is Dijkstra over the bundled road graph, computed on
/// the phone from each new position (so it works offline and re-routes);
/// without it the card falls back to a straight line and a compass
/// direction.
class NavigatePage extends ConsumerStatefulWidget {
  const NavigatePage({super.key});

  @override
  ConsumerState<NavigatePage> createState() => _NavigatePageState();
}

class _NavigatePageState extends ConsumerState<NavigatePage> {
  final _map = MapController();
  var _follow = true;
  var _ready = false;
  final _voice = VoiceGuide();
  late final Speaker _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
  }

  @override
  void dispose() {
    _speaker.stop();
    super.dispose();
  }

  /// Says the next turn or the arrival once, after the frame that shows it.
  void _speak(RouteEstimate? e) {
    if (e == null) return;
    final l10n = AppLocalizations.of(context);
    final next = e.road?.nextTurn;
    final line = _voice.update(
      atScene: e.straightMeters <= arrivalRadiusMeters,
      turn: next == null ? null : l10n.turnInstruction(next),
      meters: next == null ? null : e.road!.metersToNextTurn,
    );
    if (line == null || !ref.read(voiceGuidanceProvider)) return;
    final String text;
    if (line.isScene) {
      text = l10n.atScene;
    } else if (line.meters == null) {
      text = line.turn!;
    } else {
      final d = spokenDistance(line.meters!);
      text = d.meters != null
          ? l10n.voiceAheadMeters(d.meters!, line.turn!)
          : l10n.voiceAheadKilometers(d.kilometers!, line.turn!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _speaker.say(text));
  }

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
    final estimate = routeEstimate(ref, state, a);
    if (state.gpsOn) _speak(estimate);
    final voiceOn = ref.watch(voiceGuidanceProvider);
    final heading = estimate?.bearing;
    final tiles = ref.watch(mapTilesEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navigateTitle),
        actions: [
          IconButton(
            key: const ValueKey('voice-toggle'),
            tooltip: voiceOn ? l10n.voiceOn : l10n.voiceOff,
            onPressed: () {
              ref.read(voiceGuidanceProvider.notifier).set(!voiceOn);
              if (voiceOn) _speaker.stop();
            },
            icon: Icon(
              voiceOn ? Symbols.volume_up_rounded : Symbols.volume_off_rounded,
            ),
          ),
        ],
      ),
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
                      tileProvider: ref.watch(tileProviderProvider),
                    ),
                    if (unit != null)
                      GlidingLayer(
                        target: toLatLng(unit),
                        builder: (at) => PolylineLayer(
                          polylines: [
                            if (estimate?.road case final road?)
                              Polyline(
                                points: [
                                  at,
                                  for (final p in road.points.skip(1))
                                    toLatLng(p),
                                ],
                                strokeWidth: 6,
                                color: SagipPalette.of(context).info.fill,
                              )
                            else
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
  final RouteEstimate? estimate;
  final VoidCallback onArrived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final e = estimate;
    final close = e != null && e.straightMeters <= arrivalRadiusMeters;
    final road = e?.road;
    final next = road?.nextTurn;

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
                l10n.distanceAway(formatDistance(e.straightMeters)),
                style: text.bodyMedium!.copyWith(color: p.textSecondary),
              ),
            ] else ...[
              if (road == null)
                Text(
                  '${l10n.heading(e.bearing)} · ${formatDistance(e.meters)}',
                  style: text.titleMedium,
                )
              else ...[
                // The next turn, the one thing a driver needs (design skill).
                Text(
                  next == null
                      ? l10n.continueToScene
                      : l10n.turnInstruction(next),
                  style: text.titleLarge,
                ),
                if (next != null)
                  Text(
                    l10n.inDistance(formatDistance(road.metersToNextTurn)),
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  ),
              ],
              const SizedBox(height: SagipSpace.sm),
              EtaHero(
                label: l10n.etaTitle,
                value: l10n.etaMinutes(e.minutes),
                caption: l10n.toGo(formatDistance(e.meters)),
              ),
            ],
            const SizedBox(height: SagipSpace.xs),
            Text(
              signal != SignalState.internet
                  ? l10n.offlineSavedMap
                  : road != null
                  ? l10n.roadRouteNote
                  : l10n.straightLineNote,
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
