import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/incident_type_grid.dart';
import '../../common/labels.dart';
import '../../common/map_markers.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Safe places (Joshua, 2026-10-19): the three nearest places that suit
/// the emergency, on a map with the way there on foot. Advice only: help
/// comes to where the resident is, and officials' instructions come first.
/// Works offline from the list bundled in the app.
class SafePlacesPage extends ConsumerStatefulWidget {
  const SafePlacesPage({super.key, this.need, this.from, this.fromSos = false});

  /// The emergency, if known (the SOS's type, or flood for a weather alert).
  final IncidentType? need;

  /// Where to look from when the phone has no GPS fix.
  final GeoPoint? from;

  /// Opened from an open SOS.
  final bool fromSos;

  @override
  ConsumerState<SafePlacesPage> createState() => _SafePlacesPageState();
}

class _SafePlacesPageState extends ConsumerState<SafePlacesPage> {
  late IncidentType? _need = widget.need;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final fix = ref.watch(locationProvider).value?.lastFix;
    final from = fix?.point ?? widget.from;
    final need = _need;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.safePlacesTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                SagipSpace.xl,
                SagipSpace.lg,
                SagipSpace.xl,
                SagipSpace.x3,
              ),
              children: [
                Text(l10n.safePlacesWhat, style: text.titleMedium),
                const SizedBox(height: SagipSpace.md),
                IncidentTypeGrid(
                  selected: need,
                  onSelected: (t) => setState(() {
                    _need = t;
                    _selected = null;
                  }),
                ),
                const SizedBox(height: SagipSpace.lg),
                _Advice(need: need, fromSos: widget.fromSos),
                const SizedBox(height: SagipSpace.lg),
                if (need == null)
                  Text(l10n.safePlacesPick, style: text.bodyMedium)
                else if (from == null)
                  EmptyState(
                    icon: Symbols.location_off_rounded,
                    title: l10n.safePlacesNoLocation,
                  )
                else
                  _Results(
                    from: from,
                    need: need,
                    selected: _selected,
                    onSelect: (id) => setState(() => _selected = id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What to do first, for the emergency picked. Calm, not an alarm.
class _Advice extends StatelessWidget {
  const _Advice({required this.need, required this.fromSos});

  final IncidentType? need;
  final bool fromSos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final lines = [
      fromSos ? l10n.safePlacesFromSos : l10n.safePlacesGoIfSafe,
      if (need != null)
        switch (need!) {
          IncidentType.flood => l10n.safeAdviceFlood,
          IncidentType.fire => l10n.safeAdviceFire,
          IncidentType.structural => l10n.safeAdviceStructural,
          IncidentType.medical => l10n.safeAdviceMedical,
        },
    ];
    return DecoratedBox(
      key: const ValueKey('safe-advice'),
      decoration: BoxDecoration(
        color: p.warning.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.info_rounded, color: p.warning.text),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: SagipSpace.sm),
                    Text(lines[i], style: text.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.from,
    required this.need,
    required this.selected,
    required this.onSelect,
  });

  final GeoPoint from;
  final IncidentType need;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final near = ref.watch(safePlacesNearProvider(safePlaceQuery(from, need)));
    return near.when(
      skipLoadingOnReload: true,
      loading: () => const SkeletonList(rows: 3),
      error: (_, _) => ErrorState(message: l10n.safePlacesNone),
      data: (options) {
        if (options.isEmpty) {
          return EmptyState(
            icon: Symbols.search_off_rounded,
            title: l10n.safePlacesNone,
          );
        }
        final chosen = options.firstWhere(
          (o) => o.place.id == selected,
          orElse: () => options.first,
        );
        final walk = ref.watch(
          walkRouteProvider((from: from, to: chosen.place.location)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SafeMap(
              from: from,
              options: options,
              chosen: chosen,
              walk: walk,
              onSelect: onSelect,
            ),
            const SizedBox(height: SagipSpace.lg),
            for (final o in options) ...[
              _PlaceTile(
                option: o,
                selected: o == chosen,
                walk: o == chosen ? walk : null,
                onTap: () => onSelect(o.place.id),
              ),
              const SizedBox(height: SagipSpace.sm),
            ],
            if (signal != SignalState.internet) ...[
              const SizedBox(height: SagipSpace.sm),
              Text(
                l10n.safePlacesOffline,
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SafeMap extends ConsumerWidget {
  const _SafeMap({
    required this.from,
    required this.options,
    required this.chosen,
    required this.walk,
    required this.onSelect,
  });

  final GeoPoint from;
  final List<SafePlaceOption> options;
  final SafePlaceOption chosen;
  final RoadRoute? walk;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final points = [
      toLatLng(from),
      for (final o in options) toLatLng(o.place.location),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(SagipRadius.card),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          // A new set of places frames the map again.
          key: ValueKey(options.map((o) => o.place.id).join()),
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 16,
            initialCameraFit: CameraFit.coordinates(
              coordinates: points,
              padding: const EdgeInsets.all(40),
              maxZoom: 17,
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            SagipTiles(
              userAgentPackageName: 'ph.sagip.mobile',
              enabled: ref.watch(mapTilesEnabledProvider),
              tileProvider: ref.watch(tileProviderProvider),
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: walk == null
                      ? [toLatLng(from), toLatLng(chosen.place.location)]
                      : [for (final pt in walk!.points) toLatLng(pt)],
                  strokeWidth: 4,
                  color: p.success.fill,
                  pattern: walk == null
                      ? StrokePattern.dashed(segments: const [10, 8])
                      : const StrokePattern.solid(),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final o in options)
                  Marker(
                    key: ValueKey('safe-marker-${o.place.id}'),
                    point: toLatLng(o.place.location),
                    width: 48,
                    height: 48,
                    child: GestureDetector(
                      onTap: () => onSelect(o.place.id),
                      child: Center(
                        child: SafePlaceMarker(
                          kind: o.place.kind,
                          official: o.place.official,
                          selected: o == chosen,
                          label: l10n.safePlaceName(o.place),
                          size: o == chosen ? 36 : 30,
                        ),
                      ),
                    ),
                  ),
                Marker(
                  point: toLatLng(from),
                  width: MyLocationMarker.size,
                  height: MyLocationMarker.size,
                  child: Semantics(
                    container: true,
                    label: l10n.youAreHere,
                    child: MyLocationMarker(
                      heading: ref.watch(headingProvider).value,
                    ),
                  ),
                ),
              ],
            ),
            MapCredit(label: l10n.mapAttribution),
          ],
        ),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.option,
    required this.selected,
    required this.walk,
    required this.onTap,
  });

  final SafePlaceOption option;
  final bool selected;
  final RoadRoute? walk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final place = option.place;
    final tabular = const [FontFeature.tabularFigures()];
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.success.tint : p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SagipRadius.card),
          side: BorderSide(
            color: selected ? p.success.fill : p.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('safe-place-${place.id}'),
          borderRadius: BorderRadius.circular(SagipRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(safePlaceIcon(place.kind), color: p.success.text),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.safePlaceName(place), style: text.titleSmall),
                      const SizedBox(height: SagipSpace.xs),
                      Text(
                        place.official
                            ? l10n.safePlaceOfficial
                            : place.barangay == null || place.name == null
                            ? l10n.safePlaceKind(place.kind)
                            : l10n.safePlaceUnnamed(
                                l10n.safePlaceKind(place.kind),
                                place.barangay!,
                              ),
                        style: text.bodySmall!.copyWith(color: p.textSecondary),
                      ),
                      if (selected) ...[
                        const SizedBox(height: SagipSpace.sm),
                        Text(
                          walk == null
                              ? l10n.safePlaceNoRoute
                              : l10n.safePlaceWalk(
                                  walkMinutes(walk!.meters),
                                  formatDistance(walk!.meters),
                                ),
                          style: text.bodyMedium!.copyWith(
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: SagipSpace.md),
                Text(
                  formatDistance(option.meters),
                  style: text.titleSmall!.copyWith(fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
