part of 'supabase_repositories.dart';

// Supabase side of the resident web form (W1 to W3). Sign-in is the same as
// the app's: a mobile number and a code by SMS ([SupabaseMobileAccounts]).
// Reports go through the same checked function as the app's, marked as
// coming from the web form.

/// Everything the web form needs from one [SupabaseClient].
class SupabaseWebFormBackend {
  SupabaseWebFormBackend(SupabaseClient client)
    : accounts = SupabaseMobileAccounts(client),
      reports = SupabaseWebReportRepository(client),
      config = SupabaseClientConfigRepository(client);

  final SupabaseMobileAccounts accounts;
  final SupabaseWebReportRepository reports;

  /// The hotline set on A3, shown before sign-in.
  final SupabaseClientConfigRepository config;
}

class SupabaseWebReportRepository implements WebReportRepository {
  SupabaseWebReportRepository(this._client);

  final SupabaseClient _client;

  /// Refetches right after a report is sent, without waiting for Realtime.
  final _changed = StreamController<Object?>.broadcast();

  /// Refreshes every minute too: a report turns Not confirmed, and a used
  /// slot frees up, an hour after the report was made.
  @override
  Stream<List<HazardReport>> watchMine() => liveQuery(
    _client,
    tables: const ['crowd_report'],
    refreshEvery: const Duration(minutes: 1),
    refreshOn: _changed.stream,
    fetch: () async => [
      for (final r
          in (await _client.rpc<Object?>('my_crowd_reports')
                  as List<Object?>? ??
              const []))
        HazardReport.fromJson((r! as Map).cast<String, Object?>()),
    ],
  );

  @override
  Stream<ReportQuota> watchQuota() => liveQuery(
    _client,
    tables: const ['crowd_report'],
    refreshEvery: const Duration(minutes: 1),
    refreshOn: _changed.stream,
    fetch: () async => ReportQuota.fromJson(
      await _client.rpc<Map<String, dynamic>>('my_report_quota'),
    ),
  );

  @override
  Future<HazardReport> submit({
    required String clientId,
    required DateTime capturedAt,
    required String description,
    required GeoPoint location,
    IncidentType? type,
    double? accuracyMeters,
    Barangay? barangay,
  }) async {
    final id = await _call(
      () => _client.rpc<String>(
        'submit_crowd_report',
        params: {
          'p_client_uuid': clientId,
          'p_captured_at': capturedAt.toUtc().toIso8601String(),
          'p_description': description,
          'p_type': type?.name,
          'p_latitude': location.lat,
          'p_longitude': location.lng,
          'p_accuracy_m': accuracyMeters,
          'p_barangay': barangay?.name,
          'p_district': barangay?.district,
          'p_source': ReportChannel.webForm.name,
        },
      ),
    );
    _changed.add(null);
    return HazardReport(
      clientId: clientId,
      capturedAt: capturedAt,
      description: description.trim(),
      type: type,
      location: location,
      accuracyMeters: accuracyMeters,
      barangay: barangay?.name,
      district: barangay?.district,
      delivery: DeliveryState.delivered,
      deliveredAt: DateTime.now(),
      serverId: id,
      stage: ReportStage.checking,
      source: ReportChannel.webForm,
    );
  }
}
