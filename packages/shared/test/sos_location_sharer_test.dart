import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

class _Repo implements SosRepository {
  final sent = <(String, GeoPoint)>[];

  @override
  Future<void> updateLocation(String clientId, LocationFix fix) async =>
      sent.add((clientId, fix.point));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const home = GeoPoint(14.6091, 120.9925);
  GeoPoint north(double meters) =>
      GeoPoint(home.lat + meters / 111320, home.lng);

  late DateTime now;
  late _Repo repo;
  late SosLocationSharer sharer;

  SosRequest sos({
    String id = 'sos-1',
    DeliveryState delivery = DeliveryState.delivered,
    IncidentStatus? status = IncidentStatus.pendingVerification,
  }) => SosRequest(
    clientId: id,
    capturedAt: now,
    delivery: delivery,
    location: home,
    status: status,
  );

  LocationFix fix(GeoPoint p, {bool manual = false}) =>
      LocationFix(point: p, accuracyMeters: 8, at: now, manual: manual);

  setUp(() {
    now = DateTime(2026, 10, 11, 9);
    repo = _Repo();
    sharer = SosLocationSharer(repo, clock: () => now);
  });

  test('nothing is sent without an open SOS that MDRRMD has', () {
    sharer.onFix(fix(north(200)), const []);
    sharer.onFix(fix(north(200)), [sos(delivery: DeliveryState.savedOnPhone)]);
    sharer.onFix(fix(north(200)), [sos(status: IncidentStatus.resolved)]);
    sharer.onFix(null, [sos()]);
    sharer.onFix(fix(north(200), manual: true), [sos()]);
    expect(repo.sent, isEmpty);
  });

  test('a move of 25 m or more is sent; a smaller one is not', () {
    sharer.onFix(fix(north(10)), [sos()]);
    expect(repo.sent, isEmpty, reason: 'still where the SOS was sent');
    sharer.onFix(fix(north(40)), [sos()]);
    expect(repo.sent, [('sos-1', north(40))]);
  });

  test('at most one position a minute, measured from the last one sent', () {
    sharer.onFix(fix(north(40)), [sos()]);
    now = now.add(const Duration(seconds: 30));
    sharer.onFix(fix(north(120)), [sos()]);
    expect(repo.sent, hasLength(1));
    now = now.add(const Duration(seconds: 31));
    sharer.onFix(fix(north(50)), [sos()]);
    expect(repo.sent, hasLength(1), reason: 'only 10 m from the last one');
    sharer.onFix(fix(north(120)), [sos()]);
    expect(repo.sent.last, ('sos-1', north(120)));
  });

  test('a new SOS starts again from where it was sent', () {
    sharer.onFix(fix(north(40)), [sos()]);
    sharer.onFix(fix(north(40)), [
      sos(id: 'sos-2'),
      sos(status: IncidentStatus.resolved),
    ]);
    expect(repo.sent.last, ('sos-2', north(40)));
  });
}
