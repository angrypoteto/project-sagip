import 'dart:typed_data';

import '../algorithms/hazard_penalty.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
import '../models/photo.dart';
import '../models/response_unit.dart';
import '../models/sos.dart';

/// The server as the phone's outbox and caches see it. The Supabase
/// version is `SupabaseMobileRemote`; tests use a fake.
///
/// Sends take the record's client id and capture time, so sending the same
/// record twice after a lost reply stores it once. Refusals throw
/// `ReportRejected`, `StatusRejected`, or `ActionRejected`; a network
/// failure throws `ActionRejected(ActionRejection.offline)`.
abstract interface class MobileServer {
  // Resident.
  Future<String> submitSos(SosRequest sos);
  Future<void> addSosDetails(String clientId, SosDetails details);
  Future<void> requestSosCancel(
    String clientId,
    SosCancelReason reason,
    String? note,
  );
  Future<void> withdrawSosCancel(String clientId);
  Future<void> updateSosLocation(
    String clientId,
    GeoPoint point,
    double? accuracyMeters,
    DateTime capturedAt,
  );
  Stream<List<SosRequest>> watchMySos();
  Future<String> submitReport(HazardReport report);
  Stream<List<HazardReport>> watchMyReports();

  /// Uploads a photo (a prepared JPEG) and ties it to this resident's SOS
  /// or report [clientId] (2026-10-19). Sending it again changes nothing.
  Future<void> uploadPhoto({
    required String photoId,
    required PhotoKind kind,
    required String clientId,
    required Uint8List jpeg,
  });

  // Responder.
  Stream<ResponseUnit?> watchUnit();
  Stream<List<HazardZone>> watchRoadHazards();
  Stream<List<Assignment>> watchAssignments();
  Future<void> accept(String incidentId, DateTime capturedAt);
  Future<void> arrive(String incidentId, DateTime capturedAt);
  Future<void> confirmOnScene(
    String incidentId, {
    required bool realEmergency,
    required DateTime capturedAt,
    String? reason,
    int? peopleFound,
  });
  Future<void> setStatus(UnitStatus status, DateTime capturedAt);
  Future<void> submitCompletion(CompletionReport report);
  Future<void> updateLocation(GeoPoint point, DateTime capturedAt);
  Stream<List<CompletedAssignment>> watchHistory();
}
