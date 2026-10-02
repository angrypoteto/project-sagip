import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

WeatherStatus reading(int signal, double rain, [double? surge]) =>
    WeatherStatus(
      signalLevel: signal,
      rainfallMmPerHour: rain,
      stormSurgeMeters: surge,
      issuedAt: DateTime(2026, 10, 2, 9),
    );

void main() {
  group('thresholds', () {
    const t = AlertThresholds();

    test('a reading is a warning from its threshold and critical above', () {
      expect(t.levelOf(WeatherHazard.rainfall, 14.9), isNull);
      expect(t.levelOf(WeatherHazard.rainfall, 15), AlertLevel.warning);
      expect(t.levelOf(WeatherHazard.rainfall, 29.9), AlertLevel.warning);
      expect(t.levelOf(WeatherHazard.rainfall, 30), AlertLevel.critical);
      expect(t.levelOf(WeatherHazard.signal, 0), isNull);
      expect(t.levelOf(WeatherHazard.signal, 2), AlertLevel.warning);
      expect(t.levelOf(WeatherHazard.signal, 3), AlertLevel.critical);
      expect(t.levelOf(WeatherHazard.surge, null), isNull);
      expect(t.levelOf(WeatherHazard.surge, 1), isNull);
      expect(t.levelOf(WeatherHazard.surge, 1.1), AlertLevel.warning);
      expect(t.levelOf(WeatherHazard.surge, 2.5), AlertLevel.critical);
    });

    test('they come from the A3 settings, as the migration seeds them', () {
      final fromDb = AlertThresholds.fromSettings(defaultOtherSettings);
      expect(fromDb.rainfallWarning, 15);
      expect(fromDb.rainfallCritical, 30);
      expect(fromDb.signalWarning, 1);
      expect(fromDb.signalCritical, 3);
      expect(fromDb.surgeWarning, 1.1);
      expect(fromDb.surgeCritical, 2.1);
      final changed = AlertThresholds.fromSettings([
        for (final s in defaultOtherSettings)
          s.key == SettingKeys.rainfallWarning ? s.copyWith(value: 20) : s,
      ]);
      expect(changed.levelOf(WeatherHazard.rainfall, 18), isNull);
      // Switches and text in the same table are not thresholds or weights.
      expect(PriorityRules.fromSettings(defaultOtherSettings).sosPoints, 50);
    });

    // The same sequence as the RLS test runs against the database.
    test('the engine compares each reading with the one before', () {
      final sample = reading(2, 18);
      expect(
        t.changes(null, sample),
        isEmpty,
        reason: 'the first reading only sets the baseline',
      );

      final typhoon = reading(3, 35, 2.5);
      expect(
        [for (final c in t.changes(sample, typhoon)) (c.hazard, c.level)],
        [
          (WeatherHazard.rainfall, AlertLevel.critical),
          (WeatherHazard.signal, AlertLevel.critical),
          (WeatherHazard.surge, AlertLevel.critical),
        ],
      );
      expect(
        t.changes(typhoon, reading(4, 40, 3)),
        isEmpty,
        reason: 'the same level raises nothing new',
      );
      expect(
        [
          for (final c in t.changes(typhoon, reading(0, 2)))
            (c.hazard, c.level),
        ],
        [
          (WeatherHazard.rainfall, null),
          (WeatherHazard.signal, null),
          (WeatherHazard.surge, null),
        ],
        reason: 'easing below the warning threshold expires the alerts',
      );
      expect(
        [
          for (final c in t.changes(reading(1, 2), reading(3, 2)))
            (c.hazard, c.level),
        ],
        [(WeatherHazard.signal, AlertLevel.critical)],
      );
    });

    test('the alert text matches the database', () {
      final rain = weatherAlertText(
        WeatherHazard.rainfall,
        AlertLevel.warning,
        22,
      );
      expect(rain.title, 'Heavy rainfall warning');
      expect(
        rain.body,
        'PAGASA reports rain of 22 mm per hour over Manila. Flooding is '
        'possible in low-lying areas.',
      );
      expect(rain.guidance, hasLength(3));
      final signal = weatherAlertText(
        WeatherHazard.signal,
        AlertLevel.critical,
        3,
      );
      expect(signal.title, 'Wind Signal No. 3 raised over Manila');
      expect(signal.body, contains('Destructive winds are expected.'));
      final surge = weatherAlertText(
        WeatherHazard.surge,
        AlertLevel.critical,
        2.5,
      );
      expect(
        surge.body,
        'A storm surge of up to 2.5 m is expected along Manila Bay. Coastal '
        'areas may flood quickly.',
      );
    });
  });

  group('setting checks follow set_setting', () {
    final all = {
      for (final s in [...defaultPrioritySettings, ...defaultOtherSettings])
        s.key: s,
    };

    test('a setting keeps its type', () {
      expect(checkSetting(all, SettingKeys.simulation, true), isNull);
      expect(
        checkSetting(all, SettingKeys.simulation, 1),
        ActionRejection.invalidValue,
      );
      expect(
        checkSetting(all, 'priority.sos', 'sixty'),
        ActionRejection.invalidValue,
      );
      expect(checkSetting(all, 'alerts.nope', 1), ActionRejection.notFound);
    });

    test('a warning stays at or below its critical value', () {
      expect(
        checkSetting(all, SettingKeys.rainfallWarning, 40),
        ActionRejection.invalidValue,
      );
      expect(checkSetting(all, SettingKeys.rainfallWarning, 20), isNull);
      expect(
        checkSetting(all, SettingKeys.signalCritical, 0),
        ActionRejection.invalidValue,
        reason: 'below its range',
      );
      expect(
        checkSetting(all, SettingKeys.surgeCritical, 1),
        ActionRejection.invalidValue,
        reason: 'below the warning value',
      );
      expect(
        checkSetting(all, 'priority.high_at', 90),
        ActionRejection.invalidValue,
      );
    });

    test('the gateway is a Philippine mobile number; the hotline, digits', () {
      expect(
        checkSetting(all, SettingKeys.smsGateway, '0917 555 0199'),
        isNull,
      );
      expect(checkSetting(all, SettingKeys.smsGateway, ''), isNull);
      expect(
        checkSetting(all, SettingKeys.smsGateway, '12345'),
        ActionRejection.invalidValue,
      );
      expect(
        normalizeSetting(SettingKeys.smsGateway, ' 0917 555 0199 '),
        '+639175550199',
      );
      expect(checkSetting(all, SettingKeys.hotline, '(02) 8527-0000'), isNull);
      expect(
        checkSetting(all, SettingKeys.hotline, 'call us'),
        ActionRejection.invalidValue,
      );
      expect(normalizeSetting(SettingKeys.hotline, ' 911 '), '911');
    });
  });

  group('the mock follows the database', () {
    late MockBackend backend;
    late MockAuthRepository auth;
    late MockSettingsRepository settings;
    late MockSimulationRepository simulation;
    late MockAlertLogRepository log;

    setUp(() async {
      backend = MockBackend(latency: Duration.zero);
      auth = MockAuthRepository(backend);
      settings = MockSettingsRepository(backend);
      simulation = MockSimulationRepository(backend);
      log = MockAlertLogRepository(backend);
      await auth.signIn(
        email: 'admin@sagip.test',
        password: MockSeed.demoPassword,
      );
    });

    tearDown(() => backend.dispose());

    Future<List<SentAlert>> automatic() async => [
      for (final a in await log.watchRecent().first)
        if (a.alert.hazard != null) a,
    ];

    test('the sample alerts are in the apps and were never sent', () async {
      final all = await log.watchRecent().first;
      expect(all, hasLength(4));
      for (final a in all) {
        expect(a.on(AlertChannel.app)!.status, AlertDeliveryStatus.sent);
        expect(a.on(AlertChannel.sms)!.status, AlertDeliveryStatus.simulated);
      }
    });

    test('simulated weather needs simulation mode and an admin', () async {
      await expectLater(
        simulation.simulateWeather(signal: 3, rainfallMmPerHour: 35),
        rejected(ActionRejection.notAllowed),
      );
      await settings.set(SettingKeys.simulation, true);
      await expectLater(
        simulation.simulateWeather(signal: 9, rainfallMmPerHour: 35),
        rejected(ActionRejection.invalidValue),
      );
      await auth.signOut();
      await auth.signIn(
        email: 'dispatcher@sagip.test',
        password: MockSeed.demoPassword,
      );
      await expectLater(
        simulation.simulateWeather(signal: 3, rainfallMmPerHour: 35),
        rejected(ActionRejection.notAllowed),
      );
    });

    test(
      'a simulated typhoon raises simulated alerts, then they expire',
      () async {
        await settings.set(SettingKeys.simulation, true);
        // The sample reading is signal 2 and 18 mm/hr.
        await simulation.simulateWeather(
          signal: 3,
          rainfallMmPerHour: 35,
          surgeMeters: 2.5,
        );
        var raised = await automatic();
        expect(
          {for (final a in raised) (a.alert.hazard, a.alert.level)},
          {
            (WeatherHazard.rainfall, AlertLevel.critical),
            (WeatherHazard.signal, AlertLevel.critical),
            (WeatherHazard.surge, AlertLevel.critical),
          },
        );
        for (final a in raised) {
          expect(a.alert.isSimulated, isTrue);
          expect(a.alert.source, AlertSource.pagasa);
          expect(
            [for (final d in a.deliveries) d.status],
            [
              AlertDeliveryStatus.sent,
              AlertDeliveryStatus.simulated,
              AlertDeliveryStatus.simulated,
              AlertDeliveryStatus.simulated,
            ],
            reason: 'shown in the apps, never texted or posted',
          );
        }
        final weather = await MockWeatherRepository(backend)
            .watchCurrent()
            .first;
        expect(weather.signalLevel, 3);
        expect(weather.stormSurgeMeters, 2.5);
        expect(weather.isSimulated, isTrue);

        // The same level again: nothing new.
        await simulation.simulateWeather(
          signal: 4,
          rainfallMmPerHour: 40,
          surgeMeters: 3,
        );
        expect(await automatic(), hasLength(3));

        // Conditions ease: every automatic alert expires.
        await simulation.simulateWeather(signal: 0, rainfallMmPerHour: 2);
        raised = await automatic();
        expect(raised, hasLength(3));
        expect(raised.every((a) => a.alert.expiresAt != null), isTrue);

        // A warning that becomes critical is replaced, not doubled.
        await simulation.simulateWeather(signal: 1, rainfallMmPerHour: 2);
        await simulation.simulateWeather(signal: 3, rainfallMmPerHour: 2);
        final now = DateTime.now().add(const Duration(seconds: 1));
        final active = [
          for (final a in await automatic())
            if (a.alert.hazard == WeatherHazard.signal && a.alert.activeAt(now))
              a.alert.level,
        ];
        expect(active, [AlertLevel.critical]);

        final audit = await MockAuditRepository(backend).watchRecent().first;
        expect(
          audit
              .where((e) => e.action == AuditAction.weatherSimulated)
              .map((e) => e.detail),
          contains('Signal 3, 35 mm/hr, surge 2.5 m'),
        );
      },
    );

    test('switches and numbers are settings like any other', () async {
      await settings.set(SettingKeys.smsChannel, false);
      await settings.set(SettingKeys.smsGateway, '0917 555 0199');
      await settings.set(SettingKeys.hotline, '(02) 8527-0000');
      await expectLater(
        settings.set(SettingKeys.smsGateway, '12345'),
        rejected(ActionRejection.invalidValue),
      );
      await expectLater(
        settings.set(SettingKeys.smsChannel, 0),
        rejected(ActionRejection.invalidValue),
      );
      final config = await MockClientConfigRepository(backend).fetch();
      expect(config.smsGateway, '+639175550199');
      expect(config.hotline, '(02) 8527-0000');

      final audit = await MockAuditRepository(backend).watchRecent().first;
      final details = {
        for (final e in audit)
          if (e.action == AuditAction.settingChanged) e.targetId: e.detail,
      };
      expect(details[SettingKeys.smsChannel], 'true → false');
      expect(details[SettingKeys.smsGateway], ' → +639175550199');
    });
  });

  group('rows from the database', () {
    test('settings can be numbers, switches, or text', () {
      final rows = [
        {
          'key': 'alerts.surge_warning',
          'category': 'alerts',
          'value': 1.1,
          'min_value': 0.1,
          'max_value': 10,
          'description':
              'Storm surge height in metres that raises a warning alert',
          'updated_at': '2026-10-02T01:00:00+00:00',
          'updated_by': null,
        },
        {
          'key': 'channels.facebook',
          'category': 'channels',
          'value': false,
          'min_value': null,
          'max_value': null,
          'description': 'Post alerts on the MDRRMD Facebook Page',
          'updated_at': '2026-10-02T01:00:00+00:00',
          'updated_by': null,
        },
        {
          'key': 'contact.hotline',
          'category': 'contact',
          'value': '',
          'min_value': null,
          'max_value': null,
          'description': 'The MDRRMD hotline the apps show',
          'updated_at': '2026-10-02T01:00:00+00:00',
          'updated_by': 'E. Navarro',
        },
      ];
      final parsed = [for (final r in rows) AppSetting.fromJson(r)];
      expect(parsed[0].number, 1.1);
      expect(parsed[1].flag, isFalse);
      expect(parsed[2].text, '');
      expect(AppSetting.fromJson(parsed[1].toJson()).flag, isFalse);
    });

    test('a public_alert row with its deliveries, and client_config', () {
      final sent = SentAlert.fromJson({
        'alert_id': 'alert-0b0c',
        'source': 'pagasa',
        'level': 'warning',
        'title': 'Heavy rainfall warning',
        'body': 'PAGASA reports rain of 22 mm per hour over Manila.',
        'guidance': ['Move appliances and important papers to a higher place.'],
        'barangays': <String>[],
        'issued_at': '2026-10-02T01:00:00+00:00',
        'expires_at': null,
        'is_simulated': false,
        'hazard': 'rainfall',
        'weather_alert_id': 12,
        'alert_delivery': [
          {'channel': 'sms', 'status': 'off', 'recipients': null},
          {'channel': 'app', 'status': 'sent'},
          {'channel': 'facebook', 'status': 'off'},
          {
            'channel': 'push',
            'status': 'queued',
            'recipients': null,
            'delivered': null,
            'failed': null,
            'detail': null,
          },
        ],
      });
      expect(sent.alert.hazard, WeatherHazard.rainfall);
      expect(sent.alert.isSimulated, isFalse);
      expect(sent.alert.activeAt(DateTime.now()), isTrue);
      expect(
        [for (final d in sent.deliveries) (d.channel, d.status)],
        [
          (AlertChannel.app, AlertDeliveryStatus.sent),
          (AlertChannel.push, AlertDeliveryStatus.queued),
          (AlertChannel.sms, AlertDeliveryStatus.off),
          (AlertChannel.facebook, AlertDeliveryStatus.off),
        ],
      );

      // The sender's outcomes: counts, a note, and the two later statuses.
      final outcomes = SentAlert.fromJson({
        'alert_id': 'alert-0b0d',
        'source': 'mdrrmd',
        'level': 'warning',
        'title': 'Flooding on Dapitan St',
        'body': 'Avoid the area.',
        'issued_at': '2026-10-02T01:00:00+00:00',
        'alert_delivery': [
          {'channel': 'app', 'status': 'sent'},
          {
            'channel': 'sms',
            'status': 'sent',
            'recipients': 120,
            'delivered': 100,
            'failed': 20,
            'detail': '20 not sent: the daily limit was reached',
          },
          {'channel': 'push', 'status': 'sending'},
          {'channel': 'facebook', 'status': 'ended'},
        ],
      });
      final sms = outcomes.on(AlertChannel.sms)!;
      expect((sms.recipients, sms.delivered, sms.failed), (120, 100, 20));
      expect(sms.detail, '20 not sent: the daily limit was reached');
      expect(
        outcomes.on(AlertChannel.push)!.status,
        AlertDeliveryStatus.sending,
      );
      expect(
        outcomes.on(AlertChannel.facebook)!.status,
        AlertDeliveryStatus.ended,
      );
      final cap = defaultOtherSettings.firstWhere(
        (s) => s.key == SettingKeys.smsDailyCap,
      );
      expect((cap.number, cap.min, cap.max), (500, 0, 100000));

      final config = ClientConfig.fromJson({
        'hotline': '(02) 8527-0000',
        'sms_gateway': '+639175550199',
      });
      expect(config.hotline, '(02) 8527-0000');
      expect(config.smsGateway, '+639175550199');

      final weather = WeatherStatus.fromJson({
        'signal_level': 3,
        'rainfall_intensity': 35.0,
        'storm_surge_advisory':
            'Storm surge up to 2.5 m possible along Manila Bay',
        'storm_surge_m': 2.5,
        'issued_at': '2026-10-02T01:00:00+00:00',
        'is_simulated': true,
      });
      expect(weather.stormSurgeMeters, 2.5);
      // A reading from before the column existed.
      expect(
        WeatherStatus.fromJson({
          'signal_level': 2,
          'rainfall_intensity': 18,
          'storm_surge_advisory': null,
          'issued_at': '2026-10-02T01:00:00+00:00',
        }).stormSurgeMeters,
        isNull,
      );
    });
  });
}
