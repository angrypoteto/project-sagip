import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The real app's phone side (part 6) behind the real screens: the outbox
/// repositories, the saved settings, and the honest offline wording. The
/// server is a fake; sign-in and GPS still come from the sample backend.
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

class _Server implements MobileServer {
  var reachable = true;
  final sent = <String>[];
  final sos = StreamController<List<SosRequest>>.broadcast();

  @override
  Future<String> submitSos(SosRequest s) async {
    if (!reachable) throw const ActionRejected(ActionRejection.offline);
    sent.add(s.clientId);
    return 'INC-0301';
  }

  @override
  Stream<List<SosRequest>> watchMySos() => sos.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 9, 30, 15, 42);

  testWidgets('an offline SOS waits in the outbox, then is delivered', (
    tester,
  ) async {
    final backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
    );
    final server = _Server();
    final composer = MockSmsComposer();
    final store = MemoryLocalStore();
    await store.write('settings:welcome-seen', 'yes');
    String? account() => backend.currentUser?.id;
    final engine = SyncEngine(
      store: store,
      sender: ServerSender(server),
      online: backend.watchSignal().map((s) => s == SignalState.internet),
      account: account,
      clock: () => now,
      retryDelay: (_) => const Duration(milliseconds: 10),
    );
    backend.watchUser().listen((_) => engine.accountChanged());

    final container = ProviderContainer(
      overrides: [
        // The sample backend for sign-in, GPS, and signal; the outbox for
        // the SOS.
        authRepositoryProvider.overrideWithValue(
          MockMobileAuthRepository(backend),
        ),
        residentAccountRepositoryProvider.overrideWithValue(
          MockResidentAccountRepository(backend),
        ),
        permissionServiceProvider.overrideWithValue(
          MockPermissionService(backend),
        ),
        hazardReportRepositoryProvider.overrideWithValue(
          MockHazardReportRepository(backend),
        ),
        responderRepositoryProvider.overrideWithValue(
          MockResponderRepository(backend),
        ),
        signalMonitorProvider.overrideWithValue(MockSignalMonitor(backend)),
        locationServiceProvider.overrideWithValue(MockLocationService(backend)),
        residentRepositoryProvider.overrideWithValue(
          MockMobileResidentRepository(backend),
        ),
        weatherRepositoryProvider.overrideWithValue(
          MockMobileWeatherRepository(backend),
        ),
        alertRepositoryProvider.overrideWithValue(MockAlertRepository(backend)),
        vulnerabilityRepositoryProvider.overrideWithValue(
          MockVulnerabilityRepository(backend),
        ),
        mapTilesEnabledProvider.overrideWithValue(false),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        localStoreProvider.overrideWithValue(store),
        capabilitiesProvider.overrideWithValue(DeviceCapabilities.queueOnly),
        sosRepositoryProvider.overrideWithValue(
          OutboxSosRepository(
            engine: engine,
            server: server,
            store: store,
            account: account,
            clock: () => now,
          ),
        ),
        offlineQueueProvider.overrideWithValue(
          OutboxOfflineQueue(engine, account),
        ),
        // A gateway is known, but this phone may not text by itself.
        smsGatewayProvider.overrideWithValue('09170000001'),
        smsComposerProvider.overrideWithValue(composer),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await engine.dispose();
      backend.dispose();
    });
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

    // The welcome steps were seen on this phone before.
    expect(
      find.text("Enter your mobile number. We'll text you a code."),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '917 000 4821');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), MockMobileBackend.demoCode);
    await settle(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);

    // No internet: the banner does not promise SMS before Phase 5.
    backend.setSignal(SignalState.smsOnly);
    server.reachable = false;
    server.sos.addError(const ActionRejected(ActionRejection.offline));
    await settle(tester);
    expect(
      find.text(
        "Offline. SOS and reports are saved and sent when you're back online.",
      ),
      findsOneWidget,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await gesture.up();
    await tester.pump();
    await settle(tester);
    expect(find.text('Offline · 1 waiting to send'), findsOneWidget);
    expect(store.outbox.single.action, OutboxAction.sos);
    expect(server.sent, isEmpty);

    // S6 offers to text it from the messages app, ready to send.
    await tester.tap(find.text('Offline · 1 waiting to send'));
    await settle(tester);
    await tester.ensureVisible(find.text('Text it myself'));
    await settle(tester);
    await tester.tap(find.text('Text it myself'));
    await settle(tester);
    final (number, text) = composer.composed.single;
    expect(number, '09170000001');
    expect(
      text,
      SosSms.encode(SosRequest.fromJson(store.outbox.single.payload)),
    );
    expect(text, startsWith('SAGIP1 SOS '));
    await tester.tapAt(const Offset(195, 40)); // closes the sheet
    await settle(tester);

    // Back online: sent, and the SOS shows as delivered.
    server.reachable = true;
    backend.setSignal(SignalState.internet);
    await settle(tester);
    expect(server.sent, hasLength(1));
    expect(
      container.read(mySosProvider).value!.single.delivery,
      DeliveryState.delivered,
    );
    expect(find.textContaining('was delivered'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the theme choice is saved on the phone', (tester) async {
    final store = MemoryLocalStore();
    await store.write('settings:theme', 'dark');
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    container.read(themeModeProvider.notifier).set(ThemeMode.light);
    expect(store.read('settings:theme'), 'light');
    expect(container.read(welcomeSeenProvider), isFalse);
    container.read(welcomeSeenProvider.notifier).markSeen();
    expect(store.read('settings:welcome-seen'), 'yes');
  });
}
