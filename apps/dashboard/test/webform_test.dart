import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_dashboard/src/webform/browser/browser.dart';
import 'package:sagip_dashboard/src/webform/web_app.dart';
import 'package:sagip_dashboard/src/webform/web_providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// pumpAndSettle with a short limit, so an endless animation fails fast.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

/// The browser's geolocation: a fix, or a refusal.
class FakeLocation implements BrowserLocation {
  GeoPoint? point;
  double accuracy = 25;
  BrowserLocationFailure failure = BrowserLocationFailure.denied;

  @override
  Future<({GeoPoint point, double accuracyMeters})> current() async {
    final p = point;
    if (p == null) throw BrowserLocationException(failure);
    return (point: p, accuracyMeters: accuracy);
  }
}

class FakeConnection implements BrowserConnection {
  final _changes = StreamController<bool>.broadcast();
  var online = true;

  void set(bool next) {
    online = next;
    _changes.add(next);
  }

  @override
  Stream<bool> watch() {
    late final StreamController<bool> controller;
    StreamSubscription<bool>? sub;
    controller = StreamController<bool>(
      onListen: () {
        controller.add(online);
        sub = _changes.stream.listen(controller.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}

void main() {
  const sampaloc = GeoPoint(14.6091, 120.9925);
  late MockMobileBackend backend;
  late MemoryDraftStore drafts;
  late FakeLocation location;
  late FakeConnection connection;
  final containers = <ProviderContainer>[];

  ProviderContainer newContainer({
    WebFormConfig config = const WebFormConfig(),
    ClientConfig server = const ClientConfig(),
  }) {
    final c = ProviderContainer(
      overrides: [
        webClientConfigRepositoryProvider.overrideWithValue(
          StaticClientConfigRepository(server),
        ),
        ...webMockOverrides(backend, demoTools: false),
        webMapTilesProvider.overrideWithValue(false),
        draftStoreProvider.overrideWithValue(drafts),
        browserLocationProvider.overrideWithValue(location),
        browserConnectionProvider.overrideWithValue(connection),
        webConfigProvider.overrideWithValue(config),
      ],
    );
    containers.add(c);
    return c;
  }

  setUp(() {
    backend = MockMobileBackend(
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
    );
    drafts = MemoryDraftStore();
    location = FakeLocation();
    connection = FakeConnection();
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    backend.dispose();
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    WebFormConfig config = const WebFormConfig(),
    ClientConfig server = const ClientConfig(),
  }) async {
    tester.view.physicalSize = const Size(800, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = newContainer(config: config, server: server);
    // Kept alive so tests can read the account's reports on any page.
    container.listen(myWebReportsProvider, (_, _) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SagipWebFormApp(),
      ),
    );
    await settle(tester);
    return container;
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('web-phone')),
      '917 000 4821',
    );
    await tester.tap(find.text('Send code'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('web-code')),
      MockMobileBackend.demoCode,
    );
    await settle(tester);
  }

  Future<void> chooseBarangay(WidgetTester tester, String name) async {
    await tester.tap(find.text('Choose a barangay').first);
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('barangay-search')),
      name.split(' ').last,
    );
    await tester.pump();
    await tester.tap(find.text(name).last);
    await settle(tester);
  }

