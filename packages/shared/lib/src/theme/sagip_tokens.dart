import 'package:flutter/animation.dart';

/// Spacing scale: 4, 8, 12, 16, 20, 24, 32, 40, 56.
abstract final class SagipSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
  static const double x5 = 56;
}

/// Corner radius by hierarchy.
abstract final class SagipRadius {
  static const double chip = 6;
  static const double control = 8;
  static const double card = 12;
  static const double sheet = 20;
}

/// Motion durations and curves.
abstract final class SagipMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const emphasis = Duration(milliseconds: 400);
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
}

/// Font family bundled in this package. Apps address a package font with the
/// `packages/<package>/` prefix.
const String kSagipFontFamily = 'packages/sagip_shared/PlusJakartaSans';
