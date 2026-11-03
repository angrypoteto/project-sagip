import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// FR4 (2026-11-03): the confusion matrix and balanced accuracy follow from
/// the test figures in the model file (lstm-kde-v2's, checked against
/// docs/OBJECTIVE-2-RESULTS.md section 9).
void main() {
  final model = MockSeed(DateTime(2026, 11, 3)).modelTest;

  test('flood: 9 of 24 caught, balanced 61.7%, never warn is the baseline', () {
    final t = model.hazards[ForecastHazard.flood]!;
    expect([t.caught, t.missed, t.falseAlarms, t.quiet], [9, 15, 41, 249]);
    expect(t.caught + t.missed + t.falseAlarms + t.quiet, t.windows);
    expect(t.balancedAccuracy, closeTo(0.617, 0.001));
    expect(t.baselineNeverWarns, isTrue);
  });

  test('fire: no skill, balanced 45.4%, always warn is the baseline', () {
    final t = model.hazards[ForecastHazard.fire]!;
    expect([t.caught, t.missed, t.falseAlarms, t.quiet], [179, 111, 17, 7]);
    expect(t.balancedAccuracy, closeTo(0.454, 0.001));
    expect(t.baselineNeverWarns, isFalse);
  });

  test('the JSON from forecast_model_test() parses; no storm surge', () {
    expect(model.version, 'lstm-kde-v2');
    expect(model.trainedFrom, DateTime(2021));
    expect(model.hazards.keys, {ForecastHazard.flood, ForecastHazard.fire});
  });
}