  FilledButton sendButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('W1: number checks, a wrong code, then the code opens W2', (
    tester,
  ) async {
    await pumpApp(
      tester,
      config: const WebFormConfig(hotline: '(02) 8527 0000'),
    );
    expect(find.text('Report a hazard to MDRRMD'), findsOneWidget);
    expect(
      find.text(
        'SOS is only available in the S.A.G.I.P. app. In an emergency, '
        'call MDRRMD at (02) 8527 0000.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('web-phone')), '123');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(
      find.text('Enter a Philippine mobile number, like 917 123 4567.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('web-phone')),
      '918 555 0101',
    );
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(
      find.text('This number has no account yet. Create an account first.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('web-phone')),
      '0917 000 4821',
    );
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(
      find.text('We sent a 6-digit code to +63 917 000 4821.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('web-code')), '000000');
    await settle(tester);
    expect(
      find.text(
        'That code is not right. Check the text message and try again.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('web-code')),
      MockMobileBackend.demoCode,
    );
    await settle(tester);
    expect(find.text('Report a hazard'), findsOneWidget);
    expect(find.text('Signed in as Maria Dela Cruz'), findsOneWidget);
    // The notice follows the resident onto W2.
    expect(find.textContaining('SOS is only available'), findsOneWidget);
  });

  testWidgets('W1: the notice shows the hotline set on A3', (tester) async {
    await pumpApp(tester, server: const ClientConfig(hotline: '911'));
    expect(
      find.text(
        'SOS is only available in the S.A.G.I.P. app. In an emergency, '
        'call MDRRMD at 911.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W1: a new resident creates an account on the web form', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('New to S.A.G.I.P.? Create an account'));
    await settle(tester);
    expect(find.text('Create an account'), findsOneWidget);

    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Choose your barangay.'), findsOneWidget);
    expect(find.text('Agree to the terms to continue.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('web-name')), 'Leo Cruz');
    await tester.enterText(
      find.byKey(const ValueKey('web-phone')),
      '918 555 0101',
    );
    await tester.tap(find.byKey(const ValueKey('web-barangay')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('barangay-search')),
      '461',
    );
    await tester.pump();
    await tester.tap(find.text('Barangay 461'));
    await settle(tester);
    expect(find.text('Barangay 461, Sampaloc'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('web-terms')));
    await tester.pump();

    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('web-code')),
      MockMobileBackend.demoCode,
    );
    await settle(tester);
    expect(find.text('Signed in as Leo Cruz'), findsOneWidget);
    expect(find.text('5 of 5 reports left this hour'), findsOneWidget);
  });

  testWidgets('W1: with registration off, the form only signs in', (
    tester,
  ) async {
    await pumpApp(
      tester,
      config: const WebFormConfig(allowRegistration: false),
    );
    expect(find.text('New to S.A.G.I.P.? Create an account'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('web-phone')),
      '918 555 0101',
    );
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(
      find.text(
        'This number has no account yet. Create one in the S.A.G.I.P. app.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W2 and W3: checks, the browser location, send, and the list', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await signIn(tester);
    expect(find.text('5 of 5 reports left this hour'), findsOneWidget);
    expect(find.text('No location chosen yet.'), findsOneWidget);

    // Nothing written yet.
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(find.text('Describe what you see.'), findsOneWidget);

    // A description but no location: nothing is sent.
    await tester.enterText(
      find.byKey(const ValueKey('web-description')),
      'Water is knee-deep on Dapitan St and rising.',
    );
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(
      find.text(
        'Choose where it is: use your location, move the map, or choose a '
        'barangay.',
      ),
      findsOneWidget,
    );
    expect(container.read(myWebReportsProvider).value, isEmpty);

    // The browser refuses to share the location: a pin or barangay is needed.
    await tester.tap(find.text('Use my location'));
    await settle(tester);
    expect(
      find.textContaining('Your browser did not share your location.'),
      findsOneWidget,
    );

    location.point = sampaloc;
    await tester.tap(find.text('Use my location'));
    await settle(tester);
    expect(find.text('Near Barangay 412, Sampaloc'), findsOneWidget);
    expect(find.text('From your browser, accurate to 25 m'), findsOneWidget);
    expect(
      find.textContaining('Your browser did not share your location.'),
      findsNothing,
    );
    expect(find.textContaining('Choose where it is'), findsNothing);

    await tester.tap(find.text('Flood'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await settle(tester);

    // W3: the reference, the reminder, and the list.
    expect(find.text('Report received'), findsOneWidget);
    expect(find.text('Reference rep-400'), findsOneWidget);
    expect(
      find.textContaining('A single report is never confirmed on its own.'),
      findsOneWidget,
    );
    expect(
      find.text('Water is knee-deep on Dapitan St and rising.'),
      findsOneWidget,
    );
    expect(find.text('Sent from the web form'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);

    final sent = container.read(myWebReportsProvider).requireValue.single;
    expect(sent.source, ReportChannel.webForm);
    expect(sent.type, IncidentType.flood);
    expect(sent.accuracyMeters, 25);
    expect(sent.delivery, DeliveryState.delivered);
    // Nothing of the report stays in the browser once it is sent.
    expect(drafts.read('sagip.webform.draft.res-001'), isNull);

    await tester.tap(find.text('Send another report'));
    await settle(tester);
    expect(find.text('4 of 5 reports left this hour'), findsOneWidget);
    expect(find.text('No location chosen yet.'), findsOneWidget);
    expect(
      find.text('Water is knee-deep on Dapitan St and rising.'),
      findsNothing,
    );
  });

  testWidgets('W2: a barangay, the map pin, and a place outside Manila', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await signIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('web-description')),
      'Fallen post blocking the road',
    );

    await chooseBarangay(tester, 'Barangay 700');
    expect(find.text('Barangay 700, Malate'), findsOneWidget);
    expect(find.text('Centre of the barangay you chose'), findsOneWidget);

    // Moving the map moves the spot under the pin.
    await tester.drag(
      find.byKey(const ValueKey('web-map')),
      const Offset(30, 0),
    );
    await settle(tester);
    expect(find.text('Chosen on the map'), findsOneWidget);

    // A browser location outside the city is refused before it is sent.
    location.point = const GeoPoint(14.40, 121.20);
    await tester.tap(find.text('Use my location'));
    await settle(tester);
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(
      find.text(
        'This location is outside Manila City. S.A.G.I.P. covers Manila only.',
      ),
      findsOneWidget,
    );
    expect(container.read(myWebReportsProvider).value, isEmpty);

    // Choosing a place in Manila clears the message and sends.
    await chooseBarangay(tester, 'Barangay 700');
    expect(find.textContaining('outside Manila City'), findsNothing);
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(find.text('Report received'), findsOneWidget);
    final sent = container.read(myWebReportsProvider).requireValue.single;
    expect(sent.barangay, 'Barangay 700');
    expect(sent.accuracyMeters, isNull, reason: 'a chosen place has none');
  });

  testWidgets('W2: offline and a lost connection keep the draft', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await signIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('web-description')),
      'Smoke from a warehouse',
    );
    await chooseBarangay(tester, 'Barangay 649');

    // The browser goes offline: said twice, and Send is off.
    connection.set(false);
    await settle(tester);
    expect(find.text("You're offline."), findsOneWidget);
    expect(
      find.text(
        'Connection lost. Your report is kept on this page. Send it when '
        "you're back online.",
      ),
      findsOneWidget,
    );
    expect(sendButton(tester).onPressed, isNull);

    // A reload: the draft comes back from the browser's store.
    container.dispose();
    containers.remove(container);
    await tester.pumpWidget(const SizedBox());
    connection.online = true;
    final again = await pumpApp(tester);
    expect(find.text('Smoke from a warehouse'), findsOneWidget);
    expect(find.text('Barangay 649, Port Area'), findsOneWidget);

    // The browser says online but the server cannot be reached.
    backend.setSignal(SignalState.noSignal);
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(find.textContaining('Connection lost.'), findsOneWidget);
    expect(find.text('Report received'), findsNothing);
    expect(again.read(myWebReportsProvider).value, isEmpty);

    backend.setSignal(SignalState.internet);
    await tester.tap(find.text('Send report'));
    await settle(tester);
    expect(find.text('Report received'), findsOneWidget);
    expect(again.read(myWebReportsProvider).requireValue, hasLength(1));
  });

  testWidgets('W2: the hourly limit and a suspended account', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < MockMobileBackend.reportLimit; i++) {
        await backend.submitWebReport(
          clientId: newClientId(),
          capturedAt: DateTime.now(),
          description: 'Flood $i',
          location: sampaloc,
        );
      }
    });
    await settle(tester);
    expect(
      find.textContaining("You've sent 5 reports in the last hour."),
      findsOneWidget,
    );
    expect(sendButton(tester).onPressed, isNull);

    backend.setResidentSuspended('res-001', suspended: true);
    await settle(tester);
    expect(
      find.text(
        'This account cannot send reports right now. In an emergency, call '
        'MDRRMD.',
      ),
      findsOneWidget,
    );
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('W3: no reports yet, and signing out clears the draft', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('web-description')),
      'Half-written report',
    );
    expect(drafts.read('sagip.webform.draft.res-001'), isNotNull);

    await tester.tap(find.text('My reports'));
    await settle(tester);
    expect(find.text('Your recent reports'), findsOneWidget);
    expect(find.text('No reports yet.'), findsOneWidget);
    expect(find.text('Report received'), findsNothing);

    await tester.tap(find.text('Sign out'));
    await settle(tester);
    expect(find.text('Report a hazard to MDRRMD'), findsOneWidget);
    expect(drafts.read('sagip.webform.draft.res-001'), isNull);
  });
}
