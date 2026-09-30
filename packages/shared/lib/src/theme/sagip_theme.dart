import 'package:material_ui/material_ui.dart';

import 'sagip_colors.dart';
import 'sagip_palette.dart';
import 'sagip_tokens.dart';

/// Which type scale to use. The dashboard is denser than the phone app.
enum SagipDensity { mobile, dashboard }

/// Builds the light and dark [ThemeData] for both apps from the design tokens.
///
/// Every component that shows up on S.A.G.I.P. screens is overridden here so
/// no default Material look leaks through.
abstract final class SagipTheme {
  static ThemeData light(SagipDensity density) =>
      _build(Brightness.light, density);

  static ThemeData dark(SagipDensity density) =>
      _build(Brightness.dark, density);

  static ThemeData _build(Brightness brightness, SagipDensity density) {
    final isDark = brightness == Brightness.dark;
    final p = isDark ? SagipPalette.dark : SagipPalette.light;

    // Filled buttons keep white text on the darker blue in both themes;
    // links and text buttons use the lighter blue in dark mode for contrast.
    const actionFill = SagipColors.tideStrong;
    final actionText = p.info.text;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: actionText,
      onPrimary: isDark ? SagipColors.bay : SagipColors.porcelain,
      secondary: actionText,
      onSecondary: isDark ? SagipColors.bay : SagipColors.porcelain,
      error: p.critical.text,
      onError: isDark ? SagipColors.bay : SagipColors.porcelain,
      surface: p.panel,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.canvas,
      surfaceContainerLow: p.panel,
      surfaceContainer: p.panel,
      surfaceContainerHigh: p.panelRaised,
      surfaceContainerHighest: p.panelRaised,
      outline: p.hairlineStrong,
      outlineVariant: p.hairline,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: isDark ? SagipColors.fog : SagipColors.ink,
      onInverseSurface: isDark ? SagipColors.ink : SagipColors.fog,
    );

    final text = _textTheme(density, p.textPrimary, p.textSecondary);
    final controlRadius = BorderRadius.circular(SagipRadius.control);
    final cardRadius = BorderRadius.circular(SagipRadius.card);
    final buttonHeight = density == SagipDensity.mobile ? 52.0 : 44.0;
    final buttonText = text.labelLarge!;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: kSagipFontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.panel,
      dividerColor: p.hairline,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: [p],
      iconTheme: IconThemeData(
        color: p.textSecondary,
        size: density == SagipDensity.mobile ? 24 : 20,
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actionFill,
          foregroundColor: SagipColors.porcelain,
          disabledBackgroundColor: p.hairline,
          disabledForegroundColor: p.textSecondary,
          minimumSize: Size(64, buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
          shape: RoundedRectangleBorder(borderRadius: cardRadius),
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: Size(48, buttonHeight - 8),
          padding: const EdgeInsets.symmetric(horizontal: SagipSpace.lg),
          side: BorderSide(color: p.hairlineStrong),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: actionText,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: SagipSpace.md),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textSecondary,
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? SagipColors.bay : SagipColors.porcelain,
        isDense: density == SagipDensity.dashboard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SagipSpace.md,
          vertical: SagipSpace.md,
        ),
        labelStyle: text.labelMedium,
        floatingLabelStyle: text.labelMedium,
        hintStyle: text.bodyMedium!.copyWith(color: p.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          borderSide: BorderSide(color: p.hairlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          borderSide: BorderSide(color: p.hairlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          borderSide: BorderSide(color: p.info.fill, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          borderSide: BorderSide(color: p.critical.text),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(color: p.hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SagipRadius.sheet),
          side: BorderSide(color: p.hairline),
        ),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.textSecondary),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.canvas,
        indicatorColor: p.info.tint,
        indicatorShape: RoundedRectangleBorder(borderRadius: cardRadius),
        selectedIconTheme: IconThemeData(color: p.info.text, size: 20),
        unselectedIconTheme: IconThemeData(color: p.textSecondary, size: 20),
        selectedLabelTextStyle: text.labelSmall!.copyWith(color: p.info.text),
        unselectedLabelTextStyle: text.labelSmall,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? SagipColors.harborHigh : SagipColors.ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: SagipColors.fog),
        actionTextColor: SagipColors.tideLight,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? SagipColors.fog : SagipColors.ink,
          borderRadius: BorderRadius.circular(SagipRadius.chip),
        ),
        textStyle: text.bodySmall!.copyWith(
          color: isDark ? SagipColors.ink : SagipColors.fog,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelMedium!.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: text.bodyMedium,
        dividerThickness: 1,
        headingRowHeight: 44,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: p.info.tint,
        side: BorderSide(color: p.hairlineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
        ),
        labelStyle: text.labelMedium,
        showCheckmark: false,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panelRaised,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(color: p.hairline),
        ),
        textStyle: text.bodyMedium,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? actionFill
              : Colors.transparent,
        ),
        side: BorderSide(color: p.hairlineStrong, width: 1.5),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.hairlineStrong),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.info.fill,
        linearTrackColor: p.hairline,
      ),
    );
  }

  static TextTheme _textTheme(
    SagipDensity density,
    Color primary,
    Color secondary,
  ) {
    final mobile = density == SagipDensity.mobile;
    TextStyle style(
      double size,
      FontWeight weight, {
      Color? color,
      double height = 1.5,
    }) {
      // Tighter tracking on large sizes, per the design skill.
      final tracking = size >= 40 ? -1.0 : (size >= 24 ? -0.5 : 0.0);
      return TextStyle(
        fontFamily: kSagipFontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color ?? primary,
      );
    }

    return TextTheme(
      // Hero numbers: ETAs, counts.
      displaySmall: style(mobile ? 48 : 32, FontWeight.w700, height: 1.1),
      headlineSmall: style(mobile ? 28 : 22, FontWeight.w700, height: 1.2),
      titleLarge: style(mobile ? 22 : 19, FontWeight.w700, height: 1.25),
      titleMedium: style(mobile ? 20 : 17, FontWeight.w600, height: 1.25),
      titleSmall: style(mobile ? 16 : 14, FontWeight.w600, height: 1.4),
      bodyLarge: style(mobile ? 16 : 15, FontWeight.w400),
      bodyMedium: style(mobile ? 16 : 14, FontWeight.w400),
      bodySmall: style(mobile ? 13 : 12, FontWeight.w400, color: secondary),
      labelLarge: style(mobile ? 15 : 14, FontWeight.w600, height: 1.2),
      labelMedium: style(mobile ? 14 : 13, FontWeight.w500, height: 1.3),
      labelSmall: style(mobile ? 13 : 12, FontWeight.w500, height: 1.3),
    );
  }
}
