import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Where a step stands in a vertical timeline (R2 SOS status, R6 report
/// detail).
enum TimelineState { done, current, later }

/// One row of a vertical timeline: a check, ring, or empty circle joined
/// to the next row by a line, then the label and an optional time.
class TimelineStep extends StatelessWidget {
  const TimelineStep({
    super.key,
    required this.label,
    required this.time,
    required this.state,
    required this.last,
  });

  final String label;
  final String? time;
  final TimelineState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final (icon, color) = switch (state) {
      TimelineState.done => (Symbols.check_circle_rounded, p.success.text),
      TimelineState.current => (
        Symbols.radio_button_checked_rounded,
        p.info.text,
      ),
      TimelineState.later => (
        Symbols.radio_button_unchecked_rounded,
        p.hairline,
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 22, color: color, fill: 1),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: state == TimelineState.done
                        ? p.success.text
                        : p.hairline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: SagipSpace.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodyLarge!.copyWith(
                        color: state == TimelineState.later
                            ? p.textSecondary
                            : p.textPrimary,
                        fontWeight: state == TimelineState.current
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (time != null)
                    Text(
                      time!,
                      style: text.bodySmall!.copyWith(
                        color: p.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
