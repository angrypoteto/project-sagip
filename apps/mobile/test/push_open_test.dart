import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/app.dart';
import 'package:sagip_mobile/src/features/shell/push_routes.dart';
import 'package:sagip_mobile/src/providers.dart';
import 'package:sagip_mobile/src/router.dart';
import 'package:sagip_shared/sagip_shared.dart';

class WelcomeDone extends WelcomeSeen {
  @override
  bool build() => true;
}

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

const _maria = AppUser(
  id: 'res-001',
  displayName: 'Maria',
  email: '',
  role: UserRole.resident,
);
const _r03 = AppUser(
  id: 'staff-1',
  displayName: 'R-03',
  email: 'r03@sagip.test',
  role: UserRole.responder,
);

/// Tapping a push notification (plan part 7).
void main() {
  group('where a tap goes', () {
    final sos = SosRequest(
      clientId: 'c-1',
      capturedAt: DateTime(2026, 10, 3, 9),
      delivery: DeliveryState.delivered,
      incidentId: 'INC-0152',
    );

    test('an alert opens it for a resident; a responder goes home', () {
      const open = PushOpen(kind: PushKind.alert, alertId: 'alert-1');
      expect(pushDestination(open, _maria, const []), (
        location: Routes.alert('alert-1'),
        push: true,
      ));
      expect(pushDestination(open, _r03, const []), (
        location: Routes.duty,
        push: false,
      ));
    });

    test('a rescue confirmation opens that SOS, else the Alerts tab', () {
      const open = PushOpen(kind: PushKind.rescue, incidentId: 'INC-0152');
      expect(pushDestination(open, _maria, [sos]), (
        location: Routes.sos('c-1'),
        push: true,
      ));
      expect(pushDestination(open, _maria, const []), (
        location: Routes.alerts,
        push: false,
      ));
    });

    test('a new assignment opens the responder home (the offer)', () {
      const open = PushOpen(kind: PushKind.assignment, incidentId: 'INC-1');
      expect(pushDestination(open, _r03, const []), (
        location: Routes.duty,
        push: false,
      ));
    });
  });

  testWidgets('a tap that starts the app opens its page after sign-in', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 30, 15, 42);
    final backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
    );
    final taps = StreamController<PushOpen>.broadcast();
    final container = ProviderContainer(
      overrides: [
        ...mockOverrides(backend),
        mapTilesEnabledProvider.overrideWithValue(false),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        welcomeSeenProvider.overrideWith(WelcomeDone.new),
        pushOpensProvider.overrideWith((ref) => taps.stream),
      ],
    );
    addTearDown(() {
      container.dispose();
      backend.dispose();
      taps.close();
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

    // Not signed in yet: the tap waits.
    taps.add(const PushOpen(kind: PushKind.alert, alertId: 'alert-phivolcs-1'));
    await settle(tester);
    expect(find.text('Sign in'), findsWidgets);
    expect(container.read(pendingPushProvider), isNotNull);

    await tester.tap(find.text('Continue as resident'));
    await settle(tester);
    expect(
      find.text('Taal Volcano advisory: possible light ashfall'),
      findsOneWidget,
    );
    expect(find.text('What to do'), findsOneWidget, reason: 'the alert (R8)');
    expect(container.read(pendingPushProvider), isNull);

    // Back returns to the app underneath.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Hi, Maria'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
