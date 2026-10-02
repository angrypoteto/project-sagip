import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_dashboard/src/app.dart';
import 'package:sagip_dashboard/src/common/download.dart';
import 'package:sagip_dashboard/src/features/admin/report_pdf.dart';
import 'package:sagip_dashboard/src/features/board/incident_drawer.dart';
import 'package:sagip_dashboard/src/providers.dart';
import 'package:sagip_dashboard/src/router.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// pumpAndSettle with a short limit, so an endless animation fails fast
/// with a clear message instead of hanging the run.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

void main() {
  final now = DateTime(2026, 10, 1, 15, 42);
  late MockBackend backend;
  late ProviderContainer container;

  setUp(() {
    backend = MockBackend(clock: () => now, latency: Duration.zero);
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        mapTilesEnabledProvider.overrideWithValue(false),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        slowClockProvider.overrideWith((ref) => Stream.value(now)),
        analyticsNowProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SagipDashboardApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> signIn(
    WidgetTester tester,
    String email, {
    String password = MockSeed.demoPassword,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.text('Sign in'));
    await settle(tester);
  }

  /// The drawer builds lazily; scroll it until [target] is on screen.
  Future<void> revealInDrawer(WidgetTester tester, Finder target) async {
    final drawerList = find.descendant(
      of: find.byType(IncidentDrawer),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(target, 200, scrollable: drawerList.first);
    await settle(tester);
  }

  testWidgets('sign-in is required and a wrong password is explained', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Sign in to the command board'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'dispatcher@sagip.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('the queue is ranked with the vulnerable SOS first', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');

    expect(find.text('Triage queue'), findsOneWidget);
    final rows = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Text),
      ),
    );
    final firstTitle = rows.first.data;
    expect(firstTitle, 'SOS, flood');
    expect(find.text('Barangay 412, Sampaloc'), findsWidgets);
  });

  testWidgets('a dispatcher assigns the top suggested unit', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');

    await tester.tap(find.text('SOS, flood').first);
    await settle(tester);
    expect(find.text('Incident INC-0147'), findsOneWidget);
    await revealInDrawer(tester, find.text('Suggested units'));
    expect(find.text('Suggested units'), findsOneWidget);
    // Ranked by Dijkstra over the bundled road graph, not straight lines.
    expect(
      find.text('Available units, by travel time on the road network'),
      findsOneWidget,
    );

    await tester.tap(find.text('Assign R-03'));
    await settle(tester);

    expect(find.text('R-03 assigned'), findsOneWidget);
    expect(find.text('Assigned unit'), findsOneWidget);
    // Read through the app's own state; awaiting a raw stream inside the
    // widget-test fake clock can wait forever.
    final incident = container.read(incidentByIdProvider('INC-0147'))!;
    expect(incident.status, IncidentStatus.assigned);
    expect(incident.assignedUnitId, 'unit-r03');
    // The unit's road route went with the assignment (dispatch record).
    final route = backend.routeFor('INC-0147')!;
    expect(route.points.last, incident.location);
    expect(route.steps, isNotEmpty);
  });

  testWidgets('choosing a unit other than the top one asks for a reason', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.text('SOS, flood').first);
    await settle(tester);

    await revealInDrawer(tester, find.text('R-07'));
    await tester.tap(find.text('R-07'));
    await settle(tester);
    await tester.tap(find.text('Assign R-07'));
    await settle(tester);
    expect(
      find.text('Assign R-07 instead of the top suggestion?'),
      findsOneWidget,
    );

    // Without a reason, the dialog refuses.
    await tester.tap(find.widgetWithText(FilledButton, 'Assign R-07').last);
    await settle(tester);
    expect(find.text('Choose a reason.'), findsOneWidget);
  });

  testWidgets('admin pages are hidden from dispatchers', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    expect(find.byTooltip('Audit log'), findsNothing);

    container.read(routerProvider).go(Routes.auditLog);
    await settle(tester);
    expect(find.text('Page not found'), findsOneWidget);
  });

  testWidgets('admins see the audit log', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Assigned unit'), findsWidgets);
  });

  testWidgets('admins change priority weights on A3, checked and audited', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Configuration'));
    await settle(tester);
    expect(find.text('Triage Queue priority'), findsOneWidget);
    expect(find.text('Algorithm parameters'), findsOneWidget);

    FilledButton save() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-priority')),
    );
    expect(save().onPressed, isNull, reason: 'nothing changed yet');

    // Out of range: explained, and Save stays off.
    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.waiting_per_minute')),
      '500',
    );
    await tester.pump();
    expect(find.text('Use a number from 0 to 20.'), findsOneWidget);
    expect(save().onPressed, isNull);

    // High above Critical is refused before it reaches the server.
    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.waiting_per_minute')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.high_at')),
      '90',
    );
    await tester.pump();
    // Both fields in the conflict say so.
    expect(find.text('High must be at or below Critical.'), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.high_at')),
      '50',
    );

    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.sos')),
      '60',
    );
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('save-priority')));
    await settle(tester);
    expect(find.text('Settings saved'), findsOneWidget);
    expect(container.read(priorityRulesProvider).sosPoints, 60);
    expect(find.text('Last changed by E. Navarro'), findsOneWidget);

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Changed a setting'), findsOneWidget);
    expect(find.text('50 → 60'), findsOneWidget);
  });

  testWidgets('admins set the hourly crowd report limit on A3', (tester) async {
    await pumpApp(tester);
    // Tall, so the card below the priority weights is on screen.
    tester.view.physicalSize = const Size(1440, 2400);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Configuration'));
    await settle(tester);
    expect(find.text('Crowd reports'), findsOneWidget);
    expect(find.text('Reports per account each hour'), findsWidgets);

    final field = find.byKey(const ValueKey('setting-reports.per_hour'));
    final saveKey = find.byKey(const ValueKey('save-reports'));
    FilledButton save() => tester.widget<FilledButton>(saveKey);
    expect(save().onPressed, isNull, reason: 'nothing changed yet');

    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Use a number from 1 to 30.'), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.enterText(field, '8');
    await tester.pump();
    await tester.tap(saveKey);
    await settle(tester);
    expect(find.text('Settings saved'), findsOneWidget);
    final settings = container.read(settingsProvider).requireValue;
    expect(
      settings.firstWhere((s) => s.key == SettingKeys.reportsPerHour).value,
      8,
    );

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('5 → 8'), findsOneWidget);
  });

  testWidgets('A3: thresholds, channels, numbers, and a simulated typhoon', (
    tester,
  ) async {
    await pumpApp(tester);
    // Tall, so every card on the page is on screen.
    tester.view.physicalSize = const Size(1440, 4200);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Configuration'));
    await settle(tester);
    for (final title in [
      'Alert thresholds',
      'Alert channels',
      'SMS alert limit',
      'Numbers shown in the apps',
      'Simulation mode',
    ]) {
      expect(find.text(title), findsWidgets);
    }
    AppSetting setting(String key) => container
        .read(settingsProvider)
        .requireValue
        .firstWhere((s) => s.key == key);
    bool enabled(String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed !=
        null;

    // A warning above its critical value is explained on both fields.
    final rainWarning = find.byKey(
      const ValueKey('setting-alerts.rainfall_warning'),
    );
    await tester.enterText(rainWarning, '40');
    await tester.pump();
    expect(
      find.text('Warning must be at or below Critical.'),
      findsNWidgets(2),
    );
    expect(enabled('save-alerts'), isFalse);
    await tester.enterText(rainWarning, '20');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-alerts')));
    await settle(tester);
    expect(container.read(alertThresholdsProvider).rainfallWarning, 20);

    // A switch applies at once.
    await tester.tap(find.byKey(const ValueKey('switch-channels.sms')));
    await settle(tester);
    expect(setting(SettingKeys.smsChannel).flag, isFalse);

    // The gateway must be a mobile number; it is kept as +63...
    final gateway = find.byKey(const ValueKey('setting-contact.sms_gateway'));
    await tester.enterText(gateway, '12345');
    await tester.pump();
    expect(
      find.textContaining('Enter a Philippine mobile number'),
      findsOneWidget,
    );
    expect(enabled('save-contact'), isFalse);
    await tester.enterText(gateway, '0917 555 0199');
    await tester.enterText(
      find.byKey(const ValueKey('setting-contact.hotline')),
      '(02) 8527-0000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-contact')));
    await settle(tester);
    expect(setting(SettingKeys.smsGateway).text, '+639175550199');
    expect(setting(SettingKeys.hotline).text, '(02) 8527-0000');
    expect(tester.widget<TextField>(gateway).controller!.text, '+639175550199');

    // Simulated readings need simulation mode.
    expect(enabled('simulate-typhoon'), isFalse);
    await tester.tap(find.byKey(const ValueKey('switch-demo.simulation')));
    await settle(tester);
    expect(enabled('simulate-typhoon'), isTrue);
    await tester.tap(find.byKey(const ValueKey('simulate-typhoon')));
    await settle(tester);

    // D10: the reading against the thresholds, and the alerts it raised.
    await tester.tap(find.byTooltip('Weather and advisories'));
    await settle(tester);
    // On the card and in the top bar.
    expect(find.text('Signal No. 3'), findsNWidgets(2));
    expect(find.text('Up to 2.5 m'), findsOneWidget);
    for (final card in ['signal', 'rainfall', 'surge']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('level-$card')),
          matching: find.text('Critical'),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Warning from 20, critical from 30'), findsOneWidget);
    expect(find.text('Wind Signal No. 3 raised over Manila'), findsOneWidget);
    expect(find.text('Torrential rainfall warning'), findsOneWidget);
    expect(find.text('Storm surge warning for Manila Bay'), findsOneWidget);
    expect(find.text('Raised by a threshold'), findsNWidgets(3));
    // Three new simulated alerts on top of the four samples: in the apps,
    // never texted.
    expect(find.text('Simulated'), findsNWidgets(7));
    expect(find.text('In the apps: Sent'), findsNWidgets(7));
    expect(find.text('SMS: Not sent (simulated)'), findsNWidgets(7));

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Simulated a weather reading'), findsOneWidget);
    expect(find.text('Signal 3, 35 mm/hr, surge 2.5 m'), findsOneWidget);
    expect(find.text('true → false'), findsOneWidget);
  });

  testWidgets('A3 asks before leaving with unsaved changes', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Configuration'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('setting-priority.sos')),
      '60',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await settle(tester);
    expect(find.text('Triage Queue priority'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('setting-priority.sos')))
          .controller!
          .text,
      '60',
      reason: 'the edit is still there',
    );

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    await tester.tap(find.text('Leave'));
    await settle(tester);
    expect(find.text('Triage Queue priority'), findsNothing);
    expect(container.read(priorityRulesProvider).sosPoints, 50);

    // With nothing unsaved, leaving does not ask.
    await tester.tap(find.byTooltip('Configuration'));
    await settle(tester);
    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Leave without saving?'), findsNothing);
  });

  testWidgets('D10: readings against the thresholds and the alert log', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(1440, 2400);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.byTooltip('Weather and advisories'));
    await settle(tester);
    // The sample reading: signal 2 and 18 mm/hr are warnings.
    // On the card and in the top bar.
    expect(find.text('Signal No. 2'), findsNWidgets(2));
    for (final card in ['signal', 'rainfall']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('level-$card')),
          matching: find.text('Warning'),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('level-surge')), findsNothing);
    expect(find.text('Warning from 15, critical from 30'), findsOneWidget);
    expect(find.text('Warning from 1, critical from 3'), findsOneWidget);

    expect(find.text('Alerts sent'), findsOneWidget);
    expect(
      find.text('Orange rainfall warning for Metro Manila'),
      findsOneWidget,
    );
    expect(find.text('Barangay 412, Barangay 490'), findsOneWidget);
    expect(find.text('All of Manila'), findsNWidgets(3));
    expect(find.text('Push: Not sent (simulated)'), findsNWidgets(4));
  });

  testWidgets('D10: issue an advisory after a review, then end it', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(1440, 2400);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.byTooltip('Weather and advisories'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('issue-advisory')));
    await settle(tester);
    // Nothing typed yet: the review step is not reached.
    await tester.tap(find.byKey(const ValueKey('advisory-review')));
    await settle(tester);
    expect(find.text('Give the advisory a title.'), findsOneWidget);
    expect(find.text('Write the message.'), findsOneWidget);
    expect(find.text('Review before sending'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'PHIVOLCS'));
    await tester.tap(find.byKey(const ValueKey('advisory-level-info')));
    await tester.enterText(
      find.byKey(const ValueKey('advisory-title')),
      'Taal Volcano advisory',
    );
    await tester.enterText(
      find.byKey(const ValueKey('advisory-body')),
      'Light ashfall may reach Manila.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('advisory-steps')),
      'Wear a face mask.\n\nKeep windows closed.',
    );
    await tester.tap(find.byKey(const ValueKey('advisory-some')));
    await settle(tester);
    // Chosen barangays, but none chosen.
    await tester.tap(find.byKey(const ValueKey('advisory-review')));
    await settle(tester);
    expect(find.text('Choose at least one barangay.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Barangay 490'));
    await tester.tap(find.widgetWithText(FilterChip, 'Barangay 412'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('advisory-review')));
    await settle(tester);

    // The review: the advisory as residents see it, and where it goes.
    expect(find.text('Review before sending'), findsOneWidget);
    expect(find.text('• Wear a face mask.'), findsOneWidget);
    expect(find.text('• Keep windows closed.'), findsOneWidget);
    expect(
      find.text('For residents in Barangay 412, Barangay 490.'),
      findsOneWidget,
    );
    expect(
      find.text('It appears in the apps at once and is queued for Push, SMS.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('advisory-send')));
    await settle(tester);

    expect(find.text('Advisory issued'), findsOneWidget);
    final sent = (await tester.runAsync(
      () => MockAlertLogRepository(backend).watchRecent().first,
    ))!.first;
    expect(sent.alert.source, AlertSource.phivolcs);
    expect(sent.alert.level, AlertLevel.info);
    expect(sent.alert.guidance, ['Wear a face mask.', 'Keep windows closed.']);
    expect(sent.alert.barangays, ['Barangay 412', 'Barangay 490']);
    expect(sent.on(AlertChannel.sms)!.status, AlertDeliveryStatus.queued);
    expect(find.text('Taal Volcano advisory'), findsOneWidget);

    // End it: asked first, then the row has no End button.
    final end = find.byKey(ValueKey('end-${sent.alert.id}'));
    await tester.ensureVisible(end);
    await tester.tap(end);
    await settle(tester);
    expect(find.text('End this alert?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'End alert').last);
    await settle(tester);
    // It waits behind the "Advisory issued" snackbar.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Alert ended'), findsOneWidget);
    expect(end, findsNothing);
    final audit = await tester.runAsync(
      () => MockAuditRepository(backend).watchRecent().first,
    );
    expect(
      {
        for (final e in audit!)
          if (e.targetId == sent.alert.id) e.action,
      },
      {AuditAction.alertIssued, AuditAction.alertEnded},
    );

    // Offline, nothing can be issued or ended.
    backend.setLink(LinkState.offline);
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('issue-advisory')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('D10: in simulation mode the review says nothing is sent', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(1440, 2400);
    await signIn(tester, 'admin@sagip.test');
    await tester.runAsync(
      () => MockSettingsRepository(backend).set(SettingKeys.simulation, true),
    );
    await tester.tap(find.byTooltip('Weather and advisories'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('issue-advisory')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('advisory-title')),
      'Evacuate Baseco',
    );
    await tester.enterText(
      find.byKey(const ValueKey('advisory-body')),
      'Drill only.',
    );
    await tester.tap(find.byKey(const ValueKey('advisory-review')));
    await settle(tester);
    expect(find.text('For residents in all of Manila.'), findsOneWidget);
    expect(find.textContaining('Simulation mode is on'), findsOneWidget);

    // Back keeps what was typed.
    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.text('Evacuate Baseco'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('advisory-review')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('advisory-send')));
    await settle(tester);
    final sent = (await tester.runAsync(
      () => MockAlertLogRepository(backend).watchRecent().first,
    ))!.first;
    expect(sent.alert.isSimulated, isTrue);
    expect(sent.on(AlertChannel.sms)!.status, AlertDeliveryStatus.simulated);
  });

  testWidgets('D8: the forecast ranked by hazard, with a barangay panel', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.byTooltip('Forecast'));
    await settle(tester);

    expect(find.text('72-hour forecast'), findsOneWidget);
    expect(find.text('Sample forecast'), findsOneWidget);
    expect(find.textContaining('Sample values, not model output'), findsOne);
    expect(find.byKey(const ValueKey('forecast-stale')), findsNothing);

    double top(String barangay) =>
        tester.getTopLeft(find.byKey(ValueKey('forecast-row-$barangay'))).dy;
    // Flood: the three Sampaloc barangays are high.
    expect(find.text('3 high, 5 moderate, 0 low'), findsOneWidget);
    expect(top('Barangay 412'), lessThan(top('Barangay 105')));
    expect(top('Barangay 560'), lessThan(top('Barangay 105')));

    // Storm surge: the bay side comes first.
    await tester.tap(find.text('Storm surge'));
    await settle(tester);
    expect(find.text('2 high, 1 moderate, 5 low'), findsOneWidget);
    expect(top('Barangay 649'), lessThan(top('Barangay 105')));
    expect(top('Barangay 105'), lessThan(top('Barangay 412')));

    // No barangay chosen yet: no panel.
    expect(find.byKey(const ValueKey('forecast-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forecast-row-Barangay 412')));
    await settle(tester);
    final panel = find.byKey(const ValueKey('forecast-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Risk by hazard')),
      findsOneWidget,
    );
    // All three hazards, whatever the list is showing.
    expect(
      find.descendant(of: panel, matching: find.text('High')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Low')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text('Signal No. 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.textContaining('These are sample values'),
      ),
      findsOneWidget,
    );

    // The registered vulnerable residents there, and the way to D9.
    final here = container
        .read(vulnerableResidentsProvider)
        .value!
        .where((r) => r.barangay == 'Barangay 412')
        .toList();
    expect(here, isNotEmpty);
    expect(
      find.descendant(
        of: panel,
        matching: find.text(
          here.length == 1 ? '1 resident' : '${here.length} residents',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('forecast-open-list')));
    await settle(tester);
    expect(find.text('Vulnerable Resident Priority List'), findsOneWidget);
    expect(find.text('Barangay 412 only'), findsOneWidget);
    expect(find.text(here.first.fullName), findsOneWidget);
    final elsewhere = container
        .read(vulnerableResidentsProvider)
        .value!
        .firstWhere((r) => r.barangay != 'Barangay 412');
    expect(find.text(elsewhere.fullName), findsNothing);
    await tester.tap(find.text('Show all barangays'));
    await settle(tester);
    expect(find.text('Barangay 412 only'), findsNothing);
    expect(find.text(elsewhere.fullName), findsOneWidget);
  });

  testWidgets('D8: an overdue run is flagged; no run is said plainly', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.byTooltip('Forecast'));
    await settle(tester);

    // Barangays the run has nothing for are listed apart, without a risk.
    expect(find.text('No forecast'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('forecast-row-Barangay 306')),
      findsOneWidget,
    );

    final issued = now.subtract(const Duration(hours: 30));
    backend.setForecast(
      ForecastRun.latest([
        BarangayForecast(
          barangay: 'Barangay 412',
          district: 'Sampaloc',
          issuedAt: issued,
          validUntil: issued.add(const Duration(hours: 72)),
          risks: const {ForecastHazard.flood: RiskLevel.high},
          modelVersion: 'lstm-kde-1',
        ),
      ]),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('forecast-stale')), findsOneWidget);
    expect(find.text('Sample forecast'), findsNothing);
    expect(find.text('1 high, 0 moderate, 0 low'), findsOneWidget);

    backend.setForecast(null);
    await settle(tester);
    expect(find.text('No forecast generated yet.'), findsOneWidget);
  });

  testWidgets('admins see analytics for a period and export them', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('Analytics'));
    await settle(tester);

    final active = container.read(activeIncidentsProvider).value!.length;
    expect(find.text('Median dispatch time'), findsOneWidget);
    expect(find.text('Incidents per day'), findsOneWidget);
    expect(find.text('By unit'), findsOneWidget);
    // The active incidents, and the two past rescues of the last 7 days.
    final report = container.read(analyticsProvider).value!;
    expect(report.incidents, active + 2);

    await tester.tap(find.text('Last 24 hours'));
    await settle(tester);
    expect(container.read(analyticsPeriodProvider), AnalyticsPeriod.day);

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    expect(lastDownload!.name, endsWith('.csv'));
    expect(lastDownload!.text, contains('median_dispatch_s'));
  });

  testWidgets('A5 and A6: draft a report from the records, edit, finalize', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(1440, 2600);
    await signIn(tester, 'admin@sagip.test');
    await tester.tap(find.byTooltip('NDRRMC reports'));
    await settle(tester);
    expect(find.text('No reports yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-new')));
    await settle(tester);
    expect(find.text('Period to report on'), findsOneWidget);
    // The last 7 days: today's incidents and two of the past rescues.
    await tester.tap(find.byKey(const ValueKey('report-collect')));
    await settle(tester);

    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('report-title')),
    );
    expect(title.controller!.text, startsWith('Incident report, '));
    TextField section(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey('report-section-$key')));
    expect(
      section('population').controller!.text,
      startsWith('Responders filed 2 completion reports.'),
    );
    expect(section('remarks').controller!.text, isEmpty);
    expect(find.text('From the records'), findsOneWidget);
    expect(find.text('Completion reports'), findsOneWidget);
    // Today's incidents are still open and the remarks are blank.
    expect(find.byKey(const ValueKey('check-hasIncidents-ok')), findsOne);
    expect(find.byKey(const ValueKey('check-allReportsFiled-ok')), findsOne);
    expect(find.byKey(const ValueKey('check-noneOpen-open')), findsOne);
    expect(find.byKey(const ValueKey('check-noEmptySection-open')), findsOne);
    expect(find.text('Draft'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-save')));
    await settle(tester);
    expect(find.text('Draft saved'), findsOneWidget);
    expect(find.text('RPT-0001'), findsOneWidget);
    var saved = (await tester.runAsync(
      () => MockReportRepository(backend).watchReports().first,
    ))!.single;
    expect(saved.status, ReportStatus.draft);
    expect(saved.source.completionReports, 2);
    expect(saved.createdByName, 'E. Navarro');
    expect(saved.generationMs, isNotNull);
    // Nothing typed since: nothing to save.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('report-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('report-section-remarks')),
      'Clear the drains on Dapitan St before the next rain.',
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('check-noEmptySection-ok')), findsOne);
    // Leaving now would lose the remarks: asked first, and Stay stays.
    container.read(routerProvider).go(Routes.reports);
    await settle(tester);
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await settle(tester);
    expect(find.byKey(const ValueKey('report-title')), findsOneWidget);

    // Marking it final saves what is on screen first, and says what is
    // still not met.
    await tester.tap(find.byKey(const ValueKey('report-finalize')));
    await settle(tester);
    expect(find.text('Mark this report as final?'), findsOneWidget);
    expect(find.text('2 checks are not met:'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-finalize-confirm')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    saved = (await tester.runAsync(
      () => MockReportRepository(backend).watchReports().first,
    ))!.single;
    expect(saved.isFinal, isTrue);
    expect(
      saved.sections.last.body,
      'Clear the drains on Dapitan St before the next rain.',
    );
    expect(find.text('Final'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-save')), findsNothing);
    expect(find.byKey(const ValueKey('report-finalize')), findsNothing);
    expect(section('remarks').readOnly, isTrue);
    expect(find.byKey(const ValueKey('report-download')), findsOneWidget);

    // Back on the list.
    container.read(routerProvider).go(Routes.reports);
    await settle(tester);
    expect(find.text('Leave without saving?'), findsNothing);
    expect(find.text('RPT-0001'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
    final audit = await tester.runAsync(
      () => MockAuditRepository(backend).watchRecent().first,
    );
    expect(
      {
        for (final e in audit!)
          if (e.targetId == 'RPT-0001') e.action,
      },
      {AuditAction.reportDrafted, AuditAction.reportFinalized},
    );

    // A dispatcher has no reports page.
    await tester.runAsync(() => MockAuthRepository(backend).signOut());
    await settle(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    expect(find.byTooltip('NDRRMC reports'), findsNothing);
    container.read(routerProvider).go(Routes.report('RPT-0001'));
    await settle(tester);
    expect(find.text('Page not found'), findsOneWidget);
  });

  testWidgets('A6: the report as a PDF', (tester) async {
    final bytes = await tester.runAsync(
      () => buildReportPdf(
        title: 'Incident report, Oct 1, 2026',
        sections: const [
          ReportSection(
            key: 'overview',
            title: 'Situation overview',
            body: 'From Oct 1 to Oct 2 the department recorded 3 incidents.',
          ),
          ReportSection(
            key: 'remarks',
            title: 'Remarks and recommendations',
            body: '',
          ),
        ],
        labels: const ReportPdfLabels(
          agency: 'Manila Disaster Risk Reduction and Management Department',
          period: 'Period covered: Oct 1, 2026 to Oct 2, 2026',
          status: 'Status: draft, not yet final',
          prepared: null,
          footer: 'Prepared with Project S.A.G.I.P.',
          emptySection: '(Nothing written.)',
        ),
      ),
    );
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  testWidgets('admins manage units and the roster on A2', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    // A tall window so both tables are on screen without scrolling (the
    // width stays 1440 px, the smallest the dashboard supports).
    tester.view.physicalSize = const Size(1440, 2400);
    await tester.tap(find.byTooltip('Resources'));
    await settle(tester);
    expect(find.text('Responder roster'), findsOneWidget);

    Future<void> fillUnit(String callSign, String station, String crew) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Add unit'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('unit-call-sign')),
        callSign,
      );
      await tester.enterText(
        find.byKey(const ValueKey('unit-station')),
        station,
      );
      await tester.enterText(find.byKey(const ValueKey('unit-crew')), crew);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
    }

    // Field checks come first, then the database's.
    await fillUnit('R 20', 'Paco station', '0');
    expect(
      find.text('Use letters, numbers, and dashes, up to 12 characters.'),
      findsOneWidget,
    );
    expect(find.text('Use a number from 1 to 50.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    await fillUnit('r-03', 'Tondo station', '3');
    expect(
      find.text('Another unit already uses that call sign.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    // Let the error message go before the next one shows.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    await fillUnit('r-20', 'Paco station', '5');
    expect(find.text('R-20 saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    // Put C. Garcia on R-20.
    await tester.tap(find.byKey(const ValueKey('roster-usr-resp-04')));
    await settle(tester);
    await tester.tap(find.text('R-20').last);
    await settle(tester);
    expect(find.text('Roster updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    // A unit on a job cannot be retired; a free one can, after asking.
    final busy = tester.widget<IconButton>(
      find.byKey(const ValueKey('retire-unit-r05')),
    );
    expect(busy.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('retire-unit-r20')));
    await settle(tester);
    expect(find.text('Retire R-20?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
    await settle(tester);
    expect(find.text('R-20 retired'), findsOneWidget);
    expect(find.text('Retired'), findsOneWidget);
    final garcia = container
        .read(respondersProvider)
        .value!
        .firstWhere((s) => s.id == 'usr-resp-04');
    expect(garcia.unitId, isNull, reason: 'retiring takes the crew off');

    // Streams are read outside the fake clock (see docs/PROGRESS.md).
    final audit = await tester.runAsync(
      () => MockAuditRepository(backend).watchRecent().first,
    );
    expect(
      audit!.map((e) => e.action),
      containsAll([
        AuditAction.unitAdded,
        AuditAction.rosterChanged,
        AuditAction.unitRetired,
      ]),
    );
  });

  testWidgets('D11: theme and password change, with the checks', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.byTooltip('R. Santos, Dispatcher'));
    await settle(tester);
    await tester.tap(find.text('My account'));
    await settle(tester);
    expect(find.text('dispatcher@sagip.test'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await settle(tester);
    expect(container.read(themeModeProvider), ThemeMode.light);

    Future<void> change(String current, String next, String again) async {
      await tester.enterText(
        find.byKey(const ValueKey('password-current')),
        current,
      );
      await tester.enterText(find.byKey(const ValueKey('password-new')), next);
      await tester.enterText(
        find.byKey(const ValueKey('password-again')),
        again,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await settle(tester);
    }

    await change(MockSeed.demoPassword, 'short', 'short');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await change(MockSeed.demoPassword, 'newpass123', 'newpass124');
    expect(find.text('The two new passwords are different.'), findsOneWidget);
    await change('not-it-at-all', 'newpass123', 'newpass123');
    expect(find.text('The current password is not right.'), findsOneWidget);
    await change(MockSeed.demoPassword, 'newpass123', 'newpass123');
    expect(find.text('Password changed'), findsOneWidget);

    // The new password is the one that works now.
    await tester.runAsync(() => MockAuthRepository(backend).signOut());
    await settle(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    expect(find.text('Email or password is incorrect.'), findsWidgets);
    await signIn(tester, 'dispatcher@sagip.test', password: 'newpass123');
    expect(
      container.read(currentUserProvider).value?.email,
      'dispatcher@sagip.test',
    );
    // Back on the page it came from.
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testWidgets(
    'G2: an expired session returns to the same page after signing in',
    (tester) async {
      await pumpApp(tester);
      await signIn(tester, 'admin@sagip.test');
      await tester.tap(find.byTooltip('Units'));
      await settle(tester);

      backend.expireSession();
      await settle(tester);
      expect(find.text('Your session expired'), findsOneWidget);

      await tester.tap(find.text('Sign in again'));
      await settle(tester);
      await signIn(tester, 'admin@sagip.test');
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        Routes.units,
      );
    },
  );

  testWidgets('A1: create an account, deactivate one, suspend a resident', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@sagip.test');
    tester.view.physicalSize = const Size(1440, 2000);
    await tester.tap(find.byTooltip('Accounts'));
    await settle(tester);

    // Admins cannot act on their own row here.
    expect(find.byKey(const ValueKey('active-usr-admin-01')), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'new.dispatcher@sagip.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-name')),
      'New Dispatcher',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account').last);
    await settle(tester);
    expect(find.text('Temporary password'), findsOneWidget);
    expect(find.text('Temp1001pass'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('New Dispatcher'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('active-usr-disp-01')));
    await settle(tester);
    expect(find.text('Deactivate R. Santos?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await settle(tester);
    expect(find.text('Deactivated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    await tester.tap(find.text('Residents'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('suspend-res-001')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await settle(tester);
    expect(find.text('Suspended'), findsOneWidget);

    final audit = await tester.runAsync(
      () => MockAuditRepository(backend).watchRecent().first,
    );
    expect(
      audit!.map((e) => e.action),
      containsAll([
        AuditAction.accountCreated,
        AuditAction.accountDeactivated,
        AuditAction.residentSuspended,
      ]),
    );
  });

  testWidgets('going offline shows a banner and disables actions', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'dispatcher@sagip.test');
    await tester.tap(find.text('SOS, flood').first);
    await settle(tester);

    backend.setLink(LinkState.offline);
    await settle(tester);

    expect(find.textContaining("You're offline."), findsOneWidget);
    expect(find.text('Reconnect to take actions.'), findsOneWidget);
    final assign = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Assign R-03'),
    );
    expect(assign.onPressed, isNull);
  });
}
