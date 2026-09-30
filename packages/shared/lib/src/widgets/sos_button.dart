import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/sagip_colors.dart';
import '../theme/sagip_tokens.dart';

/// What the SOS button shows. Holding is handled inside the button.
enum SosButtonPhase {
  /// No active SOS: hold to send.
  ready,

  /// Going out over the internet (the one allowed pulse).
  sending,

  /// Tier 1: saved in the offline queue.
  savedOnPhone,

  /// Tier 2: sent by SMS.
  sentBySms,

  /// Tier 3: relaying through nearby phones.
  relaying,

  /// The server has it.
  delivered,
}

/// The signature element (design skill): a large lit red button that sends
/// an SOS only after a two-second hold. A tap never sends; letting go early
/// snaps back. Light haptic ticks mark the hold, a heavy one the send.
///
/// Put the caption ("Hold for 2 seconds", or the delivery state) under the
/// button: small white text on the signal red would fail WCAG contrast.
///
/// While an SOS is active, pass [onOpen]: a tap then opens its status
/// instead of starting a second SOS. The button is never disabled.
class SosButton extends StatefulWidget {
  const SosButton({
    super.key,
    required this.phase,
    required this.semanticLabel,
    required this.onSend,
    this.onOpen,
    this.holdDuration = const Duration(seconds: 2),
    this.diameter = 200,
  });

  final SosButtonPhase phase;

  /// Read by TalkBack, for example "Send SOS. Hold for 2 seconds."
  final String semanticLabel;
  final VoidCallback onSend;
  final VoidCallback? onOpen;
  final Duration holdDuration;
  final double diameter;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addListener(_onHoldTick);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  int? _pointer;

  /// Whether the current press began while an SOS was already active. A
  /// hold that sends makes the button active mid-press; lifting that finger
  /// must not count as a tap.
  var _pressOpens = false;
  var _fired = false;
  var _ticks = 0;

  bool get _active => widget.onOpen != null;

  @override
  void didUpdateWidget(SosButton old) {
    super.didUpdateWidget(old);
    _hold.duration = widget.holdDuration;
    _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (widget.phase == SosButtonPhase.sending && !reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  void _onHoldTick() {
    // Three light ticks at 25, 50, and 75 percent.
    final due = (_hold.value * 4).floor().clamp(0, 3);
    if (due > _ticks) {
      _ticks = due;
      HapticFeedback.lightImpact();
    }
    if (_hold.isCompleted && !_fired) {
      _fired = true;
      HapticFeedback.heavyImpact();
      widget.onSend();
    }
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _pressOpens = _active;
    if (_pressOpens) return;
    _fired = false;
    _ticks = 0;
    _hold.forward(from: 0);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_pressOpens) {
      if (e is PointerUpEvent && _active) widget.onOpen!();
      return;
    }
    if (_fired) {
      _hold.value = 0;
    } else {
      // Released early: snap back, nothing is sent.
      _hold.animateBack(0, duration: SagipMotion.base, curve: SagipMotion.exit);
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final outer = d * 1.45;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      // TalkBack: double-tap and hold sends; a double-tap opens the status
      // of an active SOS.
      onLongPress: _active ? null : widget.onSend,
      onTap: widget.onOpen,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: SizedBox.square(
          dimension: outer,
          child: AnimatedBuilder(
            animation: Listenable.merge([_hold, _pulse]),
            builder: (context, _) {
              final press = 1 - 0.03 * _hold.value;
              final pulse = 1 + 0.04 * _pulse.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final (scale, alpha) in const [
                    (1.45, 0.05),
                    (1.30, 0.09),
                    (1.15, 0.14),
                  ])
                    _Ring(diameter: d * scale * pulse, alpha: alpha),
                  Transform.scale(
                    scale: press * pulse,
                    child: _Face(diameter: d, phase: widget.phase),
                  ),
                  if (_hold.value > 0)
                    SizedBox.square(
                      dimension: d,
                      child: CustomPaint(
                        painter: _ProgressPainter(_hold.value),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.diameter, required this.alpha});

  final double diameter;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: SagipColors.signal.withValues(alpha: alpha),
    ),
  );
}

class _Face extends StatelessWidget {
  const _Face({required this.diameter, required this.phase});

  final double diameter;
  final SosButtonPhase phase;

  @override
  Widget build(BuildContext context) {
    final icon = switch (phase) {
      SosButtonPhase.ready || SosButtonPhase.sending => null,
      SosButtonPhase.savedOnPhone => Symbols.smartphone_rounded,
      SosButtonPhase.sentBySms => Symbols.sms_rounded,
      SosButtonPhase.relaying => Symbols.bluetooth_searching_rounded,
      SosButtonPhase.delivered => Symbols.check_circle_rounded,
    };
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Lit from within: a slightly lighter center, darker rim.
        gradient: RadialGradient(
          center: const Alignment(-0.15, -0.25),
          radius: 0.85,
          colors: [
            Color.lerp(SagipColors.signal, Colors.white, 0.14)!,
            SagipColors.signal,
            Color.lerp(SagipColors.signal, SagipColors.signalStrong, 0.6)!,
          ],
          stops: const [0, 0.6, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: SagipColors.signal.withValues(alpha: 0.35),
            blurRadius: 32,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: diameter * 0.14, fill: 1),
            SizedBox(height: diameter * 0.02),
          ],
          Text(
            'SOS',
            style: TextStyle(
              fontFamily: kSagipFontFamily,
              fontSize: diameter * 0.24,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Colors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(stroke / 2 + 4),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.progress != progress;
}
