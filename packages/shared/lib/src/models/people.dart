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
    this.personnelId,
  });

  final String id;
  final String displayName;
  final String email;
  final UserRole role;

  /// Responders only: the unit they crew.
  final String? unitId;

  /// MDRRMD's own personnel number (employee or badge), set by an admin on
  /// A1; shown in crew lists. Null until set.
  final String? personnelId;

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
    String? personnelId,
    bool clearPersonnelId = false,
  }) => StaffAccount(
    id: id,
    displayName: displayName ?? this.displayName,
    email: email,
    role: role ?? this.role,
    unitId: clearUnit ? null : (unitId ?? this.unitId),
    deactivatedAt: clearDeactivated
        ? null
        : (deactivatedAt ?? this.deactivatedAt),
    personnelId: clearPersonnelId ? null : (personnelId ?? this.personnelId),
  );

  factory StaffAccount.fromJson(Map<String, Object?> json) => StaffAccount(
    id: '${json['id']}',
    displayName: json['display_name']! as String,
    email: json['email']! as String,
    role: enumFromJson(UserRole.values, json['role']),
    unitId: json['unit_id'] as String?,
    deactivatedAt: timeFromJsonOrNull(json['deactivated_at']),
    personnelId: json['personnel_id'] as String?,
  );
}

/// One member of a unit's crew, as dispatchers (D7 Units) and the unit's
/// own responders (My unit) see them: name and personnel ID only, never an
/// email (`unit_crew()`).
@immutable
class CrewMember {
  const CrewMember({
    required this.unitId,
    required this.staffId,
    required this.displayName,
    this.personnelId,
  });

  final String unitId;
  final String staffId;
  final String displayName;

  /// Null until an admin sets it on A1.
  final String? personnelId;

  factory CrewMember.fromJson(Map<String, Object?> json) => CrewMember(
    unitId: json['unit_id']! as String,
    staffId: '${json['staff_id']}',
    displayName: json['display_name']! as String,
    personnelId: json['personnel_id'] as String?,
  );
}

/// What a crew head or assistant head asks for (`crew_request.kind`).
enum CrewRequestKind {
  /// An existing responder account onto the unit.
  add,

  /// A member off the unit (never the one asking).
  remove,

  /// A person with no account yet: the admin creates it on approving.
  newMember,
}

enum CrewRequestStatus { pending, approved, declined }

/// A request to change a unit's crew, and the admin's answer (2026-10-29).
/// Seen by admins and by that unit's head and assistant head.
@immutable
class CrewRequest {
  const CrewRequest({
    required this.id,
    required this.unitId,
    required this.kind,
    this.staffId,
    required this.subjectName,
    this.newEmail,
    this.newPersonnelId,
    this.note,
    required this.status,
    required this.requestedByName,
    required this.requestedAt,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
  });

  final String id;
  final String unitId;
  final CrewRequestKind kind;

  /// The responder ([CrewRequestKind.add], [CrewRequestKind.remove]), or
  /// the account made when a new member was approved.
  final String? staffId;

  /// Their name when the request was made.
  final String subjectName;

  /// [CrewRequestKind.newMember] only.
  final String? newEmail;
  final String? newPersonnelId;

  /// Why, from the one asking (optional).
  final String? note;
  final CrewRequestStatus status;
  final String requestedByName;
  final DateTime requestedAt;
  final String? decidedByName;
  final DateTime? decidedAt;

  /// The admin's reason (always given when declining).
  final String? decisionNote;

  bool get pending => status == CrewRequestStatus.pending;

  static CrewRequestKind _kind(Object? v) => switch (v) {
    'add' => CrewRequestKind.add,
    'remove' => CrewRequestKind.remove,
    _ => CrewRequestKind.newMember,
  };

  factory CrewRequest.fromJson(Map<String, Object?> json) => CrewRequest(
    id: '${json['request_id']}',
    unitId: json['unit_id']! as String,
    kind: _kind(json['kind']),
    staffId: json['staff_id'] as String?,
    subjectName: json['subject_name']! as String,
    newEmail: json['new_email'] as String?,
    newPersonnelId: json['new_personnel_id'] as String?,
    note: json['note'] as String?,
    status: enumFromJson(CrewRequestStatus.values, json['status']),
    requestedByName: json['requested_by_name']! as String,
    requestedAt: timeFromJson(json['requested_at']),
    decidedByName: json['decided_by_name'] as String?,
    decidedAt: timeFromJsonOrNull(json['decided_at']),
    decisionNote: json['decision_note'] as String?,
  );

  CrewRequest decided({
    required bool approve,
    required String byName,
    required DateTime at,
    String? note,
    String? staffId,
  }) => CrewRequest(
    id: id,
    unitId: unitId,
    kind: kind,
    staffId: staffId ?? this.staffId,
    subjectName: subjectName,
    newEmail: newEmail,
    newPersonnelId: newPersonnelId,
    note: this.note,
    status: approve ? CrewRequestStatus.approved : CrewRequestStatus.declined,
    requestedByName: requestedByName,
    requestedAt: requestedAt,
    decidedByName: byName,
    decidedAt: at,
    decisionNote: note,
  );
}

/// Someone a crew head can ask to add: an active responder not on their
/// unit (`crew_candidates()`): name, personnel ID, and unit only.
@immutable
class CrewCandidate {
  const CrewCandidate({
    required this.staffId,
    required this.displayName,
    this.personnelId,
    this.unitId,
    this.callSign,
  });

  final String staffId;
  final String displayName;
  final String? personnelId;
  final String? unitId;

  /// Their unit's call sign; null when on none.
  final String? callSign;

  factory CrewCandidate.fromJson(Map<String, Object?> json) => CrewCandidate(
    staffId: '${json['staff_id']}',
    displayName: json['display_name']! as String,
    personnelId: json['personnel_id'] as String?,
    unitId: json['unit_id'] as String?,
    callSign: json['call_sign'] as String?,
  );
}

/// [raw] as a personnel ID is stored: trimmed and in capitals; null when
/// blank. [isValidPersonnelId] checks the result (as the database does).
String? normalizePersonnelId(String? raw) {
  final v = (raw ?? '').trim().toUpperCase();
  return v.isEmpty ? null : v;
}

/// Letters, digits, and dashes, up to 20, starting with a letter or digit.
bool isValidPersonnelId(String v) =>
    RegExp(r'^[A-Z0-9][A-Z0-9-]{0,19}$').hasMatch(v);

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
