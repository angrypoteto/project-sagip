import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

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
  final now = DateTime(2026, 9, 30, 15, 42);
  late MockMobileBackend backend;
  late ProviderContainer container;

  ProviderContainer make({bool welcomeDone = true, ClientConfig? config}) =>
      ProviderContainer(
        overrides: [
          ...mockOverrides(backend),
          mapTilesEnabledProvider.overrideWithValue(false),
          clockProvider.overrideWith((ref) => Stream.value(now)),
          if (welcomeDone) welcomeSeenProvider.overrideWith(WelcomeDone.new),
          if (config != null)
            clientConfigRepositoryProvider.overrideWithValue(
              StaticClientConfigRepository(config),
            ),
        ],
      );

  setUp(() {
    backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
    );
  });

  tearDown(() {
    container.dispose();
    backend.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    bool welcomeDone = true,
    ClientConfig? config,
  }) async {
    container = make(welcomeDone: welcomeDone, config: config);
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

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('first run: welcome steps, then sign-in by code', (tester) async {
    await pumpApp(tester, welcomeDone: false);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Share your location'), findsOneWidget);

    await tap(tester, 'Allow');
    expect(find.text('Allowed'), findsOneWidget);
    await tap(tester, 'Next');
    await tap(tester, 'Skip');
    expect(find.text('Keep SOS working without internet'), findsOneWidget);
    await tap(tester, 'Allow');
    await tap(tester, 'Get started');

    expect(
      find.text("Enter your mobile number. We'll text you a code."),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '917 000 4821');
    await tap(tester, 'Send code');
    expect(
      find.text('We sent a 6-digit code to +63 917 000 4821.'),
      findsOneWidget,
    );
    expect(find.text('Resend code in 1:00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await settle(tester);
    expect(
      find.text(
        'That code is wrong or has expired. Check it or send a new one.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), MockMobileBackend.demoCode);
    await settle(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the hotline is the one set on A3, or says it is not set', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Call MDRRMD'));
    await settle(tester);
    expect(
      find.text('The MDRRMD hotline number has not been set yet.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await settle(tester);

    container.dispose();
    await tester.pumpWidget(const SizedBox());
    await pumpApp(
      tester,
      config: const ClientConfig(hotline: '(02) 8527-0000'),
    );
    await tester.tap(find.byTooltip('Call MDRRMD'));
    await settle(tester);
    expect(find.text('Call (02) 8527-0000 from any phone.'), findsOneWidget);
    // Tier 2 is promised only once a gateway number is known.
    expect(container.read(smsGatewayProvider), isEmpty);
  });

  testWidgets('sign-in explains a bad number and an unknown number', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField), '123');
    await tap(tester, 'Send code');
    expect(
      find.text('Enter a Philippine mobile number, like 917 123 4567.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '918 111 2222');
    await tap(tester, 'Send code');
    expect(find.text('This number has no account yet.'), findsOneWidget);

    backend.setSignal(SignalState.smsOnly);
    await settle(tester);
    expect(
      find.text(
        "You're offline. Signing in needs internet. In an emergency, call MDRRMD.",
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a new resident registers and lands on Home', (tester) async {
    await pumpApp(tester);
    await tap(tester, 'New to S.A.G.I.P.? Create an account');
    await tap(tester, 'Continue');
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Choose your barangay.'), findsOneWidget);
    expect(find.text('Agree to the terms to continue.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Ana Reyes');
    await tester.enterText(find.byType(TextField).at(1), '0918 555 0101');
    await tap(tester, 'Barangay');
    await tester.enterText(
      find.widgetWithText(TextField, 'Search barangays'),
      'malate',
    );
    await settle(tester);
    await tap(tester, 'Barangay 700');
    await tap(tester, 'I agree to the terms and the privacy notice');
    await tap(tester, 'Continue');

    await tester.enterText(find.byType(TextField), MockMobileBackend.demoCode);
    await settle(tester);
    expect(find.text('Hi, Ana'), findsOneWidget);
    expect(find.text('Barangay 700, Malate'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Me: theme, data deletion request, sign-out warning', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, 'Continue as resident');
    await tap(tester, 'Me');

    await tap(tester, 'Dark');
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await tap(tester, 'Request deletion of my data');
    await tap(tester, 'Send request');
    expect(
      find.text('Request sent. MDRRMD will contact you to confirm.'),
      findsOneWidget,
    );
    expect(backend.deletionRequests, ['res-001']);
    // Let the message go; it floats over the bottom of the screen.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    // Something waiting to send: signing out asks first.
    backend.setSignal(SignalState.smsOnly);
    await container.read(sosRepositoryProvider).send();
    await settle(tester);
    // Scroll to the very end so Sign out sits clear of the bottom bar.
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await settle(tester);
    await tap(tester, 'Sign out');
    expect(find.textContaining('waiting to send. They stay'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(container.read(currentUserProvider).value?.id, 'res-001');
    expect(find.text('Sign out'), findsOneWidget);
    await finish(tester);
  });
}
