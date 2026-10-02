import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

class _Device implements PushDevice {
  String? current = 'token-1';
  final refreshes = StreamController<String>.broadcast();
  final taps = StreamController<Map<String, Object?>>.broadcast();
  final topics = <String>{};
  final log = <String>[];
  var offline = false;

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Future<void> subscribe(String topic) async {
    if (offline) throw StateError('offline');
    topics.add(topic);
    log.add('+$topic');
  }

  @override
  Future<void> unsubscribe(String topic) async {
    if (offline) throw StateError('offline');
    topics.remove(topic);
    log.add('-$topic');
  }

  @override
  Future<void> deleteToken() async {
    log.add('delete');
    current = null;
  }

  @override
  Stream<Map<String, Object?>> get opened => taps.stream;
}

class _Registry implements PushRegistry {
  final calls = <String>[];
  var offline = false;

  @override
  Future<void> register(String token) async {
    if (offline) throw const ActionRejected(ActionRejection.offline);
    calls.add('register $token');
  }

  @override
  Future<void> forget(String token) async => calls.add('forget $token');
}

const _maria = AppUser(
  id: 'res-001',
  displayName: 'Maria',
  email: '',
  role: UserRole.resident,
);
const _responder = AppUser(
  id: 'staff-1',
  displayName: 'R-03',
  email: 'r03@sagip.test',
  role: UserRole.responder,
);

/// Push notifications on the phone (FR6, FR14; plan part 7).
void main() {
  test('barangay topics: the same vectors as the sender (fcm.test.ts)', () {
    const vectors = {
      'Barangay 412': 'area-barangay-412',
      'Barangay 105': 'area-barangay-105',
      '  Barangay  649 ': 'area-barangay-649',
      'Barangay 830 (Pandacan)': 'area-barangay-830-pandacan',
      'Sta. Ana': 'area-sta-ana',
      'España': 'area-espana',
      'Peñafrancia': 'area-penafrancia',
      '***': 'area-unknown',
    };
    vectors.forEach((name, topic) {
      expect(pushTopicForBarangay(name), topic, reason: name);
      expect(RegExp(r'^[a-zA-Z0-9\-_.~%]{1,900}$').hasMatch(topic), isTrue);
    });
  });

  test('who gets which topics', () {
    expect(pushTopicsFor(_maria, barangay: 'Barangay 412'), {
      'manila',
      'area-barangay-412',
    });
    expect(pushTopicsFor(_maria), {'manila'}, reason: 'barangay not known');
    expect(pushTopicsFor(_responder), {'manila'});
    expect(pushTopicsFor(null), isEmpty);
    const dispatcher = AppUser(
      id: 'd',
      displayName: 'D',
      email: 'd@sagip.test',
      role: UserRole.dispatcher,
    );
    expect(pushTopicsFor(dispatcher), isEmpty, reason: 'the dashboard only');
  });

  test('a tapped notification is read from its data', () {
    final alert = PushOpen.fromData({'type': 'alert', 'alert_id': 'a-1'})!;
    expect((alert.kind, alert.alertId), (PushKind.alert, 'a-1'));
    final rescue = PushOpen.fromData({
      'type': 'rescue',
      'incident_id': 'INC-0152',
      'confirmation_id': '7',
    })!;
    expect((rescue.kind, rescue.incidentId), (PushKind.rescue, 'INC-0152'));
    expect(
      PushOpen.fromData({'type': 'assignment', 'incident_id': 'INC-1'})!.kind,
      PushKind.assignment,
    );
    expect(PushOpen.fromData({'type': 'alert'}), isNull);
    expect(PushOpen.fromData({'type': 'rescue'}), isNull);
    expect(PushOpen.fromData({'type': 'something-new'}), isNull);
    expect(PushOpen.fromData(const {}), isNull);
  });

  group('the coordinator', () {
    late _Device device;
    late _Registry registry;
    late MemoryLocalStore store;
    late PushCoordinator push;

    setUp(() {
      device = _Device();
      registry = _Registry();
      store = MemoryLocalStore();
      push = PushCoordinator(device: device, registry: registry, store: store);
    });

    tearDown(() => push.dispose());

    test('sign-in registers the phone and joins the topics', () async {
      await push.setAccount(_maria, barangay: 'Barangay 412');
      expect(registry.calls, ['register token-1']);
      expect(device.topics, {'manila', 'area-barangay-412'});

      // The next start: nothing to change, registered again (the server
      // keeps the phone's last-seen time).
      await push.setAccount(_maria, barangay: 'Barangay 412');
      expect(device.log.toSet(), {'+area-barangay-412', '+manila'});
      expect(device.log, hasLength(2), reason: 'nothing joined twice');
      expect(registry.calls, ['register token-1', 'register token-1']);
    });

    test('a new token is registered while signed in only', () async {
      await push.setAccount(_maria, barangay: 'Barangay 412');
      device.refreshes.add('token-2');
      await pumpEventQueue();
      expect(registry.calls.last, 'register token-2');

      await push.setAccount(null);
      device.refreshes.add('token-3');
      await pumpEventQueue();
      expect(registry.calls, isNot(contains('register token-3')));
    });

    test('sign-out leaves the topics and drops the token', () async {
      await push.setAccount(_maria, barangay: 'Barangay 412');
      await push.forgetHere();
      expect(registry.calls.last, 'forget token-1');
      await push.setAccount(null);
      expect(device.topics, isEmpty);
      expect(device.log.last, 'delete');

      // A responder signs in on the same phone: only all of Manila.
      device.current = 'token-9';
      await push.setAccount(_responder);
      expect(device.topics, {'manila'});
      expect(registry.calls.last, 'register token-9');
    });

    test('offline: what failed is tried again at the next start', () async {
      device.offline = true;
      registry.offline = true;
      await push.setAccount(_maria, barangay: 'Barangay 412');
      expect(device.topics, isEmpty);
      expect(store.read('push:topics'), isEmpty);

      device.offline = false;
      registry.offline = false;
      await push.setAccount(_maria, barangay: 'Barangay 412');
      expect(device.topics, {'manila', 'area-barangay-412'});
      expect(registry.calls, ['register token-1']);
    });

    test('a move to another barangay changes one topic', () async {
      await push.setAccount(_maria, barangay: 'Barangay 412');
      await push.setAccount(_maria, barangay: 'Barangay 490');
      expect(device.topics, {'manila', 'area-barangay-490'});
      expect(device.log.sublist(2), [
        '-area-barangay-412',
        '+area-barangay-490',
      ]);
    });

    test(
      'taps on known notifications come through; others are ignored',
      () async {
        final opens = <PushOpen>[];
        final sub = push.opened.listen(opens.add);
        device.taps.add({'type': 'alert', 'alert_id': 'a-1'});
        device.taps.add({'type': 'unknown'});
        device.taps.add({'type': 'assignment', 'incident_id': 'INC-0152'});
        await pumpEventQueue();
        expect(
          [for (final o in opens) o.kind],
          [PushKind.alert, PushKind.assignment],
        );
        await sub.cancel();
      },
    );
  });
}
