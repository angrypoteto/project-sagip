import 'dart:ui' show Color;

/// Raw S.A.G.I.P. palette from the `sagip-flutter-design` skill.
///
/// Widgets should not read these directly. Use the theme instead:
/// `Theme.of(context).colorScheme` for neutrals and `SagipPalette.of(context)`
/// for signal colors, so light and dark mode stay correct.
abstract final class SagipColors {
  // Neutrals (the canvas).
  static const bay = Color(0xFF0B1724);
  static const harbor = Color(0xFF132436);
  static const harborHigh = Color(0xFF1B3047);
  static const mist = Color(0xFFEEF2F5);
  static const porcelain = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F1C2A);
  static const slate = Color(0xFF5B6B7B);

  // Text on dark surfaces. `slate` fails contrast on `bay`, so dark mode
  // uses these instead.
  static const fog = Color(0xFFE8EEF3);
  static const haze = Color(0xFF9AA8B6);

  // Signals (meaning only).
  static const signal = Color(0xFFE5323F);
  static const ember = Color(0xFFF5A524);
  static const verdant = Color(0xFF19A06B);
  static const tide = Color(0xFF2E7CD6);
  static const dusk = Color(0xFF7C5CD6);

  // Text-safe variants for light surfaces (plan section 7.5). The base
  // signals fail WCAG AA as text at body sizes. Values are tuned so text
  // passes 4.5:1 on its chip tint over every surface; test/contrast_test.dart
  // checks this.
  static const signalStrong = Color(0xFFB8232E);
  static const tideStrong = Color(0xFF1C5FB5);
  static const emberInk = Color(0xFF8A5300);
  static const verdantInk = Color(0xFF0C6E48);
  static const duskInk = Color(0xFF5B3FB8);

  // Text-safe variants for dark surfaces.
  static const signalLight = Color(0xFFFF858A);
  static const tideLight = Color(0xFF7DB4F3);
  static const verdantLight = Color(0xFF3CCB8E);
  static const duskLight = Color(0xFFB3A0F0);
}
