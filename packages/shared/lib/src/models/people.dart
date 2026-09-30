import 'package:flutter/foundation.dart';

import 'enums.dart';

/// A signed-in account of any role (FR10).
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String id;
  final String displayName;
  final String email;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;

  /// Dispatchers and admins can work the Triage Queue (FR2, FR3).
  bool get canDispatch => role == UserRole.dispatcher || isAdmin;

  factory AppUser.fromJson(Map<String, Object?> json) => AppUser(
    id: '${json['id']}',
    displayName: json['display_name']! as String,
    email: json['email']! as String,
    role: enumFromJson(UserRole.values, json['role']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'email': email,
    'role': role.name,
  };
}

/// A household member registered on the Vulnerable Resident Priority List.
@immutable
class VulnerableMember {
  const VulnerableMember({
    this.id,
    required this.label,
    required this.types,
    this.notes,
  });

  /// The database row id; null for a member not saved yet (R11).
  final String? id;

  /// A name or a description such as "Lola" or "Father".
  final String label;
  final List<VulnerabilityType> types;

  /// For example "Uses a wheelchair".
  final String? notes;

  factory VulnerableMember.fromJson(Map<String, Object?> json) =>
      VulnerableMember(
        id: json['member_id'] == null ? null : '${json['member_id']}',
        label: json['label']! as String,
        types: [
          for (final t in json['vulnerability_types']! as List<Object?>)
            enumFromJson(VulnerabilityType.values, t),
        ],
        notes: json['notes'] as String?,
      );

  Map<String, Object?> toJson() => {
    'member_id': ?id,
    'label': label,
    'vulnerability_types': [for (final t in types) t.name],
    'notes': notes,
  };
}

/// An MDRRMD account as A1 and A2 list it (`staff` row). Admins only.
@immutable
class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.displayName,
    required this.email,
    required this.role,
    this.unitId,
    this.deactivatedAt,
  });

  final String id;
  final String displayName;
  final String email;
  final UserRole role;

  /// Responders only: the unit they crew.
  final String? unitId;

  /// Set by an admin (A1): cannot sign in or act.
  final DateTime? deactivatedAt;

  bool get active => deactivatedAt == null;

  AppUser get asUser =>
      AppUser(id: id, displayName: displayName, email: email, role: role);

  StaffAccount copyWith({
    String? unitId,
    bool clearUnit = false,
    String? displayName,
    UserRole? role,
    DateTime? deactivatedAt,
    bool clearDeactivated = false,
  }) => StaffAccount(
    id: id,
    displayName: displayName ?? this.displayName,
    email: email,
    role: role ?? this.role,
    unitId: clearUnit ? null : (unitId ?? this.unitId),
    deactivatedAt: clearDeactivated
        ? null
        : (deactivatedAt ?? this.deactivatedAt),
  );

  factory StaffAccount.fromJson(Map<String, Object?> json) => StaffAccount(
    id: '${json['id']}',
    displayName: json['display_name']! as String,
    email: json['email']! as String,
    role: enumFromJson(UserRole.values, json['role']),
    unitId: json['unit_id'] as String?,
    deactivatedAt: timeFromJsonOrNull(json['deactivated_at']),
  );
}

/// A registered Manila resident (MANILA_RESIDENT with VULNERABLE_PROFILE).
@immutable
class Resident {
  const Resident({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    required this.barangay,
    required this.district,
    this.household = const [],
    this.consentGivenAt,
    this.updatedAt,
    this.suspendedAt,
  });

  final String id;
  final String fullName;

  /// Verified mobile number. Masked in the UI until a dispatcher reveals it.
  final String contactNumber;
  final String barangay;
  final String district;

  /// Vulnerable household members; empty if none registered.
  final List<VulnerableMember> household;

  /// Data Privacy Act consent (NFR4). Null means no profile may be kept.
  final DateTime? consentGivenAt;
  final DateTime? updatedAt;

  /// Set by an admin (A1): no crowd reports; an SOS arrives unverified.
  final DateTime? suspendedAt;

  bool get suspended => suspendedAt != null;

  Resident copyWith({DateTime? suspendedAt, bool clearSuspended = false}) =>
      Resident(
        id: id,
        fullName: fullName,
        contactNumber: contactNumber,
        barangay: barangay,
        district: district,
        household: household,
        consentGivenAt: consentGivenAt,
        updatedAt: updatedAt,
        suspendedAt: clearSuspended ? null : (suspendedAt ?? this.suspendedAt),
      );

  bool get isVulnerable => household.isNotEmpty && consentGivenAt != null;

  List<VulnerabilityType> get vulnerabilityTypes =>
      {for (final m in household) ...m.types}.toList();

  /// "0917 ••• 4821" style masking. The database already sends numbers
  /// masked (the full number needs an audited reveal), so pass those
  /// through unchanged.
  String get maskedContact {
    if (contactNumber.contains('•')) return contactNumber;
    final digits = contactNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return '••••';
    return '${digits.substring(0, 4)} ••• ${digits.substring(digits.length - 4)}';
  }

  String get place => '$barangay, $district';

  factory Resident.fromJson(Map<String, Object?> json) => Resident(
    id: json['manila_resident_id']! as String,
    fullName: json['fullname']! as String,
    contactNumber: json['contact_number']! as String,
    barangay: json['barangay']! as String,
    district: json['district']! as String,
    household: [
      for (final m in (json['household'] as List<Object?>? ?? const []))
        VulnerableMember.fromJson(m! as Map<String, Object?>),
    ],
    consentGivenAt: timeFromJsonOrNull(json['consent_given_at']),
    updatedAt: timeFromJsonOrNull(json['updated_at']),
    suspendedAt: timeFromJsonOrNull(json['suspended_at']),
  );

  Map<String, Object?> toJson() => {
    'manila_resident_id': id,
    'fullname': fullName,
    'contact_number': contactNumber,
    'barangay': barangay,
    'district': district,
    'household': [for (final m in household) m.toJson()],
    'consent_given_at': consentGivenAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'suspended_at': suspendedAt?.toIso8601String(),
  };
}
