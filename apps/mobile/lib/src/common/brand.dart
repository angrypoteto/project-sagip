import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The S.A.G.I.P. mark: the red SOS circle with two soft rings, the same
/// shape as the app icon.
class SagipMark extends StatelessWidget {
  const SagipMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    Widget ring(double f, double alpha) => Container(
      width: size * f,
      height: size * f,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SagipColors.signal.withValues(alpha: alpha),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring(1, 0.14),
          ring(0.8, 0.25),
          ring(0.6, 1),
          Container(
            width: size * 0.24,
            height: size * 0.24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
