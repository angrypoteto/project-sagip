import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/sagip_palette.dart';
import 'brand.dart';

// The seal's motion on the sign-in screens of both apps (2026-11-10).

/// MDRRMD's seal on a sign-in screen: it eases in when the page opens, and
/// while signing in it breathes inside a turning ring. Still when the
/// device asks for less motion.
class SealEntrance extends StatefulWidget {
  const SealEntrance({super.key, required this.busy, this.size = 72});

  final bool busy;

  /// The seal's size; the ring around it is a little larger.
  final double size;

  /// The ring's size against the seal's.
  static const ringRatio = 92 / 72;

  @override
  State<SealEntrance> createState() => SealEntranceState();
}

class SealEntranceState extends State<SealEntrance>
    with TickerProviderStateMixin {
  double get _size => widget.size;
  double get _ring => widget.size * SealEntrance.ringRatio;

  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _still => MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still) {
      _enter.value = 1;
    } else if (_enter.status == AnimationStatus.dismissed) {
      _enter.forward();
    }
  }

  @override
  void didUpdateWidget(SealEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy == oldWidget.busy) return;
    if (widget.busy && !_still) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    final pulse = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    return SizedBox.square(
      key: const ValueKey('sign-in-seal'),
      dimension: _ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.busy)
            SizedBox.square(
              dimension: _ring,
              child: CircularProgressIndicator(
                key: const ValueKey('sign-in-seal-ring'),
                strokeWidth: 3,
                color: p.info.fill,
              ),
            ),
          AnimatedBuilder(
            animation: Listenable.merge([enter, pulse]),
            builder: (context, child) => Opacity(
              opacity: _enter.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: (0.7 + 0.3 * enter.value) * (1 + 0.06 * pulse.value),
                child: child,
              ),
            ),
            child: SagipMark(size: _size),
          ),
        ],
      ),
    );
  }
}

/// After a sign-in is accepted (Joshua, 2026-11-10): everything but the
/// seal goes; the seal floats up to the middle of the screen, then flies
/// toward the viewer, growing and fading, while the page behind it fades
/// to show the board.
class SealFlight extends StatefulWidget {
  const SealFlight({
    super.key,
    required this.from,
    required this.background,
    required this.onDone,
  });

  /// Where the seal sat on the card, on screen.
  final Rect from;

  /// The page color that hides the card, then fades.
  final Color background;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 1500);

  @override
  State<SealFlight> createState() => _SealFlightState();
}

class _SealFlightState extends State<SealFlight>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: SealFlight.duration,
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // 0 to 0.4: float to the middle, a little above it, and settle.
    final float = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.4, curve: Curves.easeInOutCubic),
    );
    // 0.45 to 1: fly forward and fade.
    final fly = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.45, 1, curve: Curves.easeInCubic),
    );
    // The page behind fades from 0.55, showing the board.
    final reveal = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 1, curve: Curves.easeOut),
    );
    final start = widget.from.center;
    final middle = Offset(screen.width / 2, screen.height / 2);
    // The box holds the seal and its ring: the seal is the inner part.
    final size = widget.from.width / SealEntrance.ringRatio;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // A gentle rise that peaks mid-float and settles.
          final lift = -24 * math.sin(math.pi * float.value);
          final at = Offset.lerp(start, middle, float.value)! + Offset(0, lift);
          final scale = 1 + 0.25 * float.value + 5 * fly.value;
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: widget.background.withValues(alpha: 1 - reveal.value),
                ),
              ),
              Positioned(
                left: at.dx - size / 2,
                top: at.dy - size / 2,
                width: size,
                height: size,
                child: Opacity(
                  opacity: (1 - fly.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: SagipMark(size: size),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Readies [SealFlight] before a sign-in is sent, while the sign-in screen
/// is still there; [play] runs it once the sign-in is accepted. [seal] is
/// the [SealEntrance]'s key: the flight starts where the seal is. Nothing
/// plays when the device asks for less motion.
class SealFlightLauncher {
  SealFlightLauncher(BuildContext context, {required GlobalKey seal})
    : _overlay = Overlay.of(context, rootOverlay: true),
      _still = MediaQuery.of(context).disableAnimations,
      _background = SagipPalette.of(context).canvas,
      _from = _rectOf(seal);

  final OverlayState _overlay;
  final bool _still;
  final Color _background;
  final Rect? _from;

  static Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void play() {
    final from = _from;
    if (_still || from == null || !_overlay.mounted) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SealFlight(
        from: from,
        background: _background,
        onDone: () => entry.remove(),
      ),
    );
    _overlay.insert(entry);
  }
}
