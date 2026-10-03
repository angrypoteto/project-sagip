import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/barangay_picker.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// R5 Location picker for a hazard report. Online: move the map under a
/// fixed pin, jump to GPS, or search a barangay. Offline there are no map
/// tiles, so it offers the GPS fix or a barangay from the bundled list.
/// Pops with the chosen [LocationFix]; a pin or barangay is marked
/// [LocationFix.manual].
class LocationPickerPage extends ConsumerStatefulWidget {
  const LocationPickerPage({super.key, this.initial});

  /// Where the pin starts: the report's current location.
  final GeoPoint? initial;

  @override
  ConsumerState<LocationPickerPage> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<LocationPickerPage> {
  final _map = MapController();
  final _search = TextEditingController();
  var _ready = false;
  var _query = '';
  late GeoPoint _center;

  /// The pin sits on the GPS fix (not moved by hand since "Use my GPS").
  var _onGps = false;

  /// Offline choice: the GPS fix, or a barangay from the list.
  var _offlineGps = false;
  Barangay? _offlineBarangay;

  @override
  void initState() {
    super.initState();
    final gps = ref.read(locationProvider).value?.lastFix;
    final start = widget.initial ?? gps?.point;
    _center = start ?? GeoPoint(manilaCenter.latitude, manilaCenter.longitude);
    _onGps = gps != null && start == gps.point;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _moveTo(GeoPoint p, {bool gps = false}) {
    setState(() {
      _center = p;
      _onGps = gps;
      _query = '';
      _search.clear();
    });
    if (_ready) _map.move(toLatLng(p), 17);
    FocusScope.of(context).unfocus();
  }

  LocationFix? _result(bool online, LocationFix? gps) {
    final now = DateTime.now();
    if (online) {
      if (_onGps && gps != null) return gps;
      final near = nearestBarangay(_center);
      return LocationFix(
        point: _center,
        accuracyMeters: 0,
        at: now,
        barangay: near?.name,
        district: near?.district,
        manual: true,
      );
    }
    if (_offlineGps) return gps;
    final b = _offlineBarangay;
    if (b == null || b.center == null) return null;
    return LocationFix(
      point: b.center!,
      accuracyMeters: 0,
      at: now,
      barangay: b.name,
      district: b.district,
      manual: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online =
        (ref.watch(signalProvider).value ?? SignalState.internet) ==
        SignalState.internet;
    final gps = ref.watch(locationProvider).value?.lastFix;
    final result = _result(online, gps);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pickLocationTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfflineBanner(),
          Expanded(child: online ? _mapView(context, gps) : _offline(gps)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            SagipSpace.md,
            SagipSpace.xl,
            SagipSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (online) ...[
                _PlaceLine(point: _center, gps: gps),
                const SizedBox(height: SagipSpace.md),
              ],
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: result == null ? null : () => context.pop(result),
                  child: Text(l10n.pickConfirm),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapView(BuildContext context, LocationFix? gps) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final tiles = ref.watch(mapTilesEnabledProvider);
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <Barangay>[]
        : [
            for (final b in manilaBarangays)
              if (b.center != null &&
                  ('${b.name} ${b.district}').toLowerCase().contains(q))
                b,
          ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: toLatLng(_center),
            initialZoom: 17,
            onMapReady: () => _ready = true,
            // Moves by code set the center themselves (_moveTo).
            onPositionChanged: (camera, hasGesture) {
              if (!hasGesture) return;
              final c = camera.center;
              setState(() {
                _center = GeoPoint(c.latitude, c.longitude);
                _onGps = false;
              });
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            SagipTiles(userAgentPackageName: 'ph.sagip.mobile', enabled: tiles),
            if (gps != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: toLatLng(gps.point),
                    radius: gps.accuracyMeters.clamp(5, 200),
                    useRadiusInMeter: true,
                    color: p.info.fill.withValues(alpha: 0.12),
                    borderColor: p.info.fill.withValues(alpha: 0.4),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: toLatLng(gps.point),
                    width: 16,
                    height: 16,
                    child: Semantics(
                      container: true,
                      label: l10n.youAreHere,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.info.fill,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            MapCredit(label: l10n.mapAttribution),
          ],
        ),
        // The pin stays in the middle; the map moves under it. Its tip
        // marks the spot.
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: Semantics(
                label: l10n.pickPin,
                child: Icon(
                  Symbols.location_on_rounded,
                  size: 48,
                  fill: 1,
                  color: p.info.fill,
                  shadows: const [
                    Shadow(color: Color(0x33000000), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: SagipSpace.lg,
          right: SagipSpace.lg,
          top: SagipSpace.lg,
          child: _SearchBox(
            controller: _search,
            matches: matches,
            showNoMatch: q.isNotEmpty && matches.isEmpty,
            onChanged: (v) => setState(() => _query = v),
            onPick: (b) => _moveTo(b.center!),
          ),
        ),
        Positioned(
          right: SagipSpace.lg,
          bottom: SagipSpace.x3,
          child: _FloatingButton(
            icon: Symbols.my_location_rounded,
            tooltip: l10n.pickUseGps,
            onPressed: gps == null ? null : () => _moveTo(gps.point, gps: true),
          ),
        ),
      ],
    );
  }

  Widget _offline(LocationFix? gps) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final b = _offlineBarangay;

    Widget option({
      required bool selected,
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      leading: Icon(
        selected
            ? Symbols.radio_button_checked_rounded
            : Symbols.radio_button_unchecked_rounded,
        color: selected ? p.info.text : p.textSecondary,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(icon, color: p.textSecondary),
      onTap: onTap,
    );

    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        Text(l10n.pickOfflineTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.xs),
        Text(
          l10n.pickOfflineBody,
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.lg),
        option(
          selected: _offlineGps,
          icon: Symbols.my_location_rounded,
          title: l10n.pickGpsOption,
          subtitle: gps == null ? l10n.pickNoGps : formatCoordinates(gps.point),
          onTap: gps == null
              ? null
              : () => setState(() {
                  _offlineGps = true;
                  _offlineBarangay = null;
                }),
        ),
        option(
          selected: b != null,
          icon: Symbols.location_city_rounded,
          title: b == null ? l10n.barangay : b.name,
          subtitle: b == null ? l10n.chooseBarangay : b.district,
          onTap: () async {
            final picked = await showBarangayPicker(context);
            if (picked != null) {
              setState(() {
                _offlineBarangay = picked;
                _offlineGps = false;
              });
            }
          },
        ),
      ],
    );
  }
}

/// "Near Barangay 412, Sampaloc" and the pin's coordinates.
class _PlaceLine extends StatelessWidget {
  const _PlaceLine({required this.point, required this.gps});

  final GeoPoint point;
  final LocationFix? gps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final near = nearestBarangay(point);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          near == null
              ? l10n.pickNoBarangay
              : l10n.pickNear(l10n.place(near.name, near.district)),
          style: text.titleSmall,
        ),
        Text(
          formatCoordinates(point),
          style: text.bodySmall!.copyWith(
            color: p.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          gps == null ? l10n.pickNoGps : l10n.pickMoveHint,
          style: text.bodySmall!.copyWith(
            color: gps == null ? p.warning.text : p.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.matches,
    required this.showNoMatch,
    required this.onChanged,
    required this.onPick,
  });

  final TextEditingController controller;
  final List<Barangay> matches;
  final bool showNoMatch;
  final ValueChanged<String> onChanged;
  final ValueChanged<Barangay> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    return Material(
      color: p.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        side: BorderSide(color: p.hairline),
      ),
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              onChanged: onChanged,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: l10n.pickSearch,
                prefixIcon: const Icon(Symbols.search_rounded),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
            if (matches.isNotEmpty || showNoMatch) const Divider(height: 1),
            if (showNoMatch)
              ListTile(title: Text(l10n.noBarangayMatch))
            else
              for (final b in matches.take(5))
                ListTile(
                  leading: const Icon(Symbols.location_city_rounded),
                  title: Text(b.name),
                  subtitle: Text(b.district),
                  onTap: () => onPick(b),
                ),
          ],
        ),
      ),
    );
  }
}

/// A round control floating over the map: panel surface, hairline border,
/// soft shadow (design skill).
class _FloatingButton extends StatelessWidget {
  const _FloatingButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.panel,
        shape: BoxShape.circle,
        border: Border.all(color: p.hairline),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 24)],
      ),
      child: SizedBox(
        width: 56,
        height: 56,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: onPressed == null ? p.hairlineStrong : p.info.text,
          ),
        ),
      ),
    );
  }
}
