import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Moves [p] by roughly [northMeters] and [eastMeters] (fine at city scale).
GeoPoint offset(GeoPoint p, double northMeters, double eastMeters) => GeoPoint(
  p.lat + northMeters / 111320,
  p.lng + eastMeters / (111320 * 0.9686), // cos(14.6°) for Manila
);

void main() {
  const dapitan = GeoPoint(14.6118, 120.9893);
  List<int> run(List<GeoPoint> pts) => dbscan(pts, locate: (p) => p);

  group('haversine distance', () {
    test('matches a flat-earth estimate at city scale', () {
      // 0.0091° north (1,013 m) and 0.0027° east (291 m): about 1,054 m.
      const cityHall = GeoPoint(14.5896, 120.9811);
      const quiapo = GeoPoint(14.5987, 120.9838);
      expect(cityHall.distanceTo(quiapo), closeTo(1055, 15));
    });

    test('is zero for the same point', () {
      expect(dapitan.distanceTo(dapitan), 0);
    });
  });

  group('dbscan with eps 50 m and minPts 3 (thesis values)', () {
    test('a single report stays unverified (noise)', () {
      expect(run([dapitan]), [kDbscanNoise]);
    });

    test('two reports within 50 m are not enough', () {
      expect(run([dapitan, offset(dapitan, 20, 0)]), [
        kDbscanNoise,
        kDbscanNoise,
      ]);
    });

    test('three reports within 50 m form one cluster', () {
      final labels = run([
        dapitan,
        offset(dapitan, 20, 0),
        offset(dapitan, 0, 25),
      ]);
      expect(labels, [0, 0, 0]);
    });

    test('three reports spread 80 m apart do not cluster', () {
      final labels = run([
        dapitan,
        offset(dapitan, 80, 0),
        offset(dapitan, 160, 0),
      ]);
      expect(labels, everyElement(kDbscanNoise));
    });

    test('a border point joins the cluster of a core point', () {
      // Three points close together (core) and one 45 m from the edge.
      final labels = run([
        dapitan,
        offset(dapitan, 10, 0),
        offset(dapitan, 0, 10),
        offset(dapitan, 10, 45),
      ]);
      expect(labels, [0, 0, 0, 0]);
    });

    test('separate groups get separate cluster numbers', () {
      const tondo = GeoPoint(14.6197, 120.9670);
      final labels = run([
        dapitan,
        offset(dapitan, 15, 0),
        offset(dapitan, 0, 15),
        tondo,
        offset(tondo, 15, 0),
        offset(tondo, 0, 15),
        const GeoPoint(14.58, 121.0), // lone report far away
      ]);
      expect(labels.sublist(0, 3), everyElement(labels[0]));
      expect(labels.sublist(3, 6), everyElement(labels[3]));
      expect(labels[0], isNot(labels[3]));
      expect(labels[6], kDbscanNoise);
    });
  });
}
