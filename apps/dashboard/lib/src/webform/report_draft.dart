import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sagip_shared/sagip_shared.dart';

import 'web_providers.dart';

/// How the resident set the report's location on W2.
enum DraftPlace {
  /// The browser's geolocation.
  browser,

  /// The map moved under the pin.
  pin,

  /// The centre of a barangay chosen from the list.
  barangay,
}

/// The report being written on W2. Kept in the browser (plan 7.2: "draft
/// kept in the browser") so a reload or a lost connection does not lose it.
@immutable
class ReportDraft {
  const ReportDraft({
    required this.clientId,
    this.description = '',
    this.type,
    this.location,
    this.accuracyMeters,
    this.place,
    this.barangay,
    this.capturedAt,
  });

  /// The report's id ([newClientId]). It stays the same when the draft is
  /// sent again after a lost connection, so the server stores it once.
  final String clientId;
  final String description;
  final IncidentType? type;

  /// Null until the resident chooses a location.
  final GeoPoint? location;

  /// Only for [DraftPlace.browser].
  final double? accuracyMeters;
  final DraftPlace? place;

  /// The chosen barangay, or the nearest one to the location.
  final Barangay? barangay;

  /// When Send was first pressed. A retry keeps it (NFR1).
  final DateTime? capturedAt;

  bool get isBlank => description.trim().isEmpty && location == null;

  ReportDraft copyWith({
    String? description,
    IncidentType? type,
    bool clearType = false,
    DateTime? capturedAt,
    bool clearCapturedAt = false,
  }) => ReportDraft(
    clientId: clientId,
    description: description ?? this.description,
    type: clearType ? null : (type ?? this.type),
    location: location,
    accuracyMeters: accuracyMeters,
    place: place,
    barangay: barangay,
    capturedAt: clearCapturedAt ? null : (capturedAt ?? this.capturedAt),
  );

  ReportDraft at(
    GeoPoint point,
    DraftPlace place, {
    double? accuracyMeters,
    Barangay? barangay,
  }) => ReportDraft(
    clientId: clientId,
    description: description,
    type: type,
    location: point,
    accuracyMeters: accuracyMeters,
    place: place,
    barangay: barangay ?? nearestBarangay(point),
    capturedAt: capturedAt,
  );

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'description': description,
    'type': type?.name,
    'latitude': location?.lat,
    'longitude': location?.lng,
    'accuracy_m': accuracyMeters,
    'place': place?.name,
    'barangay': barangay?.name,
    'district': barangay?.district,
    'captured_at': capturedAt?.toUtc().toIso8601String(),
  };

  /// Null for text that is not a draft (an old format, or tampered with).
  static ReportDraft? tryParse(String? text) {
    if (text == null) return null;
    try {
      final json = (jsonDecode(text) as Map).cast<String, Object?>();
      final lat = (json['latitude'] as num?)?.toDouble();
      final lng = (json['longitude'] as num?)?.toDouble();
      final barangay = json['barangay'] as String?;
      final district = json['district'] as String?;
      final point = lat == null || lng == null ? null : GeoPoint(lat, lng);
      return ReportDraft(
        clientId: json['client_id']! as String,
        description: json['description'] as String? ?? '',
        type: enumFromJsonOrNull(IncidentType.values, json['type']),
        location: point,
        accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
        place: point == null
            ? null
            : enumFromJsonOrNull(DraftPlace.values, json['place']),
        barangay: barangay == null || district == null
            ? null
            : Barangay(barangay, district),
        capturedAt: timeFromJsonOrNull(json['captured_at']),
      );
    } on Object {
      return null;
    }
  }
}

/// The draft for the signed-in account. Each change is written to the
/// browser's store; map moves are written once the map settles.
class ReportDraftController extends Notifier<ReportDraft> {
  Timer? _saving;

  String get _key => 'sagip.webform.draft.${ref.read(webUserIdProvider)}';

  @override
  ReportDraft build() {
    // A different account starts from its own draft.
    ref.watch(webUserIdProvider);
    ref.onDispose(() => _saving?.cancel());
    return ReportDraft.tryParse(ref.read(draftStoreProvider).read(_key)) ??
        ReportDraft(clientId: newClientId());
  }

  void _save() {
    _saving?.cancel();
    _saving = null;
    ref
        .read(draftStoreProvider)
        .write(_key, state.isBlank ? null : jsonEncode(state.toJson()));
  }

  void setDescription(String text) {
    state = state.copyWith(description: text);
    _save();
  }

  void setType(IncidentType? type) {
    state = state.copyWith(type: type, clearType: type == null);
    _save();
  }

  void setLocation(
    GeoPoint point,
    DraftPlace place, {
    double? accuracyMeters,
    Barangay? barangay,
  }) {
    state = state.at(
      point,
      place,
      accuracyMeters: accuracyMeters,
      barangay: barangay,
    );
    if (place == DraftPlace.pin) {
      // The map reports every frame of a drag.
      _saving ??= Timer(const Duration(milliseconds: 400), _save);
    } else {
      _save();
    }
  }

  /// Keeps the time Send was first pressed.
  DateTime markSending(DateTime now) {
    final at = state.capturedAt ?? now;
    state = state.copyWith(capturedAt: at);
    _save();
    return at;
  }

  /// The server refused the report (not a lost connection): the next try
  /// is a new attempt with a new time.
  void forgetSending() {
    state = state.copyWith(clearCapturedAt: true);
    _save();
  }

  /// After a report is sent, or on sign-out: nothing stays in the browser.
  void clear() {
    state = ReportDraft(clientId: newClientId());
    _save();
  }
}

final reportDraftProvider =
    NotifierProvider<ReportDraftController, ReportDraft>(
      ReportDraftController.new,
    );
