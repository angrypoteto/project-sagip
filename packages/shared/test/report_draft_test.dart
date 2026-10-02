import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

void main() {
  final now = DateTime(2026, 10, 1, 15, 42);
  final seed = MockSeed(now);

  ReportSource source(DateTime from, DateTime to) => buildReportSource(
    incidents: [...seed.incidents, ...seed.pastIncidents],
    completions: seed.pastCompletions,
    alerts: [for (final a in seed.sentAlerts) a.alert],
    readings: [seed.weather],
    from: from,
    to: to,
  );

  group('the figures for a period', () {
    final fortnight = source(now.subtract(const Duration(days: 14)), now);

    test('cover every incident received in it and add up', () {
      expect(fortnight.incidents, seed.incidents.length + 4);
      expect(
        fortnight.resolved + fortnight.open + fortnight.falseReports,
        fortnight.incidents,
      );
      expect(fortnight.sos + fortnight.clusters, fortnight.incidents);
      expect(
        fortnight.byType.values.fold(0, (a, b) => a + b),
        fortnight.incidents,
      );
      expect(
        fortnight.byBarangay.fold(0, (a, b) => a + b.count),
        fortnight.incidents,
      );
      expect(fortnight.resolved, 4, reason: 'the four past rescues');
      // Most incidents first, then by name.
      final counts = [for (final b in fortnight.byBarangay) b.count];
      expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
    });

    test('count what responders reported', () {
      expect(fortnight.completionReports, 4);
      expect(fortnight.resolvedWithoutReport, 0);
      expect(fortnight.personsAssisted, 6);
      expect(fortnight.injured, 1);
      expect(fortnight.missing, 0);
      expect(fortnight.affectedFamilies, 10);
      expect(fortnight.housesDamaged, 5);
      expect(fortnight.outcomes, {
        RescueOutcome.rescued: 3,
        RescueOutcome.transported: 1,
      });
    });

    test('take response times from each incident\'s timeline', () {
      final past = source(
        now.subtract(const Duration(days: 14)),
        now.subtract(const Duration(days: 2)),
      );
      expect(past.incidents, 4);
      expect(past.dispatches, 4);
      expect(past.unitsDeployed, 2, reason: 'R-03 and R-07');
      // Assigned 5 minutes after, on scene 17 minutes after.
      expect(past.medianDispatchS, 300);
      expect(past.medianResponseS, 1020);
      expect(past.vulnerableIncidents, 2);
      expect(past.open, 0);
      // The sample alerts and the reading are from today.
      expect(past.alertsIssued, 0);
      expect(past.maxSignal, isNull);
    });

    test('include the alerts and the highest readings', () {
      final today = source(now.subtract(const Duration(days: 1)), now);
      expect(today.incidents, seed.incidents.length);
      expect(today.alertsIssued, greaterThan(0));
      expect(today.alertsSimulated, today.alertsIssued);
      expect(today.maxSignal, 2);
      expect(today.maxRainfall, 18);
      expect(today.weatherSimulated, isTrue);
      expect(today.completionReports, 0);
    });

    test('are empty for a period with nothing in it', () {
      final none = source(DateTime(2025), DateTime(2025, 2));
      expect(none.isEmpty, isTrue);
      expect(none.byType, isEmpty);
      expect(none.medianDispatchS, isNull);
    });

    test('survive the trip to and from the database', () {
      final again = ReportSource.fromJson(fortnight.toJson());
      expect(again.toJson(), fortnight.toJson());
      // A row as `report_source` returns it.
      final row = ReportSource.fromJson(const {
        'from': '2026-09-30T16:00:00+00:00',
        'to': '2026-10-01T16:00:00+00:00',
        'incidents': 3,
        'sos': 2,
        'clusters': 1,
        'resolved': 1,
        'open': 2,
        'false_reports': 0,
        'vulnerable_incidents': 1,
        'by_type': [
          {'type': 'flood', 'count': 2},
          {'type': null, 'count': 1},
        ],
        'by_barangay': [
          {'barangay': 'Barangay 412', 'district': 'Sampaloc', 'count': 3},
        ],
        'completion_reports': 1,
        'resolved_without_report': 0,
        'persons_assisted': 1,
        'injured': 0,
        'missing': 0,
        'affected_families': 1,
        'houses_damaged': 0,
        'outcomes': {'transported': 1},
        'dispatches': 2,
        'units_deployed': 2,
        'median_dispatch_s': 266,
        'median_response_s': null,
        'alerts_issued': 4,
        'alerts_simulated': 4,
        'max_signal': 4,
        'max_rainfall': 40,
        'max_surge_m': 3.0,
        'weather_simulated': true,
      });
      expect(row.byType, {IncidentType.flood: 2, null: 1});
      expect(row.outcomes, {RescueOutcome.transported: 1});
      expect(row.medianDispatchS, 266);
      expect(row.medianResponseS, isNull);
      expect(row.maxSurgeM, 3);
      expect(row.byBarangay.single.place, 'Barangay 412, Sampaloc');
    });
  });

  group('the first draft', () {
    final figures = ReportSource(
      from: DateTime.utc(2026, 9, 30, 16),
      to: DateTime.utc(2026, 10, 1, 16),
      incidents: 3,
      sos: 2,
      clusters: 1,
      resolved: 1,
      open: 1,
      falseReports: 1,
      vulnerableIncidents: 1,
      byType: const {IncidentType.flood: 2, null: 1},
      byBarangay: const [
        BarangayCount(barangay: 'Barangay 412', district: 'Sampaloc', count: 2),
        BarangayCount(barangay: 'Barangay 105', district: 'Tondo', count: 1),
      ],
      completionReports: 1,
      resolvedWithoutReport: 0,
      personsAssisted: 3,
      injured: 1,
      affectedFamilies: 2,
      housesDamaged: 4,
      outcomes: const {RescueOutcome.rescued: 1},
      dispatches: 2,
      unitsDeployed: 1,
      medianDispatchS: 266,
      medianResponseS: 842,
      alertsIssued: 1,
      maxSignal: 2,
      maxRainfall: 18,
    );
    final draft = {for (final s in draftReportSections(figures)) s.key: s.body};

    test('has every section in order, with the remarks left blank', () {
      final sections = draftReportSections(figures);
      expect(
        [for (final s in sections) s.key],
        [
          ReportSections.overview,
          ReportSections.incidents,
          ReportSections.population,
          ReportSections.damage,
          ReportSections.response,
          ReportSections.remarks,
        ],
      );
      expect(sections.first.title, 'Situation overview');
      expect(draft[ReportSections.remarks], isEmpty);
    });

    test('states the figures, in Manila time, and nothing else', () {
      expect(
        draft[ReportSections.overview],
        'From Oct 1, 2026 12:00 AM to Oct 2, 2026 12:00 AM (Manila time), '
        'the Manila Disaster Risk Reduction and Management Department '
        'recorded 3 incidents through Project S.A.G.I.P.: 2 SOS requests '
        'and 1 confirmed cluster of crowd reports. The highest tropical '
        'cyclone wind signal recorded was No. 2. Peak rainfall recorded '
        'was 18 mm per hour. 1 public alert was issued to residents.',
      );
      expect(
        draft[ReportSections.incidents],
        'By type: flood 2, not yet classified 1. By barangay: Barangay '
        '412, Sampaloc (2); Barangay 105, Tondo (1). 1 incident was '
        'resolved, 1 remains open, and 1 report was found to be false. '
        '1 incident involved a household on the Vulnerable Resident '
        'Priority List.',
      );
      expect(
        draft[ReportSections.population],
        'Responders filed 1 completion report. Persons assisted: 3. '
        'Injured: 1. Missing: 0. Affected families: 2. Outcomes: rescued 1.',
      );
      expect(
        draft[ReportSections.damage],
        'Houses reported damaged: 4, as recorded by responders in their '
        'completion reports.',
      );
      expect(
        draft[ReportSections.response],
        '2 dispatches were made, using 1 response unit. Median time from '
        'a report being received to a unit being assigned: 4 min 26 s. '
        'Median time from a report being received to a unit arriving on '
        'scene: 14 min 2 s.',
      );
    });

    test('says so when figures are missing or simulated', () {
      final thin = {
        for (final s in draftReportSections(
          ReportSource(
            from: figures.from,
            to: figures.to,
            incidents: 2,
            sos: 2,
            resolved: 2,
            resolvedWithoutReport: 2,
            byType: const {IncidentType.fire: 2},
            byBarangay: const [
              BarangayCount(
                barangay: 'Barangay 649',
                district: 'Port Area',
                count: 2,
              ),
            ],
            alertsIssued: 3,
            alertsSimulated: 3,
            maxSignal: 0,
            maxRainfall: 12.5,
            maxSurgeM: 1.2,
            weatherSimulated: true,
          ),
        ))
          s.key: s.body,
      };
      expect(
        thin[ReportSections.overview],
        allOf(
          contains('No tropical cyclone wind signal was recorded.'),
          contains('12.5 mm per hour'),
          contains('storm surge forecast was 1.2 m'),
          contains('include data from a simulated feed'),
          contains(
            '3 public alerts were issued to residents, 3 of them '
            'simulated.',
          ),
        ),
      );
      expect(
        thin[ReportSections.population],
        'Responders filed 0 completion reports. 2 resolved incidents have '
        'no completion report, so these figures are incomplete.',
      );
      expect(
        thin[ReportSections.damage],
        'No damage figures were reported in the period.',
      );
      expect(
        thin[ReportSections.response],
        '0 dispatches were made, using 0 response units.',
      );

      final empty = draftReportSections(
        ReportSource(from: figures.from, to: figures.to),
      );
      expect(empty[0].body, contains('No PAGASA reading was recorded'));
      expect(empty[1].body, 'No incidents were recorded in the period.');
    });

    test('writes whole minutes without seconds', () {
      final response = draftReportSections(
        ReportSource(
          from: figures.from,
          to: figures.to,
          incidents: 1,
          dispatches: 1,
          unitsDeployed: 1,
          medianDispatchS: 300,
          medianResponseS: 45,
        ),
      )[4].body;
      expect(response, contains('assigned: 5 min.'));
      expect(response, contains('on scene: 45 s.'));
    });

    test('gets a title from its period, in Manila dates', () {
      expect(
        defaultReportTitle(figures.from, figures.to),
        'Incident report, Oct 1, 2026',
      );
      expect(
        defaultReportTitle(
          DateTime.utc(2026, 9, 24, 16),
          DateTime.utc(2026, 10, 1, 16),
        ),
        'Incident report, Sep 25 to Oct 1, 2026',
      );
      expect(
        defaultReportTitle(
          DateTime.utc(2026, 12, 30, 16),
          DateTime.utc(2027, 1, 2, 16),
        ),
        'Incident report, Dec 31, 2026 to Jan 2, 2027',
      );
    });

    test('is checked before it is called final', () {
      final sections = draftReportSections(figures);
      // One incident is still open and the remarks are blank.
      expect(passedReportChecks(figures, sections), {
        ReportCheck.hasIncidents,
        ReportCheck.allReportsFiled,
        ReportCheck.noSimulatedData,
      });
      final written = [
        for (final s in sections)
          s.key == ReportSections.remarks ? s.withBody('None.') : s,
      ];
      expect(
        passedReportChecks(figures, written),
        contains(ReportCheck.noEmptySection),
      );
      expect(
        passedReportChecks(
          ReportSource(from: figures.from, to: figures.to),
          written,
        ),
        isNot(contains(ReportCheck.hasIncidents)),
      );
    });

    test('keeps to the limits the database sets', () {
      final sections = draftReportSections(figures);
      expect(reportTextAccepted('Report', sections), isTrue);
      expect(reportTextAccepted('  ', sections), isFalse);
      expect(reportTextAccepted('x' * 161, sections), isFalse);
      expect(reportTextAccepted('Report', const []), isFalse);
      expect(
        reportTextAccepted('Report', [sections.first.withBody('x' * 6001)]),
        isFalse,
      );
      expect(
        reportTextAccepted('Report', List.filled(13, sections.first)),
        isFalse,
      );
    });
  });

  group('the mock follows the database', () {
    late MockBackend backend;
    late MockAuthRepository auth;
    late MockReportRepository reports;
    final from = now.subtract(const Duration(days: 14));

    setUp(() async {
      backend = MockBackend(clock: () => now, latency: Duration.zero);
      auth = MockAuthRepository(backend);
      reports = MockReportRepository(backend);
      await auth.signIn(
        email: 'admin@sagip.test',
        password: MockSeed.demoPassword,
      );
    });

    tearDown(() => backend.dispose());

    test('only admins read the figures or save reports', () async {
      await auth.signOut();
      await auth.signIn(
        email: 'dispatcher@sagip.test',
        password: MockSeed.demoPassword,
      );
      await expectLater(
        reports.source(from, now),
        rejected(ActionRejection.notAllowed),
      );
      await expectLater(
        reports.save(
          from: from,
          to: now,
          title: 'Report',
          sections: const [
            ReportSection(key: 'overview', title: 'Overview', body: 'Text.'),
          ],
        ),
        rejected(ActionRejection.notAllowed),
      );
    });

    test('a draft keeps its figures, can be edited, then is final', () async {
      final figures = await reports.source(from, now);
      expect(figures.completionReports, 4);
      await expectLater(
        reports.source(now, from),
        rejected(ActionRejection.invalidValue),
      );

      final id = await reports.save(
        from: from,
        to: now,
        title: ' Flood report ',
        sections: draftReportSections(figures),
        generationMs: 1800,
      );
      expect(id, 'RPT-0001');
      var saved = (await reports.watchReports().first).single;
      expect(saved.title, 'Flood report');
      expect(saved.status, ReportStatus.draft);
      expect(saved.method, ReportMethod.assembled);
      expect(saved.createdByName, 'E. Navarro');
      expect(saved.generationMs, 1800);
      expect(saved.source.personsAssisted, 6);
      expect(saved.periodStart, from);

      // Editing changes the text, not the period or its figures.
      await reports.save(
        id: id,
        from: DateTime(2020),
        to: DateTime(2020, 2),
        title: 'Flood report, revised',
        sections: [
          for (final s in saved.sections)
            s.key == ReportSections.remarks ? s.withBody('None.') : s,
        ],
      );
      saved = (await reports.watchReports().first).single;
      expect(saved.title, 'Flood report, revised');
      expect(saved.sections.last.body, 'None.');
      expect(saved.periodStart, from);
      expect(saved.source.personsAssisted, 6);

      await expectLater(
        reports.save(
          id: 'RPT-9999',
          from: from,
          to: now,
          title: 'Report',
          sections: saved.sections,
        ),
        rejected(ActionRejection.notFound),
      );
      await expectLater(
        reports.save(from: from, to: now, title: ' ', sections: saved.sections),
        rejected(ActionRejection.invalidValue),
      );

      await reports.finalize(id);
      saved = (await reports.watchReports().first).single;
      expect(saved.isFinal, isTrue);
      expect(saved.finalizedByName, 'E. Navarro');
      await expectLater(
        reports.finalize(id),
        rejected(ActionRejection.alreadyFinal),
      );
      await expectLater(
        reports.save(
          id: id,
          from: from,
          to: now,
          title: 'Changed',
          sections: saved.sections,
        ),
        rejected(ActionRejection.alreadyFinal),
      );

      final audit = await MockAuditRepository(backend).watchRecent().first;
      expect(
        [
          for (final e in audit.reversed)
            if (e.action == AuditAction.reportDrafted ||
                e.action == AuditAction.reportFinalized)
              '${e.action.name} ${e.detail}',
        ],
        ['reportDrafted Flood report', 'reportFinalized Flood report, revised'],
      );
    });

    test('a report row from the database parses', () {
      final report = NdrrmcReport.fromJson({
        'report_id': 'RPT-0003',
        'period_start': '2026-09-30T16:00:00+00:00',
        'period_end': '2026-10-01T16:00:00+00:00',
        'title': 'Flood report',
        'status': 'final',
        'method': 'assembled',
        'source': {
          'from': '2026-09-30T16:00:00+00:00',
          'to': '2026-10-01T16:00:00+00:00',
          'incidents': 2,
        },
        'sections': [
          {'key': 'overview', 'title': 'Situation overview', 'body': 'Text.'},
        ],
        'generation_ms': 4200,
        'created_by_name': 'Test Admin',
        'created_at': '2026-10-01T08:00:00+00:00',
        'updated_at': '2026-10-01T09:00:00+00:00',
        'finalized_at': '2026-10-01T09:00:00+00:00',
        'finalized_by_name': 'Test Admin',
      });
      expect(report.isFinal, isTrue);
      expect(report.source.incidents, 2);
      expect(report.sections.single.body, 'Text.');
      expect(report.generationMs, 4200);
      expect(report.periodEnd.isAfter(report.periodStart), isTrue);
    });
  });
}
