import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_mobile/src/router.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Part 4b screens: R5 location picker, R6 My activity, R7 and R8 alerts,
/// R9 to R11 vulnerability profile, and F7 assignment history.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

class WelcomeDone extends WelcomeSeen {
  @override
  bool build() => true;
}

void main() {
  // A Wednesday, so "This week" starts on Monday, Sep 28.
  final now = DateTime(2026, 9, 30, 15, 42);
  late MockMobileBackend backend;
  late ProviderContainer container;

  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  Future<void> pumpApp(WidgetTester tester, {bool history = false}) async {
    backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
      withHistory: history,
    );
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend),
        mapTilesEnabledProvider.overrideWithValue(false),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        welcomeSeenProvider.overrideWith(WelcomeDone.new),
      ],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SagipMobileApp(),
      ),
    );
    await settle(tester);
  }

  /// Taps [text], scrolling to it first if the list has not built it yet.
  Future<void> tap(WidgetTester tester, String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(f.first);
    await tester.tap(f.first);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  /// Lets any message go; they float over the bottom of the screen.
  Future<void> clearMessages(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('R6: past SOS and reports, and what happened to a report', (
    tester,
  ) async {
    await pumpApp(tester, history: true);
    await tap(tester, 'Continue as resident');
    await tap(tester, 'Me');
    await tap(tester, 'My activity');

    expect(find.text('Flood'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);

    await tap(tester, 'Reports');
    expect(
      find.text('Knee-deep flood on Dapitan St near the market'),
      findsOneWidget,
    );
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Not confirmed'), findsOneWidget);

    await tap(tester, 'Knee-deep flood on Dapitan St near the market');
    expect(find.text('Part of a confirmed incident'), findsOneWidget);
    expect(find.textContaining('became incident INC-0141'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    await tap(tester, 'Smell of smoke near España Blvd');
    expect(find.textContaining('No one else reported this'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('R6: a new account starts empty', (tester) async {
    await pumpApp(tester);
    await tap(tester, 'Continue as resident');
    await tap(tester, 'Me');
    await tap(tester, 'My activity');
    expect(
      find.text('No SOS yet. If you send one, it will appear here.'),
      findsOneWidget,
    );
    await tap(tester, 'Reports');
    expect(
      find.text('No reports yet. Reports you send will appear here.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('R7, R8: alerts, reading one, forecast, offline copy', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, 'Continue as resident');
    expect(find.text('3'), findsOneWidget, reason: 'unread count on the tab');

    await tap(tester, 'Alerts');
    expect(find.text('Flooding on Dapitan St and España Blvd'), findsOneWidget);
    expect(
      find.text('Taal Volcano advisory: possible light ashfall'),
      findsOne,
    );

    // The last card sits below the fold; scroll the list up first.
    await tester.drag(
      find.text('Flooding on Dapitan St and España Blvd'),
      const Offset(0, -400),
    );
    await settle(tester);
    await tap(tester, 'Taal Volcano advisory: possible light ashfall');
    expect(find.text('What to do'), findsOneWidget);
    expect(find.textContaining('wear a face mask'), findsOneWidget);
    await back(tester);
    await tester.drag(
      find.text('Taal Volcano advisory: possible light ashfall'),
      const Offset(0, 400),
    );
    await settle(tester);

    await tap(tester, 'Flooding on Dapitan St and España Blvd');
    expect(find.text('Barangay 412, Barangay 490'), findsOneWidget);
    await back(tester);
    expect(container.read(alertFeedProvider).value!.unread, 2);
    expect(find.text('2'), findsOneWidget);

    await tap(tester, 'Forecast');
    expect(find.text('Next 72 hours'), findsOneWidget);
    expect(find.text('High'), findsOneWidget, reason: 'flood in Barangay 412');
    expect(
      find.text('Move appliances and important papers to a higher place.'),
      findsOneWidget,
    );

    backend.setSignal(SignalState.smsOnly);
    await settle(tester);
    expect(find.textContaining('Offline. Last updated 3:42'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('R9 to R11: add, check, remove, withdraw, consent again', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, 'Continue as resident');
    await tap(tester, 'Me');
    await tap(tester, 'Vulnerability profile');
    expect(find.text('Lolo Andres'), findsOneWidget);
    expect(find.text('Uses a wheelchair'), findsOneWidget);

    await tap(tester, 'Add household member');
    await tap(tester, 'Save');
    expect(find.text('Enter a name or description.'), findsOneWidget);
    expect(find.text('Choose at least one.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Tita Rosa');
    await tap(tester, 'Pregnant');
    await tap(tester, 'Save');
    expect(find.text('Tita Rosa'), findsOneWidget);
    expect(find.text('Saved.'), findsOneWidget);
    await clearMessages(tester);

    await tester.tap(find.byTooltip('Remove Tita Rosa'));
    await settle(tester);
    await tap(tester, 'Remove');
    expect(find.text('Tita Rosa'), findsNothing);
    await clearMessages(tester);

    await tap(tester, 'Withdraw consent');
    await tap(tester, 'Withdraw and delete');
    expect(find.text('Lolo Andres'), findsNothing);
    await clearMessages(tester);

    await tap(tester, 'Review and give consent');
    expect(find.text('Data privacy consent'), findsOneWidget);
    final agree = find.widgetWithText(FilledButton, 'I agree');
    expect(tester.widget<FilledButton>(agree).onPressed, isNull);
    await tap(tester, 'I agree to let MDRRMD keep this information');
    await tap(tester, 'I agree');
    expect(find.text('Consent given Sep 30, 2026'), findsOneWidget);
    expect(
      find.text('Add household members who may need priority rescue.'),
      findsOneWidget,
    );

    backend.setSignal(SignalState.smsOnly);
    await settle(tester);
    expect(find.text("You're offline. Connect to make changes."), findsOne);
    final add = find.widgetWithText(FilledButton, 'Add household member');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    await finish(tester);
  });

  testWidgets('R5: choose the spot by search, and by barangay offline', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, 'Continue as resident');
    await tap(tester, 'Report');
    await tap(tester, 'Change');
    expect(find.text('Choose location'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search barangay'),
      'binondo',
    );
    await settle(tester);
    await tap(tester, 'Barangay 287');
    expect(find.text('Near Barangay 287, Binondo'), findsOneWidget);
    await tap(tester, 'Use this location');

    expect(find.text('Barangay 287, Binondo'), findsOneWidget);
    expect(find.text('Chosen by you'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Fallen tree');
    await tap(tester, 'Send report');
    final sent = container.read(myReportsProvider).value!.single;
    expect(sent.barangay, 'Barangay 287');
    expect(sent.accuracyMeters, isNull);

    await tap(tester, 'Send another report');
    backend.setSignal(SignalState.noSignal);
    await settle(tester);
    await tap(tester, 'Change');
    expect(find.text('No map while offline'), findsOneWidget);
    await tap(tester, 'Barangay');
    await tester.enterText(
      find.widgetWithText(TextField, 'Search barangays'),
      'malate',
    );
    await settle(tester);
    await tap(tester, 'Barangay 700');
    await tap(tester, 'Use this location');
    expect(find.text('Barangay 700, Malate'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('F7: history with week filters and a report still waiting', (
    tester,
  ) async {
    await pumpApp(tester, history: true);
    await tap(tester, 'Continue as rescue personnel');
    await tap(tester, 'History');
    expect(find.text('Assignment history'), findsOneWidget);
    expect(find.text('INC-0139 · Flood'), findsOneWidget);
    expect(find.text('INC-0131 · Medical'), findsOneWidget);

    await tap(tester, 'This week');
    expect(find.text('INC-0139 · Flood'), findsOneWidget);
    expect(find.text('INC-0131 · Medical'), findsNothing);

    await tap(tester, 'Last week');
    expect(find.text('INC-0139 · Flood'), findsNothing);
    expect(find.text('INC-0131 · Medical'), findsOneWidget);
    expect(find.text('INC-0124 · Flood'), findsOneWidget);

    // A job finished offline shows its report as saved on the phone.
    backend.setSignal(SignalState.noSignal);
    backend.sendOfferNow();
    await container.read(responderRepositoryProvider).accept('INC-0147');
    await container.read(responderRepositoryProvider).arrive();
    await container
        .read(responderRepositoryProvider)
        .complete(outcome: RescueOutcome.rescued, personsAssisted: 3);
    await settle(tester);
    // The offer opened F2 over the tabs; go back to History.
    container.read(routerProvider).go(Routes.history);
    await settle(tester);
    await tap(tester, 'All');
    expect(find.text('INC-0147 · Flood'), findsOneWidget);
    expect(find.text('Saved on phone'), findsOneWidget);
    await finish(tester);
  });
}
