import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  // The live model's rule (supabase/data/forecast_live_v1.json).
  final rule = ForecastRule.fromJson({
    'high': {'probability': 0.5, 'density': 0.5},
    'moderate': [
      {'probability': 0.5, 'density': 0.2},
      {'probability': 0.25, 'density': 0.5},
    ],
  });

  test('the rule gives the level and says which part did', () {
    expect(rule.levelOf(0.6, 0.7), RiskLevel.high);
    expect(rule.matched(0.6, 0.7), rule.high);
    expect(rule.levelOf(0.6, 0.3), RiskLevel.moderate);
    expect(rule.matched(0.6, 0.3), rule.moderate.first);
    expect(rule.levelOf(0.3, 0.6), RiskLevel.moderate);
    expect(rule.matched(0.3, 0.6), rule.moderate.last);
    expect(rule.levelOf(0.1, 1), RiskLevel.low);
    expect(rule.levelOf(0.6, 0.1), RiskLevel.low);
    expect(rule.matched(0.6, 0.1), isNull);
    expect(rule.lowestChance, 0.25);
  });

  test('a run takes its chances and rule from forecast_run_detail', () {
    final at = DateTime.utc(2026, 11, 2);
    final run = ForecastRun.latest([
      BarangayForecast(
        barangay: 'Barangay 412',
        district: 'Sampaloc',
        issuedAt: at,
        validUntil: at.add(const Duration(hours: 72)),
        risks: const {ForecastHazard.flood: RiskLevel.low},
      ),
    ])!;
    expect(run.chances, isNull);
    final detailed = run.withDetail({
      'probabilities': {'flood': 0.31, 'fire': 0.6, 'storm_surge': 0.0002},
      'rule': {
        'high': {'probability': 0.5, 'density': 0.5},
        'moderate': [
          {'probability': 0.5, 'density': 0.2},
        ],
      },
    });
    expect(detailed.chances![ForecastHazard.flood], 0.31);
    expect(detailed.chances![ForecastHazard.stormSurge], 0.0002);
    expect(detailed.rule!.moderate, hasLength(1));
    expect(detailed.forecasts, run.forecasts);
  });

  test('a run names the hazards its model does not forecast', () {
    const v2 =
        'lstm-kde-v2 live weather, 14 days to 2026-11-01 (trained on '
        'recorded data 2021 to 2026; storm surge not forecast; provisional '
        'levels)';
    expect(forecastsHazard(v2, ForecastHazard.flood), isTrue);
    expect(forecastsHazard(v2, ForecastHazard.fire), isTrue);
    expect(forecastsHazard(v2, ForecastHazard.stormSurge), isFalse);
    expect(forecastsHazard(null, ForecastHazard.stormSurge), isTrue);
    expect(forecastsHazard('sample', ForecastHazard.stormSurge), isTrue);
    final f = BarangayForecast(
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      issuedAt: DateTime(2026, 11, 2),
      validUntil: DateTime(2026, 11, 5),
      risks: const {},
      modelVersion: v2,
    );
    expect(f.covers(ForecastHazard.stormSurge), isFalse);
    expect(ForecastRun.latest([f])!.covers(ForecastHazard.stormSurge), isFalse);
  });
}
