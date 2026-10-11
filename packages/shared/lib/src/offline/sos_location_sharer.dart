import 'dart:async';

import '../models/geo_point.dart';
import '../models/offline.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';

/// While a resident's SOS is open, tells MDRRMD where the phone is now
/// (plan Q33): a new position goes out when the phone has moved at least
/// [minMove] metres from the last one sent and [minGap] has passed. The
/// place the SOS was sent from is never changed.
///
/// Runs only while the app is open, and only for an SOS MDRRMD already has
/// and has not closed. Nothing is queued: an old position helps nobody.
class SosLocationSharer {
  SosLocationSharer(this._repo, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const minMove = 25.0;
  static const minGap = Duration(seconds: 60);

  final SosRepository _repo;
  final DateTime Function() _clock;

  String? _sosId;
  GeoPoint? _sentPoint;
  DateTime? _sentAt;

  /// Call with each new GPS fix and the resident's SOS requests.
  void onFix(LocationFix? fix, List<SosRequest> mine) {
    if (fix == null || fix.manual) return;
    SosRequest? open;
    for (final s in mine) {
      if (s.isDelivered && s.isActive) {
        open = s;
        break;
      }
    }
    if (open == null) {
      _sosId = null;
      return;
    }
    if (open.clientId != _sosId) {
      _sosId = open.clientId;
      _sentPoint = open.location;
      _sentAt = null;
    }
    final now = _clock();
    final sentAt = _sentAt;
    final sentPoint = _sentPoint;
    if (sentAt != null && now.difference(sentAt) < minGap) return;
    if (sentPoint != null && fix.point.distanceTo(sentPoint) < minMove) return;
    _sentPoint = fix.point;
    _sentAt = now;
    unawaited(_repo.updateLocation(open.clientId, fix));
  }
}
