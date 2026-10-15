import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'incident.dart';

/// An incident's post on the MDRRMD Facebook Page, as the database keeps it
/// (`incident_post`, migrations incident_posts and incident_post_updates).
@immutable
class IncidentPost {
  const IncidentPost({
    required this.stage,
    required this.status,
    this.detail,
    this.updatedAt,
  });

  /// `unverified`, `confirmed`, `falseAlarm`, or `withdrawn`.
  final String stage;

  /// `queued`, `sending`, `sent`, `failed`, `off`, `simulated`,
  /// `notSetUp`, or `withdrawn`.
  final String status;
  final String? detail;
  final DateTime? updatedAt;

  factory IncidentPost.fromJson(Map<String, dynamic> json) => IncidentPost(
    stage: json['stage'] as String? ?? 'confirmed',
    status: json['status'] as String? ?? 'queued',
    detail: json['detail'] as String?,
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')
        ?.toLocal(),
  );

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'status': status,
    'detail': detail,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

/// What the dispatcher is told about an incident and the Facebook Page.
enum FacebookPostState {
  /// The A3 switch is off.
  switchedOff,

  /// No type yet, so the system cannot tell a flood from a medical case.
  needsType,

  /// Medical, or anything else that is never posted.
  neverPosted,

  /// Unverified with no unit yet: it is posted once a unit is sent.
  waitingForUnit,

  /// Queued or being sent to the Page.
  posting,
  postedUnverified,
  postedConfirmed,
  postedFalseAlarm,
  postedWithdrawn,

  /// Withdrawn or false before it was ever posted.
  notNeeded,
  failed,
  pageNotSetUp,
  simulated,

  /// The switch was off when the incident would have been posted.
  heldBack,
}

/// The Facebook line for [incident], from its [post] if it has one and the
/// A3 switch ([switchOn]).
FacebookPostState facebookPostState(
  Incident incident,
  IncidentPost? post, {
  required bool switchOn,
}) {
  if (post != null) {
    return switch (post.status) {
      'simulated' => FacebookPostState.simulated,
      'off' => FacebookPostState.heldBack,
      'withdrawn' => FacebookPostState.notNeeded,
      'notSetUp' => FacebookPostState.pageNotSetUp,
      'failed' => FacebookPostState.failed,
      'sent' => switch (post.stage) {
        'unverified' => FacebookPostState.postedUnverified,
        'falseAlarm' => FacebookPostState.postedFalseAlarm,
        'withdrawn' => FacebookPostState.postedWithdrawn,
        _ => FacebookPostState.postedConfirmed,
      },
      _ => FacebookPostState.posting,
    };
  }
  if (incident.isSimulated) return FacebookPostState.simulated;
  if (!switchOn) return FacebookPostState.switchedOff;
  final type = incident.type;
  if (type == null) return FacebookPostState.needsType;
  if (type == IncidentType.medical) return FacebookPostState.neverPosted;
  if (!incident.isVerified && incident.assignedUnitId == null) {
    return FacebookPostState.waitingForUnit;
  }
  return FacebookPostState.posting;
}
