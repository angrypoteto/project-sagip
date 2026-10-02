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
  final String category;

  /// A number for every setting so far.
  final num value;
  final num? min;
  final num? max;
  final String description;
  final DateTime? updatedAt;
  final String? updatedBy;

  AppSetting copyWith({num? value, DateTime? updatedAt, String? updatedBy}) =>
      AppSetting(
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
    value: json['value']! as num,
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

/// The hourly crowd report limit per resident account (FR15, NFR7), across
/// the app and the web form.
const reportsPerHourKey = 'reports.per_hour';

/// The report settings as the `web_form` migration seeds them, with the
/// same range (the mock backend starts from these).
const defaultReportSettings = [
  AppSetting(
    key: reportsPerHourKey,
    category: 'reports',
    value: 5,
    min: 1,
    max: 30,
    description: 'Crowd reports one account may send in an hour (app and web form together)',
  ),
];
