import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

// Map markers shared by R3 Track responder and the responder screens.

/// Moves a map layer smoothly to [target] whenever it changes, so a unit
/// glides between position updates instead of jumping.
class GlidingLayer extends StatelessWidget {
  const GlidingLayer({super.key, required this.target, required this.builder});

  final LatLng target;
  final Widget Function(LatLng at) builder;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<LatLng>(
      tween: LatLngTween(begin: target, end: target),
      duration: still ? Duration.zero : const Duration(seconds: 3),
      builder: (context, at, _) => builder(at),
    );
  }
}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});

  @override
  LatLng lerp(double t) => LatLng(
    begin!.latitude + (end!.latitude - begin!.latitude) * t,
    begin!.longitude + (end!.longitude - begin!.longitude) * t,
  );
}

/// The person who needs help: a red pin with a soft halo.
class SosPinMarker extends StatelessWidget {
  const SosPinMarker({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SagipColors.signal.withValues(alpha: 0.18),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SagipColors.signal,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    ),
  );
}

/// A rescue unit: a rounded square with the unit type's icon. With a
/// [heading] (degrees from north) it shows a direction arrow instead, for
/// navigation.
class UnitMarker extends StatelessWidget {
  const UnitMarker({super.key, required this.type, this.heading});

  final UnitType? type;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final icon = heading != null
        ? Transform.rotate(
            angle: heading! * math.pi / 180,
            child: const Icon(
              Symbols.navigation_rounded,
              color: Colors.white,
              fill: 1,
            ),
          )
        : Icon(
            switch (type) {
              UnitType.ambulance => Symbols.ambulance_rounded,
              UnitType.rescueBoat => Symbols.directions_boat_rounded,
              _ => Symbols.groups_rounded,
            },
            color: Colors.white,
            fill: 1,
          );
    return Container(
      decoration: BoxDecoration(
        color: p.info.fill,
        borderRadius: BorderRadius.circular(
          heading != null ? 22 : SagipRadius.card,
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(child: icon),
    );
  }
}
