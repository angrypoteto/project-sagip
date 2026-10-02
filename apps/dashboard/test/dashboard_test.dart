import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_dashboard/src/app.dart';
import 'package:sagip_dashboard/src/common/download.dart';
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
    // Every sample incident arrived within the last 7 days.
    final report = container.read(analyticsProvider).value!;
    expect(report.incidents, active);

    await tester.tap(find.text('Last 24 hours'));
    await settle(tester);
    expect(container.read(analyticsPeriodProvider), AnalyticsPeriod.day);

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    expect(lastDownload!.name, endsWith('.csv'));
    expect(lastDownload!.text, contains('median_dispatch_s'));
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
