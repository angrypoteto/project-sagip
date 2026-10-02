import 'package:flutter/foundation.dart';

import 'enums.dart';

/// A value an administrator can change on A3 Configuration (`app_setting`).
/// Every change is audited (FR11).
@immutable
class AppSetting {
  const AppSetting({
    required this.key,
    required this.category,
    required this.value,
    required this.description,
    this.min,
    this.max,
    this.updatedAt,
    this.updatedBy,
  });

  /// For example `priority.sos`.
  final String key;

  /// The group the setting belongs to: `priority`, `reports`, `alerts`,
  /// `channels`, `contact`, or `demo`.
  final String category;

  /// A number (weights, limits, thresholds), a switch (`bool`), or text
  /// (the hotline and the SMS gateway number). A setting never changes
  /// its type.
  final Object value;

  /// The range of a number setting.
  final num? min;
  final num? max;
  final String description;
  final DateTime? updatedAt;
  final String? updatedBy;

  /// The value of a number setting.
  num get number => value as num;

  /// The value of a switch.
  bool get flag => value as bool;

  /// The value of a text setting.
  String get text => value as String;

  AppSetting copyWith({
    Object? value,
    DateTime? updatedAt,
    String? updatedBy,
  }) => AppSetting(
    key: key,
    category: category,
    value: value ?? this.value,
    description: description,
    min: min,
    max: max,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  factory AppSetting.fromJson(Map<String, Object?> json) => AppSetting(
    key: json['key']! as String,
    category: json['category']! as String,
    value: json['value']!,
    description: json['description']! as String,
    min: json['min_value'] as num?,
    max: json['max_value'] as num?,
    updatedAt: timeFromJsonOrNull(json['updated_at']),
    updatedBy: json['updated_by'] as String?,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'category': category,
    'value': value,
    'description': description,
    'min_value': min,
    'max_value': max,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'updated_by': updatedBy,
  };
}

/// The `app_setting` keys outside the priority weights (those are listed in
/// `PriorityRules.settingKeys`).
abstract final class SettingKeys {
  /// Crowd reports per resident account per hour (FR15, NFR7), across the
  /// app and the web form.
  static const reportsPerHour = 'reports.per_hour';

  // Readings at or above these raise an alert by themselves (FR5).
  static const rainfallWarning = 'alerts.rainfall_warning';
  static const rainfallCritical = 'alerts.rainfall_critical';
  static const signalWarning = 'alerts.signal_warning';
  static const signalCritical = 'alerts.signal_critical';
  static const surgeWarning = 'alerts.surge_warning';
  static const surgeCritical = 'alerts.surge_critical';

  /// In the order A3 shows them.
  static const alerts = [
    rainfallWarning,
    rainfallCritical,
    signalWarning,
    signalCritical,
    surgeWarning,
    surgeCritical,
  ];

  // Which channels an alert goes out on (FR6). The apps always show it.
  static const pushChannel = 'channels.push';
  static const smsChannel = 'channels.sms';
  static const facebookChannel = 'channels.facebook';
  static const channels = [pushChannel, smsChannel, facebookChannel];

  /// The most alert texts sent in one day (each costs Semaphore credit).
  static const smsDailyCap = 'channels.sms_daily_cap';

  /// The MDRRMD hotline the apps show.
  static const hotline = 'contact.hotline';

  /// The gateway SIM that receives an SOS by SMS (Tier 2).
  static const smsGateway = 'contact.sms_gateway';

  /// Simulation mode for demos and UAT (plan section 12).
  static const simulation = 'demo.simulation';

  /// Pairs where the first value must stay at or below the second.
  static const pairs = [
    ('priority.high_at', 'priority.critical_at'),
    (rainfallWarning, rainfallCritical),
    (signalWarning, signalCritical),
    (surgeWarning, surgeCritical),
  ];
}

/// The settings beyond the priority weights, as the `web_form` and
/// `alert_engine` migrations seed them, with the same ranges (the mock
/// backend starts from these).
const defaultOtherSettings = [
  AppSetting(
    key: SettingKeys.reportsPerHour,
    category: 'reports',
    value: 5,
    min: 1,
    max: 30,
    description: 'Crowd reports one account may send in an hour (app and web form together)',
  ),
  AppSetting(
    key: SettingKeys.rainfallWarning,
    category: 'alerts',
    value: 15,
    min: 1,
    max: 200,
    description: 'Rainfall in mm per hour that raises a warning alert',
  ),
  AppSetting(
    key: SettingKeys.rainfallCritical,
    category: 'alerts',
    value: 30,
    min: 1,
    max: 200,
    description: 'Rainfall in mm per hour that raises a critical alert',
  ),
  AppSetting(
    key: SettingKeys.signalWarning,
    category: 'alerts',
    value: 1,
    min: 1,
    max: 5,
    description: 'Wind signal that raises a warning alert',
  ),
  AppSetting(
    key: SettingKeys.signalCritical,
    category: 'alerts',
    value: 3,
    min: 1,
    max: 5,
    description: 'Wind signal that raises a critical alert',
  ),
  AppSetting(
    key: SettingKeys.surgeWarning,
    category: 'alerts',
    value: 1.1,
    min: 0.1,
    max: 10,
    description: 'Storm surge height in metres that raises a warning alert',
  ),
  AppSetting(
    key: SettingKeys.surgeCritical,
    category: 'alerts',
    value: 2.1,
    min: 0.1,
    max: 10,
    description: 'Storm surge height in metres that raises a critical alert',
  ),
  AppSetting(
    key: SettingKeys.pushChannel,
    category: 'channels',
    value: true,
    description: 'Send alerts as push notifications',
  ),
  AppSetting(
    key: SettingKeys.smsChannel,
    category: 'channels',
    value: true,
    description: 'Send alerts by SMS (Semaphore)',
  ),
  AppSetting(
    key: SettingKeys.facebookChannel,
    category: 'channels',
    value: false,
    description: 'Post alerts on the MDRRMD Facebook Page',
  ),
  AppSetting(
    key: SettingKeys.smsDailyCap,
    category: 'channels',
    value: 500,
    min: 0,
    max: 100000,
    description: 'Most alert texts sent in one day (Manila time)',
  ),
  AppSetting(
    key: SettingKeys.hotline,
    category: 'contact',
    value: '',
    description: 'The MDRRMD hotline the apps show',
  ),
  AppSetting(
    key: SettingKeys.smsGateway,
    category: 'contact',
    value: '',
    description: 'The gateway SIM that receives an SOS by SMS',
  ),
  AppSetting(
    key: SettingKeys.simulation,
    category: 'demo',
    value: false,
    description: 'Simulation mode for demos and UAT',
  ),
];

/// What the apps may read before anyone signs in (`client_config()`): the
/// hotline and the SMS gateway number, both set on A3. Empty means not set.
@immutable
class ClientConfig {
  const ClientConfig({this.hotline = '', this.smsGateway = ''});

  final String hotline;

  /// For example "+639171234567".
  final String smsGateway;

  factory ClientConfig.fromJson(Map<String, Object?> json) => ClientConfig(
    hotline: json['hotline'] as String? ?? '',
    smsGateway: json['sms_gateway'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'hotline': hotline,
    'sms_gateway': smsGateway,
  };
}
