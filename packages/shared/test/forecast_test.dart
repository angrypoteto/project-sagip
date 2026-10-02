import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

BarangayForecast forecast(
  String barangay,
  DateTime issued, {
  RiskLevel flood = RiskLevel.low,
  RiskLevel fire = RiskLevel.low,
  RiskLevel surge = RiskLevel.low,
  int validHours = 72,
  bool simulated = false,
  String? model,
}) => BarangayForecast(
  barangay: barangay,
  district: 'Sampaloc',
  issuedAt: issued,
  validUntil: issued.add(Duration(hours: validHours)),
  risks: {
    ForecastHazard.flood: flood,
    ForecastHazard.fire: fire,
    ForecastHazard.stormSurge: surge,
  },
  isSimulated: simulated,
  modelVersion: model,
);

void main() {
  final today = DateTime(2026, 10, 2, 6);
  final yesterday = DateTime(2026, 10, 1, 6);

  group('a forecast run', () {
    test('is the forecasts that share the newest issue time', () {
      final run = ForecastRun.latest([
        forecast('Barangay 490', today, model: 'lstm-kde-1'),
        forecast('Barangay 412', yesterday, flood: RiskLevel.high),
        forecast('Barangay 412', today, flood: RiskLevel.moderate),
        forecast('Barangay 105', today, validHours: 48, simulated: true),
      ])!;
      expect(run.issuedAt, today);
      expect(
        [for (final f in run.forecasts) f.barangay],
        ['Barangay 105', 'Barangay 412', 'Barangay 490'],
        reason: 'yesterday\'s row is not part of it; sorted by name',
      );
      expect(
        run.forBarangay('Barangay 412')!.riskOf(ForecastHazard.flood),
        RiskLevel.moderate,
      );
      expect(run.forBarangay('Barangay 306'), isNull);
      expect(
        run.validUntil,
        today.add(const Duration(hours: 48)),
        reason: 'valid only as long as every forecast in it',
      );
      expect(run.isSimulated, isTrue, reason: 'one simulated row is enough');
      expect(run.isSample, isFalse);
    });

    test('there is none before the model has run', () {
      expect(ForecastRun.latest(const []), isNull);
    });

    test('ranks the barangays for one hazard, highest first', () {
      final run = ForecastRun.latest([
        forecast('Barangay 105', today, fire: RiskLevel.high),
        forecast('Barangay 412', today, flood: RiskLevel.high),
        forecast('Barangay 490', today, flood: RiskLevel.high),
        forecast('Barangay 287', today, flood: RiskLevel.moderate),
      ])!;
      expect(
        [for (final f in run.ranked(ForecastHazard.flood)) f.barangay],
        ['Barangay 412', 'Barangay 490', 'Barangay 287', 'Barangay 105'],
      );
      expect(run.ranked(ForecastHazard.fire).first.barangay, 'Barangay 105');
      expect(run.count(ForecastHazard.flood, RiskLevel.high), 2);
      expect(run.count(ForecastHazard.flood, RiskLevel.moderate), 1);
      expect(run.count(ForecastHazard.stormSurge, RiskLevel.low), 4);
    });

    test('is overdue once it is more than 24 hours old', () {
      final run = ForecastRun.latest([forecast('Barangay 412', today)])!;
      expect(run.isStaleAt(today.add(const Duration(hours: 24))), isFalse);
      expect(
        run.isStaleAt(today.add(const Duration(hours: 24, minutes: 1))),
        isTrue,
      );
    });
  });

  group('rows and sample data', () {
    test('a barangay_forecast row carries the model that made it', () {
      final f = BarangayForecast.fromRow(const {
        'barangay': 'Barangay 412',
        'district': 'Sampaloc',
        'issued_at': '2026-10-01T22:00:00+00:00',
        'valid_until': '2026-10-04T22:00:00+00:00',
        'flood_risk': 'high',
        'fire_risk': 'low',
        'surge_risk': 'moderate',
        'model_version': 'sample',
        'is_simulated': true,
      });
      expect(f.riskOf(ForecastHazard.flood), RiskLevel.high);
      expect(f.riskOf(ForecastHazard.stormSurge), RiskLevel.moderate);
      expect(f.modelVersion, ForecastRun.sampleModel);
      // The phone keeps its copy as JSON.
      final again = BarangayForecast.fromJson(f.toJson());
      expect(again.modelVersion, 'sample');
      expect(again.risks, f.risks);
      expect(ForecastRun.latest([f])!.isSample, isTrue);
    });

    test('the mock gives the sample run of the demo data', () async {
      final now = DateTime(2026, 10, 1, 15, 42);
      final backend = MockBackend(clock: () => now, latency: Duration.zero);
      addTearDown(backend.dispose);
      final run = (await MockForecastRepository(backend).watchLatest().first)!;
      expect(run.issuedAt, DateTime(2026, 10, 1, 6), reason: 'the 6 AM run');
      expect(run.validUntil, DateTime(2026, 10, 4, 6));
      expect(run.forecasts, hasLength(8));
      expect(run.isSample, isTrue);
      expect(run.isSimulated, isTrue);
      expect(run.isStaleAt(now), isFalse);
      expect(run.count(ForecastHazard.flood, RiskLevel.high), 3);
      expect(run.forBarangay('Barangay 306'), isNull);

      backend.setForecast(null);
      expect(await MockForecastRepository(backend).watchLatest().first, isNull);
    });

    test('before 6 AM the newest run is yesterday\'s', () async {
      final backend = MockBackend(
        clock: () => DateTime(2026, 10, 2, 4, 30),
        latency: Duration.zero,
      );
      addTearDown(backend.dispose);
      final run = (await MockForecastRepository(backend).watchLatest().first)!;
      expect(run.issuedAt, DateTime(2026, 10, 1, 6));
    });
  });
}
