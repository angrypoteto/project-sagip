import 'package:material_ui/material_ui.dart';

import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';
import 'status_visuals.dart';

/// Small status or label chip. Status is always color, icon, and text
/// (never color alone). Use [SagipChip.status] for [StatusVisual]s.
class SagipChip extends StatelessWidget {
  const SagipChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.look = ChipLook.tint,
    this.dense = true,
  });

  SagipChip.status({
    super.key,
    required this.label,
    required StatusVisual visual,
    this.dense = true,
  }) : tone = visual.tone,
       icon = visual.icon,
       look = visual.look;

  final String label;
  final SagipTone tone;
  final IconData? icon;
  final ChipLook look;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = tone.text;
    final height = dense ? 24.0 : 28.0;
    // Sized to its content; the label shrinks with an ellipsis when space is
    // tight (long Filipino labels, narrow panels) instead of overflowing.
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 14 : 16, color: color),
          const SizedBox(width: SagipSpace.xs),
        ],
        Flexible(
          child: Text(
            label,
            style: (dense ? text.labelSmall : text.labelMedium)!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final radius = BorderRadius.circular(SagipRadius.chip);
    final padding = EdgeInsets.symmetric(horizontal: dense ? 8 : 10);
    return switch (look) {
      ChipLook.tint => Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(color: tone.tint, borderRadius: radius),
        child: content,
      ),
      ChipLook.outline => Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          border: Border.all(color: tone.text),
          borderRadius: radius,
        ),
        child: content,
      ),
      ChipLook.dashed => CustomPaint(
        painter: DashedRRectPainter(
          color: SagipPalette.of(context).hairlineStrong,
          radius: SagipRadius.chip,
        ),
        child: Container(height: height, padding: padding, child: content),
      ),
    };
  }
}

/// Paints a dashed rounded-rectangle outline.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.color,
    this.radius = SagipRadius.chip,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
