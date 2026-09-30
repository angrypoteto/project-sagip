import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/offline.dart';

/// What a record in the outbox asks the server to do.
enum OutboxAction {
  sos,
  sosDetails,
  crowdReport,
  accept,
  arrive,
  confirmOnScene,
  setStatus,
  completion;

  /// How the offline queue sheet (S6) groups it.
  QueuedKind get kind => switch (this) {
    OutboxAction.sos => QueuedKind.sos,
    OutboxAction.sosDetails => QueuedKind.sosDetails,
    OutboxAction.crowdReport => QueuedKind.crowdReport,
    OutboxAction.completion => QueuedKind.completionReport,
    _ => QueuedKind.statusUpdate,
  };
}

/// A record made on the phone, saved before anything is sent (NFR1, FR13).
/// It keeps the time it was made and the account that made it; the server
/// stores it once however many times it is sent.
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.action,
    required this.accountId,
    required this.capturedAt,
    required this.payload,
    this.delivery = DeliveryState.savedOnPhone,
    this.attempts = 0,
    this.waited = false,
    this.serverId,
    this.deliveredAt,
    this.rejectReason,
    this.sequence = 0,
    this.smsSentAt,
  });

  /// The record's client id: the SOS, report, or completion report id, or
  /// a fresh id for a status change.
  final String id;
  final OutboxAction action;

  /// Only sent while this account is signed in; another account's records
  /// wait on the phone (the server would refuse them).
  final String accountId;
  final DateTime capturedAt;

  /// The record in its model's JSON shape.
  final Map<String, Object?> payload;
  final DeliveryState delivery;
  final int attempts;

  /// It could not go out right away. Only these get the "was delivered"
  /// notice.
  final bool waited;

  /// For example the incident id of an SOS or the report id.
  final String? serverId;
  final DateTime? deliveredAt;

  /// The server's refusal code (for example `outsideManila`).
  final String? rejectReason;

  /// Order of saving on this phone; breaks ties between records made in
  /// the same instant, so they are sent in the order they were made.
  final int sequence;

  /// Tier 2: when the SOS went out as an SMS to the gateway. It still goes
  /// over the internet later (the server recognises it), so it stays
  /// pending until then.
  final DateTime? smsSentAt;

  QueuedKind get kind => action.kind;

  OutboxEntry copyWith({
    Map<String, Object?>? payload,
    DeliveryState? delivery,
    int? attempts,
    bool? waited,
    String? serverId,
    DateTime? deliveredAt,
    String? rejectReason,
    int? sequence,
    DateTime? smsSentAt,
  }) => OutboxEntry(
    id: id,
    action: action,
    accountId: accountId,
    capturedAt: capturedAt,
    payload: payload ?? this.payload,
    delivery: delivery ?? this.delivery,
    attempts: attempts ?? this.attempts,
    waited: waited ?? this.waited,
    serverId: serverId ?? this.serverId,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    rejectReason: rejectReason ?? this.rejectReason,
    sequence: sequence ?? this.sequence,
    smsSentAt: smsSentAt ?? this.smsSentAt,
  );

  QueuedRecord toQueued() => QueuedRecord(
    id: id,
    kind: kind,
    capturedAt: capturedAt,
    delivery: delivery,
    rejectReason: rejectReason,
    waitedOffline: waited,
  );

  factory OutboxEntry.fromJson(Map<String, Object?> json) => OutboxEntry(
    id: json['id']! as String,
    action: enumFromJson(OutboxAction.values, json['action']),
    accountId: json['account_id']! as String,
    capturedAt: timeFromJson(json['captured_at']),
    payload: (json['payload']! as Map).cast<String, Object?>(),
    delivery: enumFromJson(DeliveryState.values, json['delivery']),
    attempts: json['attempts'] as int? ?? 0,
    waited: json['waited'] as bool? ?? false,
    serverId: json['server_id'] as String?,
    deliveredAt: timeFromJsonOrNull(json['delivered_at']),
    rejectReason: json['reject_reason'] as String?,
    sequence: json['sequence'] as int? ?? 0,
    smsSentAt: timeFromJsonOrNull(json['sms_sent_at']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action.name,
    'account_id': accountId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'payload': payload,
    'delivery': delivery.name,
    'attempts': attempts,
    'waited': waited,
    'server_id': serverId,
    'delivered_at': deliveredAt?.toUtc().toIso8601String(),
    'reject_reason': rejectReason,
    'sequence': sequence,
    'sms_sent_at': smsSentAt?.toUtc().toIso8601String(),
  };
}

/// Storage on the phone: the outbox, the last copy of server data for
/// offline reading, and small settings. The app uses Hive (encrypted);
/// tests use [MemoryLocalStore]. Reads are synchronous because the store
/// is opened before the app starts.
abstract interface class LocalStore {
  List<OutboxEntry> get outbox;
  Future<void> putEntry(OutboxEntry entry);
  Future<void> deleteEntry(String id);

  /// A JSON value saved under [key], or null.
  Object? read(String key);
  Future<void> write(String key, Object? value);
}

/// An in-memory [LocalStore] for tests and previews.
class MemoryLocalStore implements LocalStore {
  final _entries = <String, OutboxEntry>{};
  final _values = <String, Object?>{};

  @override
  List<OutboxEntry> get outbox => _entries.values.toList();

  @override
  Future<void> putEntry(OutboxEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<void> deleteEntry(String id) async => _entries.remove(id);

  @override
  Object? read(String key) => _values[key];

  @override
  Future<void> write(String key, Object? value) async => _values[key] = value;
}
