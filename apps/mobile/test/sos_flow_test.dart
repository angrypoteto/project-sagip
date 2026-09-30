import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/features/sos/sos_status_page.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// pumpAndSettle with a short limit, so an endless animation fails fast.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

void main() {
  final now = DateTime(2026, 9, 30, 15, 42);
  late MockMobileBackend backend;
  late ProviderContainer container;

  setUp(() {
    backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: const MockSosTiming(
        send: Duration(milliseconds: 500),
        sms: Duration(seconds: 1),
        relay: Duration(seconds: 1),
        verify: Duration(seconds: 2),
        assign: Duration(seconds: 2),
        depart: Duration(seconds: 2),
        arrive: Duration(seconds: 4),
        resolve: Duration(seconds: 4),
      ),
    );
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        clockProvider.overrideWith((ref) => Stream.value(now)),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
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

  Future<void> signInAsResident(WidgetTester tester) async {
    await tester.tap(find.text('Continue as resident'));
    await settle(tester);
  }

  /// Finds [text] on the SOS status screen only (Home can still be on
  /// screen during the page transition).
  Finder onStatus(String text) => find.descendant(
    of: find.byType(SosStatusPage),
    matching: find.text(text),
  );

  /// Holds the SOS button for its full two seconds.
  Future<void> holdSos(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Runs every simulated step to the end and clears timers, so the test
  /// ends with nothing pending.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 20));
    backend.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('the role picks the shell', (tester) async {
    await pumpApp(tester);
    expect(find.text('Sign in'), findsOneWidget);

    await signInAsResident(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);
    expect(find.text('Hold for 2 seconds to send'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);

    await tester.tap(find.text('Me'));
    await settle(tester);
    await tester.tap(find.text('Sign out'));
    await settle(tester);

    await tester.tap(find.text('Continue as rescue personnel'));
    await settle(tester);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Responder home comes next'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('online SOS: hold, delivered, verified, responder assigned', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);

    await holdSos(tester);
    // R2 opens straight away with the local record.
    expect(find.text('Your SOS'), findsOneWidget);
    expect(find.text('Saved on phone'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Waiting for verification'), findsOneWidget);
    expect(find.text('Received by MDRRMD'), findsOneWidget);
    expect(find.textContaining('was delivered'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Verified by MDRRMD'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Responder assigned'), findsOneWidget);
    expect(find.text('9 min'), findsOneWidget);
    expect(find.text('R-03 · Rescue boat'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('offline SOS goes out by SMS and is delivered on reconnect', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    backend.setSignal(SignalState.smsOnly);
    await settle(tester);
    expect(
      find.text('Offline. Your SOS will be saved and sent by SMS.'),
      findsOneWidget,
    );

    await holdSos(tester);
    expect(onStatus('Saved on your phone'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(onStatus('Sent by SMS'), findsWidgets);
    expect(
      onStatus("We'll keep trying and tell you when it's delivered."),
      findsOneWidget,
    );
    expect(find.text('Offline · 1 waiting to send'), findsOneWidget);

    // The banner opens the offline queue (S6).
    await tester.tap(find.text('Offline · 1 waiting to send'));
    await settle(tester);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('SOS'), findsWidgets);
    await tester.tapAt(const Offset(20, 20)); // close the sheet
    await settle(tester);

    backend.setSignal(SignalState.internet);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.textContaining('Your SOS from 3:42'), findsOneWidget);
    expect(onStatus('Received by MDRRMD'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('details can be added after the SOS is sent', (tester) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.scrollUntilVisible(find.text('Add details'), 200);
    await tester.tap(find.text('Add details'));
    await settle(tester);
    await tester.tap(find.text('Flood'));
    await tester.tap(find.byTooltip('More people'));
    await tester.tap(find.byTooltip('More people'));
    await tester.pump();
    expect(find.text('2 people'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save details'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save details'));
    await settle(tester);

    final sos = container.read(mySosProvider).value!.single;
    expect(sos.details.type, IncidentType.flood);
    expect(sos.details.peopleCount, 2);
    expect(onStatus('Edit details'), findsOneWidget);
    // Queued behind the "delivered" notice, which stays up for 4 seconds.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Details added'), findsOneWidget);
    await finish(tester);
  });
}
