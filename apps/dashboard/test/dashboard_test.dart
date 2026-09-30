import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_dashboard/src/app.dart';
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
