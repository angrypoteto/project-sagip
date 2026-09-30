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

  Future<void> signIn(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      MockSeed.demoPassword,
    );
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
      find.widgetWithText(FilledButton, 'Save changes'),
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await settle(tester);
    expect(find.text('Settings saved'), findsOneWidget);
    expect(container.read(priorityRulesProvider).sosPoints, 60);
    expect(find.text('Last changed by E. Navarro'), findsOneWidget);

    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);
    expect(find.text('Changed a setting'), findsOneWidget);
    expect(find.text('50 → 60'), findsOneWidget);
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
