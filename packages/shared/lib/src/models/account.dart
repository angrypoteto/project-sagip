import 'package:flutter/foundation.dart';

/// A barangay and its district, for pickers (S4, R5).
@immutable
class Barangay {
  const Barangay(this.name, this.district);

  /// For example "Barangay 412".
  final String name;

  /// For example "Sampaloc".
  final String district;

  @override
  bool operator ==(Object other) =>
      other is Barangay && other.name == name && other.district == district;

  @override
  int get hashCode => Object.hash(name, district);
}

/// Permissions the app explains and asks for on S2 (plan 7.4).
enum AppPermission {
  /// SOS location and responder tracking.
  location,

  /// Alerts and delivery notices.
  notifications,

  /// Tier 2: sending an SOS by SMS.
  sms,

  /// Tier 3: relaying an SOS through nearby phones (Bluetooth).
  nearbyDevices,
}

enum PermissionState {
  notAsked,
  granted,
  denied,

  /// The phone will not ask again; only Settings can change it.
  permanentlyDenied,
}

/// Why a phone-number sign-in or registration step failed (S3 to S5).
enum PhoneAuthFailure {
  invalidNumber,
  notRegistered,
  numberTaken,
  wrongCode,
  tooManyAttempts,
  offline,
}

class PhoneAuthException implements Exception {
  const PhoneAuthException(this.reason);

  final PhoneAuthFailure reason;

  @override
  String toString() => 'PhoneAuthException($reason)';
}

/// Turns what a resident types ("0917 123 4567", "9171234567",
/// "+63 917 123 4567") into "+639171234567", or null if it is not a
/// Philippine mobile number.
String? normalizePhMobile(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('63')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length != 10 || !digits.startsWith('9')) return null;
  return '+63$digits';
}
