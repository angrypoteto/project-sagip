import 'package:flutter/foundation.dart';

import '../models/alerts.dart';
import '../models/records.dart';
import '../models/settings.dart';

/// When a reading raises an alert by itself. Set by an administrator on A3
/// (`app_setting`, category `alerts`); the database's threshold engine
/// (`private.raise_weather_alerts`) uses the same values, so keep the two in
/// step. The defaults are provisional until MDRRMD confirms them: rainfall
/// follows PAGASA's heavy rainfall warnings (orange from 15 mm/hr, red from
/// 30) and storm surge follows PAGASA's risk bands.
@immutable
class AlertThresholds {
  const AlertThresholds({
    this.rainfallWarning = 15,
    this.rainfallCritical = 30,
    this.signalWarning = 1,
    this.signalCritical = 3,
    this.surgeWarning = 1.1,
    this.surgeCritical = 2.1,
  });

  /// Rainfall in mm per hour.
  final num rainfallWarning;
  final num rainfallCritical;

  /// Tropical cyclone wind signal number.
  final num signalWarning;
  final num signalCritical;

  /// Storm surge height in metres.
  final num surgeWarning;
  final num surgeCritical;

  /// Thresholds from the A3 settings; a missing value keeps its default.
  factory AlertThresholds.fromSettings(Iterable<AppSetting> settings) {
    final v = {
      for (final s in settings)
        if (s.value is num) s.key: s.number,
    };
    const d = AlertThresholds();
    return AlertThresholds(
      rainfallWarning: v[SettingKeys.rainfallWarning] ?? d.rainfallWarning,
      rainfallCritical: v[SettingKeys.rainfallCritical] ?? d.rainfallCritical,
      signalWarning: v[SettingKeys.signalWarning] ?? d.signalWarning,
      signalCritical: v[SettingKeys.signalCritical] ?? d.signalCritical,
      surgeWarning: v[SettingKeys.surgeWarning] ?? d.surgeWarning,
      surgeCritical: v[SettingKeys.surgeCritical] ?? d.surgeCritical,
    );
  }

  num warningAt(WeatherHazard hazard) => switch (hazard) {
    WeatherHazard.rainfall => rainfallWarning,
    WeatherHazard.signal => signalWarning,
    WeatherHazard.surge => surgeWarning,
  };

  num criticalAt(WeatherHazard hazard) => switch (hazard) {
    WeatherHazard.rainfall => rainfallCritical,
    WeatherHazard.signal => signalCritical,
    WeatherHazard.surge => surgeCritical,
  };

  /// Warning or critical, or null below the warning threshold (and for a
  /// reading that has no value, such as no storm surge advisory).
  AlertLevel? levelOf(WeatherHazard hazard, num? value) {
    if (value == null) return null;
    if (value >= criticalAt(hazard)) return AlertLevel.critical;
    if (value >= warningAt(hazard)) return AlertLevel.warning;
    return null;
  }

  /// The level of [hazard] in [weather].
  AlertLevel? levelIn(WeatherStatus weather, WeatherHazard hazard) =>
      levelOf(hazard, readingOf(weather, hazard));

  /// What the threshold engine does with a new reading: for each hazard
  /// whose level differs from the reading before, the new level (null when
  /// it eased below the warning threshold). The first reading only sets
  /// the baseline, so [previous] null changes nothing.
  List<({WeatherHazard hazard, AlertLevel? level, num? value})> changes(
    WeatherStatus? previous,
    WeatherStatus now,
  ) {
    if (previous == null) return const [];
    return [
      for (final h in WeatherHazard.values)
        if (levelIn(now, h) != levelIn(previous, h))
          (hazard: h, level: levelIn(now, h), value: readingOf(now, h)),
    ];
  }
}

/// The number the engine compares for [hazard].
num? readingOf(WeatherStatus weather, WeatherHazard hazard) => switch (hazard) {
  WeatherHazard.rainfall => weather.rainfallMmPerHour,
  WeatherHazard.signal => weather.signalLevel,
  WeatherHazard.surge => weather.stormSurgeMeters,
};

String _plain(num v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// The words of an automatic alert, the same as
/// `private.weather_alert_text`. They are content from the system, not UI
/// strings: residents get them as written, whatever the app's language.
({String title, String body, List<String> guidance}) weatherAlertText(
  WeatherHazard hazard,
  AlertLevel level,
  num value,
) {
  final n = _plain(value);
  final critical = level == AlertLevel.critical;
  return switch (hazard) {
    WeatherHazard.rainfall when !critical => (
      title: 'Heavy rainfall warning',
      body:
          'PAGASA reports rain of $n mm per hour over Manila. Flooding is '
          'possible in low-lying areas.',
      guidance: const [
        'Move appliances and important papers to a higher place.',
        'Avoid wading in floodwater; it can carry disease and live wires.',
        'Prepare a go-bag with water, food, medicine, and a flashlight.',
      ],
    ),
    WeatherHazard.rainfall => (
      title: 'Torrential rainfall warning',
      body:
          'PAGASA reports rain of $n mm per hour over Manila. Serious '
          'flooding is expected in low-lying areas.',
      guidance: const [
        'Move to higher ground if water is rising where you are.',
        'Do not walk or drive through floodwater.',
        'If you need rescue, hold the SOS button in the app.',
      ],
    ),
    WeatherHazard.signal when !critical => (
      title: 'Wind Signal No. $n raised over Manila',
      body:
          'PAGASA raised Tropical Cyclone Wind Signal No. $n. Strong winds '
          'are expected.',
      guidance: const [
        'Secure or bring in loose objects outside your home.',
        'Stay indoors unless MDRRMD tells you to leave.',
        'Charge your phone and prepare a go-bag.',
      ],
    ),
    WeatherHazard.signal => (
      title: 'Wind Signal No. $n raised over Manila',
      body:
          'PAGASA raised Tropical Cyclone Wind Signal No. $n. Destructive '
          'winds are expected.',
      guidance: const [
        'Stay indoors and away from windows.',
        'Follow evacuation instructions from MDRRMD and your barangay.',
        'If you need rescue, hold the SOS button in the app.',
      ],
    ),
    WeatherHazard.surge when !critical => (
      title: 'Storm surge warning for Manila Bay',
      body: 'A storm surge of up to $n m is possible along Manila Bay.',
      guidance: const [
        'Stay away from the coast and seawalls.',
        'Move vehicles and belongings to higher ground.',
      ],
    ),
    WeatherHazard.surge => (
      title: 'Storm surge warning for Manila Bay',
      body:
          'A storm surge of up to $n m is expected along Manila Bay. '
          'Coastal areas may flood quickly.',
      guidance: const [
        'Leave coastal and low-lying areas now if told to evacuate.',
        'Stay away from the coast and seawalls.',
        'If you need rescue, hold the SOS button in the app.',
      ],
    ),
  };
}
