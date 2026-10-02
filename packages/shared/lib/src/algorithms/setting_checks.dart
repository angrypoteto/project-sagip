import '../models/account.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';

final _hotline = RegExp(r'^[0-9+() -]*[0-9][0-9+() -]*$');

/// A setting value as the database stores it: text trimmed, and the SMS
/// gateway number as "+639XXXXXXXXX".
Object normalizeSetting(String key, Object value) {
  if (value is! String) return value;
  final text = value.trim();
  if (key == SettingKeys.smsGateway && text.isNotEmpty) {
    return normalizePhMobile(text) ?? text;
  }
  return text;
}

/// Why a setting value is refused (the same checks as `set_setting`), or
/// null when it is fine. [current] holds every setting by key.
///
/// A setting keeps its type; a number stays in its range and each warning
/// stays at or below its critical value ([SettingKeys.pairs]); the SMS
/// gateway is a Philippine mobile number or empty; the hotline is digits
/// with the usual punctuation, or empty.
ActionRejection? checkSetting(
  Map<String, AppSetting> current,
  String key,
  Object value,
) {
  final s = current[key];
  if (s == null) return ActionRejection.notFound;
  final sameType =
      (value is num && s.value is num) ||
      (value is bool && s.value is bool) ||
      (value is String && s.value is String);
  if (!sameType) return ActionRejection.invalidValue;

  if (value is num) {
    if ((s.min != null && value < s.min!) ||
        (s.max != null && value > s.max!)) {
      return ActionRejection.invalidValue;
    }
    for (final (low, high) in SettingKeys.pairs) {
      final lowValue = current[low]?.value;
      final highValue = current[high]?.value;
      if ((key == low && highValue is num && value > highValue) ||
          (key == high && lowValue is num && value < lowValue)) {
        return ActionRejection.invalidValue;
      }
    }
  } else if (value is String) {
    final text = value.trim();
    if (key == SettingKeys.smsGateway) {
      if (text.isNotEmpty && normalizePhMobile(text) == null) {
        return ActionRejection.invalidValue;
      }
    } else if (key == SettingKeys.hotline) {
      if (text.length > 40 || (text.isNotEmpty && !_hotline.hasMatch(text))) {
        return ActionRejection.invalidValue;
      }
    } else if (text.length > 200) {
      return ActionRejection.invalidValue;
    }
  }
  return null;
}
