import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:io';

import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/app_version.dart';
import 'package:sagip_mobile/src/features/safe_places/safe_places_page.dart';
import 'package:sagip_mobile/src/features/sos/sos_status_page.dart';
import 'package:sagip_mobile/src/features/sos/track_page.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// These tests start at sign-in: the welcome steps (S2) count as seen.
class WelcomeDone extends WelcomeSeen {
  @override
  bool build() => true;
}

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
        offerAfter: Duration(seconds: 3),
        mapSave: Duration(seconds: 2),
        drive: Duration(seconds: 6),
      ),
    );
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        mapTilesEnabledProvider.overrideWithValue(false),
        welcomeSeenProvider.overrideWith(WelcomeDone.new),
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

  /// Signs in the way a resident does: mobile number, then the code.
  Future<void> signInAsResident(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '917 000 4821');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), MockMobileBackend.demoCode);
    await settle(tester);
  }

  /// Signs in through the MDRRMD personnel form.
  Future<void> signInAsStaff(WidgetTester tester) async {
    await tester.ensureVisible(find.text('MDRRMD personnel sign in'));
    await tester.tap(find.text('MDRRMD personnel sign in'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'r03@sagip.test');
    await tester.enterText(find.byType(TextField).at(1), MockSeed.demoPassword);
    await tester.tap(find.text('Sign in').last);
    await settle(tester);
  }

  /// Finds [text] on the SOS status screen only (Home can still be on
  /// screen during the page transition).
  Finder onStatus(String text) => find.descendant(
    of: find.byType(SosStatusPage),
    matching: find.text(text),
  );

  /// Holds the SOS button for its full two seconds. The "What's
  /// happening?" question that follows is skipped unless [keepQuestion].
  Future<void> holdSos(WidgetTester tester, {bool keepQuestion = false}) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final skip = find.byKey(const ValueKey('whats-happening-skip'));
    if (!keepQuestion && skip.evaluate().isNotEmpty) {
      // Closed without moving the clock, so the steps each test times
      // (delivered, verified, assigned) come when they always did.
      await tester.tap(skip);
      await tester.pump();
    }
  }

  /// Runs every simulated step to the end and clears timers, so the test
  /// ends with nothing pending.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 20));
    backend.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  test('the app knows its own build number (pubspec.yaml)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final build = RegExp(
      r'^version: [0-9.]+\+([0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appBuild, int.parse(build!));
  });

  testWidgets('too old an app asks to be updated, but SOS still works', (
    tester,
  ) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        mapTilesEnabledProvider.overrideWithValue(false),
        welcomeSeenProvider.overrideWith(WelcomeDone.new),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        clientConfigRepositoryProvider.overrideWithValue(
          const StaticClientConfigRepository(
            ClientConfig(minBuild: appBuild + 1),
          ),
        ),
      ],
    );
    await pumpApp(tester);
    expect(find.text('Update S.A.G.I.P.'), findsOneWidget);
    // Signed out: only the update and the hotline.
    expect(find.byType(SosButton), findsNothing);
    expect(find.text('Call MDRRMD'), findsOneWidget);

    // A signed-in resident keeps SOS on the same screen.
    await container
        .read(residentAccountRepositoryProvider)
        .verifyCode(phone: '917 000 4821', code: MockMobileBackend.demoCode);
    await settle(tester);
    expect(find.text('Update S.A.G.I.P.'), findsOneWidget);
    expect(find.byType(SosButton), findsOneWidget);
    await holdSos(tester);
    await settle(tester);
    // The SOS went, and while it is open nothing is blocked.
    expect(find.byType(SosStatusPage), findsOneWidget);
    expect(container.read(updateRequiredProvider), isFalse);
    await finish(tester);
  });

  testWidgets('the role picks the shell', (tester) async {
    await pumpApp(tester);
    expect(find.text('Sign in'), findsOneWidget);

    await signInAsResident(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);
    expect(find.text('Hold for 2 seconds to send'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);

    // Android Back on another tab returns to Home instead of closing.
    await tester.tap(find.text('Report'));
    await settle(tester);
    expect(find.text('Report a hazard'), findsWidgets);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);

    await tester.tap(find.text('Me'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sign out'));
    await settle(tester);

    await signInAsStaff(tester);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('R-03'), findsOneWidget);
    expect(find.text('No assignment. Stay available.'), findsOneWidget);
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
    // Sent at once, so no "was delivered" notice: the screen shows it.
    expect(find.textContaining('was delivered'), findsNothing);

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
    expect(find.text('Details added'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Cancel SOS: asked, taken back, asked again, closed by MDRRMD', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester);
    await tester.pump(const Duration(milliseconds: 600));

    Future<void> ask(String reason) async {
      await tester.scrollUntilVisible(find.text('Cancel SOS'), 200);
      // A notice at the bottom ("delivered") may cover the last button.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await settle(tester);
      await tester.tap(find.text('Cancel SOS'));
      await settle(tester);
      expect(find.text('Cancel this SOS?'), findsOneWidget);
      // Nothing is sent until a reason is chosen.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Ask MDRRMD to cancel'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text(reason));
      await tester.pump();
      await tester.tap(find.text('Ask MDRRMD to cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await ask("I'm safe now");
    var sos = container.read(mySosProvider).value!.single;
    expect(sos.cancelReason, SosCancelReason.safeNow);
    expect(sos.isActive, isTrue, reason: 'MDRRMD closes it, not the resident');
    await tester.scrollUntilVisible(
      find.text('You asked to cancel this SOS'),
      -200,
    );
    expect(find.text('Cancel SOS'), findsNothing);

    await tester.ensureVisible(find.text('I still need help'));
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('I still need help'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    sos = container.read(mySosProvider).value!.single;
    expect(sos.cancelRequested, isFalse);
    expect(find.text('You asked to cancel this SOS'), findsNothing);

    // Messages on screen (this one, and "a unit is on the way") would
    // cover the button.
    await tester.pump(const Duration(seconds: 5));
    rootMessengerKey.currentState?.clearSnackBars();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await ask('I sent it by mistake');
    await tester.pump(const Duration(seconds: 3));
    sos = container.read(mySosProvider).value!.single;
    expect(sos.status, IncidentStatus.resolved);
    expect(sos.cancelled, isTrue);
    await tester.scrollUntilVisible(find.text('SOS cancelled'), -200);
    expect(onStatus('SOS cancelled'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tracking the responder once a unit is assigned', (tester) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Track responder'), findsNothing);

    // Verified after 2 s, R-03 assigned 2 s later.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Track responder'), 200);
    await tester.tap(find.text('Track responder'));
    await settle(tester);

    Finder onTrack(String text) =>
        find.descendant(of: find.byType(TrackPage), matching: find.text(text));
    expect(onTrack('R-03 · Rescue boat'), findsOneWidget);
    expect(onTrack('9 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Your location'), findsOneWidget);
    expect(find.bySemanticsLabel('Responder R-03'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(onTrack('Responder on the way'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(onTrack('Your responder has arrived.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('after the SOS, one tap says what is happening', (tester) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester, keepQuestion: true);
    // The SOS is already sent; the question sits over its status screen.
    expect(find.text('What is happening?'), findsOneWidget);
    expect(
      find.text(
        'Your SOS is already sent. One tap tells the responders what to bring.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('type-fire')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Details added'), findsOneWidget);
    expect(find.byKey(const ValueKey('whats-happening-skip')), findsNothing);
    final sos = container.read(mySosProvider).value!.first;
    expect(sos.details.type, IncidentType.fire);
    // Add details opens with the same large buttons, fire chosen.
    await tester.scrollUntilVisible(find.text('Edit details'), 200);
    await tester.ensureVisible(find.text('Edit details'));
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await settle(tester);
    await tester.tap(find.text('Edit details'));
    await settle(tester);
    expect(find.byKey(const ValueKey('type-flood')), findsOneWidget);
    final fire = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('type-fire')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(fire.properties.selected, isTrue);
    await finish(tester);
  });

  testWidgets('safe places: the SOS points to open ground away from a fire', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester, keepQuestion: true);
    await tester.tap(find.byKey(const ValueKey('type-fire')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final see = find.text('See safe places');
    await tester.scrollUntilVisible(see, 200);
    await settle(tester);
    expect(find.textContaining('Nearest: '), findsOneWidget);
    await tester.tap(see);
    await settle(tester);

    // Fire is already picked; the advice says help comes to them.
    expect(find.text('Safe places'), findsOneWidget);
    expect(
      find.textContaining('Help is coming to where you are'),
      findsOneWidget,
    );
    expect(find.textContaining('at least 300 m from the fire'), findsOneWidget);
    final tiles = find.byWidgetPredicate(
      (w) =>
          w is InkWell &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('safe-place-'),
    );
    await tester.scrollUntilVisible(tiles.last, 200);
    await settle(tester);
    expect(tiles, findsNWidgets(3));
    // Each is open ground, at least 300 m away.
    final sos = container.read(mySosProvider).value!.first;
    final near = await container.read(
      safePlacesNearProvider(safePlaceQuery(sos.location!, IncidentType.fire))
          .future,
    );
    for (final o in near) {
      expect(
        SafePlaceRules.kindsFor(IncidentType.fire),
        contains(o.place.kind),
      );
      expect(o.meters, greaterThanOrEqualTo(300));
    }
    // Picking another place shows how to get there.
    await tester.tap(tiles.at(1));
    await settle(tester);
    expect(
      find.textContaining('min on foot').evaluate().length +
          find.textContaining('No street route').evaluate().length,
      1,
    );
    // Medical: the nearest hospitals instead.
    await tester.drag(
      find
          .descendant(
            of: find.byType(SafePlacesPage),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, 3000),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('type-medical')));
    await settle(tester);
    expect(find.textContaining('nearest hospitals'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('rescue confirmations: said at once, kept on Alerts (FR6)', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await holdSos(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 2)); // verified
    expect(
      container.read(alertFeedProvider).value!.confirmations,
      isEmpty,
      reason: 'verification alone is not a rescue confirmation',
    );
    await tester.pump(const Duration(seconds: 2)); // R-03 assigned
    await tester.pump();

    // Said on whatever screen is open.
    const sent =
        'R-03 has been sent to your location. Stay where you are if it is '
        'safe.';
    expect(find.text(sent), findsOneWidget);
    var feed = container.read(alertFeedProvider).value!;
    expect(feed.confirmations.single.kind, RescueConfirmationKind.assigned);
    expect(feed.unread, 4, reason: 'three alerts and the confirmation');

    // And kept on the Alerts tab, above the public alerts.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('4'), findsOneWidget, reason: 'the count on the tab');
    await tester.tap(find.text('Alerts'));
    await settle(tester);
    expect(find.text('About your SOS'), findsOneWidget);
    expect(find.text('Unit assigned'), findsOneWidget);
    expect(find.text('A rescue team is coming'), findsOneWidget);
    expect(find.text('SOS ${feed.confirmations.single.incidentId}'), findsOne);

    // Opening it marks it read and shows that SOS (R2).
    await tester.tap(find.text('A rescue team is coming'));
    await settle(tester);
    expect(find.text('Your SOS'), findsOneWidget);
    feed = container.read(alertFeedProvider).value!;
    expect(feed.confirmations.single.read, isTrue);
    expect(feed.unread, 3);

    // Arrival and closing follow.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    feed = container.read(alertFeedProvider).value!;
    expect(
      [for (final c in feed.confirmations) c.kind],
      [
        RescueConfirmationKind.resolved,
        RescueConfirmationKind.onScene,
        RescueConfirmationKind.assigned,
      ],
    );
    expect(feed.unread, 5);
    await finish(tester);
  });

  testWidgets('reporting a hazard: checks, online, and offline', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResident(tester);
    await tester.tap(find.text('Report'));
    await settle(tester);
    expect(
      find.text('MDRRMD checks reports against others nearby before acting.'),
      findsOneWidget,
    );

    Future<void> tapSend() async {
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pump();
    }

    await tapSend();
    expect(find.text('Describe what you see.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Water is knee-deep on Dapitan St',
    );
    await tester.tap(find.text('Flood'));
    await tapSend();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Report sent'), findsOneWidget);
    expect(find.textContaining('was delivered'), findsNothing);
    final sent = container.read(myReportsProvider).value!.single;
    expect(sent.type, IncidentType.flood);
    expect(sent.delivery, DeliveryState.delivered);

    await tester.tap(find.text('Send another report'));
    await settle(tester);
    backend.setSignal(SignalState.smsOnly);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Fallen wires on Lacson');
    await tapSend();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Saved on your phone'), findsOneWidget);
    expect(find.text("It will send when you're back online."), findsOneWidget);
    expect(find.text('Offline · 1 waiting to send'), findsOneWidget);
    await finish(tester);
  });

  Future<void> signInAsResponder(WidgetTester tester) => signInAsStaff(tester);

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  testWidgets(
    'responder: asked once to keep the app running in the background',
    (tester) async {
      final battery = MockBatteryOptimization();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          ...mockOverrides(backend, demoTools: false),
          mapTilesEnabledProvider.overrideWithValue(false),
          welcomeSeenProvider.overrideWith(WelcomeDone.new),
          clockProvider.overrideWith((ref) => Stream.value(now)),
          batteryOptimizationProvider.overrideWithValue(battery),
        ],
      );
      await pumpApp(tester);
      await signInAsResponder(tester);
      expect(find.text('Keep S.A.G.I.P. running'), findsOneWidget);
      await tapAndSettle(tester, 'Allow');
      expect(battery.requests, 1);
      expect(find.text('Keep S.A.G.I.P. running'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('responder: no battery prompt when the phone already allows it', (
    tester,
  ) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        mapTilesEnabledProvider.overrideWithValue(false),
        welcomeSeenProvider.overrideWith(WelcomeDone.new),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        batteryOptimizationProvider.overrideWithValue(
          MockBatteryOptimization(exempt: true),
        ),
      ],
    );
    await pumpApp(tester);
    await signInAsResponder(tester);
    expect(find.text('No assignment. Stay available.'), findsOneWidget);
    expect(find.text('Keep S.A.G.I.P. running'), findsNothing);
    await finish(tester);
  });

  testWidgets('responder: offer, accept, navigate, on scene, report', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResponder(tester);
    expect(find.text('No assignment. Stay available.'), findsOneWidget);

    // Nothing assigned yet, so On scene is refused with a reason.
    await tester.tap(find.bySemanticsLabel('On scene'));
    await tester.pump();
    expect(
      find.text("There's no assignment to be en route to or on scene at."),
      findsOneWidget,
    );

    // F2 opens by itself when the assignment arrives.
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(find.text('New assignment'), findsOneWidget);
    expect(find.text('Flood'), findsOneWidget);
    expect(
      (container.read(alertSoundProvider) as MockAlertSound).played,
      greaterThan(0),
      reason: 'the assignment tone plays',
    );
    expect(
      find.text('Vulnerable: Senior citizen, Person with disability'),
      findsOneWidget,
    );

    await tapAndSettle(tester, 'Accept and start');
    expect(find.text('Assignment INC-0147'), findsOneWidget);
    expect(find.textContaining('Saving map for offline use'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    await settle(tester);
    expect(find.text('Map saved for offline use'), findsOneWidget);

    await tapAndSettle(tester, 'Start navigation');
    // Dijkstra on the phone over the bundled road graph: the next turn and
    // the road route, not a straight line.
    expect(
      find.text('Road route from OpenStreetMap. Times are estimates.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r'^(Turn|Keep|Continue|Make|Go)')),
      findsOneWidget,
    );
    expect(find.text('Arrived'), findsNothing);
    // The next turn is said aloud once, with its distance.
    final speaker = container.read(speakerProvider) as MockSpeaker;
    expect(speaker.said, hasLength(1));
    expect(
      speaker.said.single,
      matches(
        RegExp(
          r'^In \d[\d.]* (meters|kilometers), (Turn|Keep|Continue|Make|Go)',
        ),
      ),
    );
    // A fire is confirmed elsewhere: the phone is told where, routes with
    // it, and says so.
    expect(find.byKey(const ValueKey('route-avoids-hazards')), findsNothing);
    backend.setRoadHazards(const [
      HazardZone(GeoPoint(14.62, 120.97), IncidentType.fire),
    ]);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('The route goes around 1 confirmed flood or fire when it can.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 7));
    await settle(tester);
    expect(find.text("You're at the scene"), findsOneWidget);
    expect(speaker.said.last, "You're at the scene");
    expect(
      speaker.said.where((t) => t == "You're at the scene"),
      hasLength(1),
      reason: 'said once',
    );
    // The responder can mute it; the choice is kept on the phone.
    await tester.tap(find.byKey(const ValueKey('voice-toggle')));
    await tester.pump();
    expect(container.read(voiceGuidanceProvider), isFalse);
    expect(find.textContaining('Head '), findsNothing);
    await tapAndSettle(tester, 'Arrived');

    expect(find.text('Is this a real emergency?'), findsOneWidget);
    await tapAndSettle(tester, 'Yes');
    await tapAndSettle(tester, 'Complete rescue');

    expect(find.text('Completion report'), findsOneWidget);
    await tapAndSettle(tester, 'Rescued');
    await tapAndSettle(tester, 'Submit report');
    expect(
      find.text('Report sent. The unit is available again.'),
      findsOneWidget,
    );
    expect(find.text('No assignment. Stay available.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    final report = backend.completionReports.single;
    expect(report.outcome, RescueOutcome.rescued);
    expect(report.personsAssisted, 3);
    expect(report.delivery, DeliveryState.delivered);
    await finish(tester);
  });

  testWidgets('responder offline: the report waits on the phone', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAsResponder(tester);
    backend.sendOfferNow();
    await tester.pump();
    await settle(tester);
    await tapAndSettle(tester, 'Accept and start');
    await tapAndSettle(tester, 'Mark on scene');

    backend.setSignal(SignalState.noSignal);
    await tester.pump();
    await tapAndSettle(tester, 'No');
    await tapAndSettle(tester, 'Complete rescue');
    expect(find.text('Say why it is not a real emergency.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'No one at the address');
    await tapAndSettle(tester, 'Complete rescue');

    // F5 said it was not real, so False report is already chosen.
    await tapAndSettle(tester, 'Submit report');
    expect(
      find.text(
        "Report saved on your phone. It will send when you're back online.",
      ),
      findsOneWidget,
    );
    final waiting = container.read(pendingQueueProvider).value!;
    expect(waiting.map((r) => r.kind), contains(QueuedKind.completionReport));
    expect(backend.completionReports.single.outcome, RescueOutcome.falseReport);

    backend.setSignal(SignalState.internet);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(backend.completionReports.single.delivery, DeliveryState.delivered);
    await finish(tester);
  });
}
