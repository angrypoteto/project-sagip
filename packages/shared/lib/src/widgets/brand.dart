import 'package:material_ui/material_ui.dart';

/// The system's mark: Manila MDRRMD's seal (Joshua, 2026-11-10: "instead of
/// using our own logo ... use the logo of the mdrrmd"). Replaced the red SOS
/// circle on the splash, sign-in, dashboard bar, and resident web form; the
/// app and website icons use the same seal.
class SagipMark extends StatelessWidget {
  const SagipMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/mdrrmd_logo.png',
    package: 'sagip_shared',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Manila City DRRM Department',
    // A blank square of the same size if the image cannot load, so the
    // layout around it does not jump.
    errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
  );
}
