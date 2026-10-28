// Frame times on R3 Track responder and F4 Navigate, on an emulator set up
// like a budget phone (Joshua, 2026-10-28: testers' phones lagged, his own
// has 24 GB of RAM). Runs the app on sample data with real map tiles, a
// responder moving every second, a compass firing 20 times a second (as a
// phone's does), and a finger panning the map; records build and raster
// time of every frame.
//
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/map_perf_test.dart -d <emulator>
//
// Writes build/map_perf.json. Numbers from an emulator use this PC's
// processor and graphics, so compare runs with each other, not with a
// real phone.
import 'dart:async';

import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_shared/sagip_shared.dart';

class _WelcomeDone extends WelcomeSeen {
  @override
  bool build() => true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late MockMobileBackend backend;
  late ProviderContainer container;

  setUp(() {
    backend = MockMobileBackend(
      latency: Duration.zero,
      timing: const MockSosTiming(
        send: Duration(milliseconds: 500),
        verify: Duration(seconds: 1),
        assign: Duration(seconds: 1),
        depart: Duration(seconds: 1),
        moveEvery: Duration(seconds: 1),
        arrive: Duration(minutes: 3),
        resolve: Duration(minutes: 4),
        offerAfter: Duration(seconds: 2),
        mapSave: Duration(seconds: 1),
        drive: Duration(minutes: 3),
      ),
    );
    var angle = 0.0;
    container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend, demoTools: false),
        welcomeSeenProvider.overrideWith(_WelcomeDone.new),
        // A compass: a new heading every 50 ms.
        headingSourceProvider.overrideWithValue(
          Stream.periodic(
            const Duration(milliseconds: 50),
            (_) => angle = (angle + 3) % 360,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    backend.dispose();
    container.dispose();
  });

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await waitFor(tester, finder);
    await tester.ensureVisible(finder.last);
    await tester.tap(finder.last);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SagipMobileApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  /// Ten pans of the map, back and forth, then one fling, with real time
  /// in between for tiles to load: about 15 seconds.
  Future<void> panAround(WidgetTester tester, Finder map) async {
    const moves = [
      Offset(-160, 0),
      Offset(0, -160),
      Offset(160, 0),
      Offset(0, 160),
      Offset(-220, -120),
      Offset(220, 120),
      Offset(-120, 200),
      Offset(120, -200),
      Offset(-200, 0),
      Offset(200, 0),
    ];
    for (final m in moves) {
      await tester.timedDrag(map, m, const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 900));
    }
    await tester.fling(map, const Offset(-400, -300), 1500);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('R3 Track responder', (tester) async {
    await start(tester);
    await tester.enterText(find.byType(TextField), '917 000 4821');
    await tap(tester, find.text('Send code'));
    await waitFor(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), MockMobileBackend.demoCode);
    await tester.pump(const Duration(seconds: 1));

    await waitFor(tester, find.byType(SosButton));
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump(const Duration(milliseconds: 2300));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 500));
    final skip = find.byKey(const ValueKey('whats-happening-skip'));
    if (skip.evaluate().isNotEmpty) await tap(tester, skip);

    await tap(tester, find.text('Track responder'));
    await tester.pump(const Duration(seconds: 3));
    await binding.watchPerformance(
      () => panAround(tester, find.byType(FlutterMap)),
      reportKey: 'track_responder',
    );
  });

  testWidgets('F4 Navigate', (tester) async {
    await start(tester);
    await tap(tester, find.text('MDRRMD personnel sign in'));
    await tester.enterText(find.byType(TextField).at(0), 'r03@sagip.test');
    await tester.enterText(find.byType(TextField).at(1), MockSeed.demoPassword);
    await tap(tester, find.text('Sign in'));

    await tap(tester, find.text('Accept and start'));
    await tap(tester, find.text('Start navigation'));
    await tester.pump(const Duration(seconds: 3));
    await binding.watchPerformance(
      () => panAround(tester, find.byType(FlutterMap)),
      reportKey: 'navigate',
    );
  });
}
