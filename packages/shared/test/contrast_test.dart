import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A translucent color painted over an opaque background.
Color over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

/// Automated contrast audit (plan 7.8): every text and background pair the
/// design system uses must pass WCAG AA (4.5:1) for normal-size text.
void main() {
  const aa = 4.5;

  for (final (name, p) in [
    ('light', SagipPalette.light),
    ('dark', SagipPalette.dark),
  ]) {
    group('$name theme', () {
      test('body text passes on every surface', () {
        for (final surface in [p.canvas, p.panel, p.panelRaised]) {
          expect(contrast(p.textPrimary, surface), greaterThanOrEqualTo(aa));
          expect(contrast(p.textSecondary, surface), greaterThanOrEqualTo(aa));
        }
      });

      test('chip text passes on its own tint', () {
        final tones = {
          'critical': p.critical,
          'warning': p.warning,
          'success': p.success,
          'info': p.info,
          'onScene': p.onScene,
          'neutral': p.neutral,
        };
        tones.forEach((tone, t) {
          for (final surface in [p.panel, p.panelRaised]) {
            final ratio = contrast(t.text, over(t.tint, surface));
            expect(
              ratio,
              greaterThanOrEqualTo(aa),
              reason: '$tone text on its tint is ${ratio.toStringAsFixed(2)}',
            );
          }
        });
      });

      test('links and text buttons pass on panels', () {
        expect(contrast(p.info.text, p.panel), greaterThanOrEqualTo(aa));
        expect(contrast(p.info.text, p.canvas), greaterThanOrEqualTo(aa));
      });
    });
  }

  test('white label on the filled action button passes', () {
    expect(
      contrast(SagipColors.porcelain, SagipColors.tideStrong),
      greaterThanOrEqualTo(aa),
    );
  });

  test(
    'the base palette really does fail as small text (why variants exist)',
    () {
      expect(contrast(SagipColors.porcelain, SagipColors.tide), lessThan(aa));
      expect(contrast(SagipColors.ember, SagipColors.porcelain), lessThan(3));
    },
  );
}
