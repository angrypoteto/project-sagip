import 'package:material_ui/material_ui.dart';

import 'sagip_colors.dart';

/// One signal color prepared for the three ways the UI uses it.
@immutable
class SagipTone {
  const SagipTone({required this.fill, required this.text, required this.tint});

  /// Solid color for dots, map markers, edges and icons without text.
  final Color fill;

  /// Color for text and icons drawn on [tint] or on the page surface.
  /// Always passes WCAG AA in its theme.
  final Color text;

  /// Low-opacity background for chips and highlighted rows.
  final Color tint;

  static SagipTone lerp(SagipTone a, SagipTone b, double t) => SagipTone(
    fill: Color.lerp(a.fill, b.fill, t)!,
    text: Color.lerp(a.text, b.text, t)!,
    tint: Color.lerp(a.tint, b.tint, t)!,
  );
}

/// S.A.G.I.P. colors that the Material [ColorScheme] has no slot for.
///
/// Read with `SagipPalette.of(context)`.
@immutable
class SagipPalette extends ThemeExtension<SagipPalette> {
  const SagipPalette({
    required this.canvas,
    required this.panel,
    required this.panelRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.hairline,
    required this.hairlineStrong,
    required this.critical,
    required this.warning,
    required this.success,
    required this.info,
    required this.onScene,
    required this.neutral,
  });

  /// Deepest background (page behind panels).
  final Color canvas;

  /// Raised surface: panels, sheets, cards.
  final Color panel;

  /// Highest surface: selected rows, hover, grouped sections inside a panel.
  final Color panelRaised;

  final Color textPrimary;
  final Color textSecondary;

  /// 1 px dividers and borders.
  final Color hairline;

  /// Borders of controls such as outlined buttons and inputs.
  final Color hairlineStrong;

  /// SOS, confirmed incidents, critical severity.
  final SagipTone critical;

  /// Pending verification, weather warnings, high severity.
  final SagipTone warning;

  /// Available units, resolved incidents, delivered records.
  final SagipTone success;

  /// Primary actions, assigned and en route.
  final SagipTone info;

  /// On scene only.
  final SagipTone onScene;

  /// Unverified reports and normal severity.
  final SagipTone neutral;

  static SagipPalette of(BuildContext context) =>
      Theme.of(context).extension<SagipPalette>()!;

  static const light = SagipPalette(
    canvas: SagipColors.mist,
    panel: SagipColors.porcelain,
    panelRaised: Color(0xFFF4F7F9),
    textPrimary: SagipColors.ink,
    textSecondary: SagipColors.slate,
    hairline: Color(0x140F1C2A),
    hairlineStrong: Color(0x290F1C2A),
    critical: SagipTone(
      fill: SagipColors.signal,
      text: SagipColors.signalStrong,
      tint: Color(0x1FE5323F),
    ),
    warning: SagipTone(
      fill: SagipColors.ember,
      text: SagipColors.emberInk,
      tint: Color(0x29F5A524),
    ),
    success: SagipTone(
      fill: SagipColors.verdant,
      text: SagipColors.verdantInk,
      tint: Color(0x2419A06B),
    ),
    info: SagipTone(
      fill: SagipColors.tide,
      text: SagipColors.tideStrong,
      tint: Color(0x1F2E7CD6),
    ),
    onScene: SagipTone(
      fill: SagipColors.dusk,
      text: SagipColors.duskInk,
      tint: Color(0x247C5CD6),
    ),
    neutral: SagipTone(
      fill: SagipColors.slate,
      text: SagipColors.slate,
      tint: Color(0x0F0F1C2A),
    ),
  );

  static const dark = SagipPalette(
    canvas: SagipColors.bay,
    panel: SagipColors.harbor,
    panelRaised: SagipColors.harborHigh,
    textPrimary: SagipColors.fog,
    textSecondary: SagipColors.haze,
    hairline: Color(0x14FFFFFF),
    hairlineStrong: Color(0x29FFFFFF),
    critical: SagipTone(
      fill: SagipColors.signal,
      text: SagipColors.signalLight,
      tint: Color(0x2EE5323F),
    ),
    warning: SagipTone(
      fill: SagipColors.ember,
      text: SagipColors.ember,
      tint: Color(0x29F5A524),
    ),
    success: SagipTone(
      fill: SagipColors.verdant,
      text: SagipColors.verdantLight,
      tint: Color(0x2E19A06B),
    ),
    info: SagipTone(
      fill: SagipColors.tide,
      text: SagipColors.tideLight,
      tint: Color(0x332E7CD6),
    ),
    onScene: SagipTone(
      fill: SagipColors.dusk,
      text: SagipColors.duskLight,
      tint: Color(0x387C5CD6),
    ),
    neutral: SagipTone(
      fill: SagipColors.haze,
      text: SagipColors.haze,
      tint: Color(0x0FFFFFFF),
    ),
  );

  @override
  SagipPalette copyWith({
    Color? canvas,
    Color? panel,
    Color? panelRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? hairline,
    Color? hairlineStrong,
    SagipTone? critical,
    SagipTone? warning,
    SagipTone? success,
    SagipTone? info,
    SagipTone? onScene,
    SagipTone? neutral,
  }) {
    return SagipPalette(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      panelRaised: panelRaised ?? this.panelRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      critical: critical ?? this.critical,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      info: info ?? this.info,
      onScene: onScene ?? this.onScene,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  SagipPalette lerp(SagipPalette? other, double t) {
    if (other == null) return this;
    return SagipPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      critical: SagipTone.lerp(critical, other.critical, t),
      warning: SagipTone.lerp(warning, other.warning, t),
      success: SagipTone.lerp(success, other.success, t),
      info: SagipTone.lerp(info, other.info, t),
      onScene: SagipTone.lerp(onScene, other.onScene, t),
      neutral: SagipTone.lerp(neutral, other.neutral, t),
    );
  }
}
