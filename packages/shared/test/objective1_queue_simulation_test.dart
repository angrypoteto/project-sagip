// Objective 1, the Priority Queue (2026-11-12): a typhoon surge in which
// incidents come in faster than the units can clear them. Each time a unit
// is free, the dispatcher sends it to the next waiting incident, either the
// oldest (first come, first served: a hotline logbook) or the first on the
// Triage Queue (PriorityRules.order, the real ranking the board uses).
//
// Joshua, 2026-11-12: keep the objective as written; MDRRMD does not control
// the responders' travel, and the time on scene depends on the situation.
// So the measure here is the wait from the report to a unit being sent.
//
// A queue does not make the average wait shorter (the same units clear the
// same work); it moves the most urgent cases forward. So the result is the
// wait of the vulnerable households' SOS, and of everyone, under both.
//
// What is real: the ranking (PriorityRules with the seeded A3 weights) and
// the units' road travel times (Dijkstra, docs/testing/dijkstra/
// suggestions.csv). What is assumed: the mix (one SOS household in seven
// vulnerable, as the NFR7 surge test; one report in five a crowd cluster;
// one in 200 with a mock location), the arrivals (random, over a 3-hour
// surge), and the time a unit is busy (twice its drive plus 20 to 60
// minutes on scene). Ten units, as on the hosted project.
//
// Skipped in normal runs (it writes files). Run it with:
//   cd packages/shared
//   SAGIP_EVAL=1 flutter test test/objective1_queue_simulation_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

const _out = '../../docs/testing/objective1';
const _units = 10;
const _runs = 200;
const _surge = Duration(hours: 3);

Incident _incident(String id, DateTime at, math.Random rng) {
  final sos = rng.nextDouble() >= 0.2;
  return Incident(
    id: id,
    origin: sos ? IncidentOrigin.sos : IncidentOrigin.crowdCluster,
    channel: ReportChannel.app,
    status: IncidentStatus.pendingVerification,
    location: const GeoPoint(14.6, 121.0),
    barangay: 'Barangay 1',
    district: 'Tondo',
    capturedAt: at,
    receivedAt: at,
    vulnerable: sos && rng.nextInt(7) == 0
        ? const [VulnerabilityType.seniorCitizen]
        : const [],
    mockLocationSuspected: rng.nextInt(200) == 0,
  );
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _p90(List<double> xs) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * 0.9).round()];
}

double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

void main() {
  final run = Platform.environment['SAGIP_EVAL'] != null;

  test(
    'Objective 1: the Priority Queue in a surge',
    () {
      final drives = [
        for (final line in File(
          '../../docs/testing/dijkstra/suggestions.csv',
        ).readAsLinesSync().skip(1))
          if (line.trim().isNotEmpty) double.parse(line.split(',')[3]),
      ];
      const rules = PriorityRules();
      final start = DateTime.utc(2026, 11, 12, 6);
      final results = <Map<String, Object?>>[];
      final csv = StringBuffer(
        'reports_per_hour,method,group,incidents,median_wait_min,'
        'mean_wait_min,p90_wait_min\n',
      );

      for (final perHour in [12, 16, 20, 30]) {
        final waits = {
          for (final m in ['fifo', 'queue'])
            for (final g in ['vulnerable', 'other_sos', 'cluster', 'all'])
              '$m/$g': <double>[],
        };
        for (var r = 0; r < _runs; r++) {
          // The same surge for both methods.
          final rng = math.Random(perHour * 1000 + r);
          final arrivals = <Incident>[];
          var t = Duration.zero;
          var n = 0;
          while (true) {
            final gap = -math.log(1 - rng.nextDouble()) * 3600 / perHour;
            t += Duration(milliseconds: (gap * 1000).round());
            if (t > _surge) break;
            arrivals.add(_incident('INC-${n++}', start.add(t), rng));
          }
          final busy = [
            for (final _ in arrivals)
              Duration(
                seconds:
                    ((2 * drives[rng.nextInt(drives.length)] +
                                20 +
                                40 * rng.nextDouble()) *
                            60)
                        .round(),
              ),
          ];

          for (final method in ['fifo', 'queue']) {
            final freeAt = List.filled(_units, start);
            final waiting = <Incident>[];
            var next = 0;
            var done = 0;
            while (done < arrivals.length) {
              // The next unit to come free.
              var u = 0;
              for (var i = 1; i < _units; i++) {
                if (freeAt[i].isBefore(freeAt[u])) u = i;
              }
              var now = freeAt[u];
              if (waiting.isEmpty && next < arrivals.length) {
                final a = arrivals[next].capturedAt;
                if (a.isAfter(now)) now = a;
              }
              while (next < arrivals.length &&
                  !arrivals[next].capturedAt.isAfter(now)) {
                waiting.add(arrivals[next++]);
              }
              final pick = method == 'fifo'
                  ? waiting.first
                  : rules.order(waiting, now).first;
              waiting.remove(pick);
              final idx = int.parse(pick.id.substring(4));
              freeAt[u] = now.add(busy[idx]);
              done++;
              final w = now.difference(pick.capturedAt).inSeconds / 60;
              final g = pick.origin == IncidentOrigin.crowdCluster
                  ? 'cluster'
                  : (pick.vulnerable.isNotEmpty ? 'vulnerable' : 'other_sos');
              waits['$method/$g']!.add(w);
              waits['$method/all']!.add(w);
            }
          }
        }

        final row = <String, Object?>{'reports_per_hour': perHour};
        for (final e in waits.entries) {
          final xs = e.value;
          row[e.key] = {
            'incidents': xs.length,
            'median_wait_min': _median(xs),
            'mean_wait_min': _mean(xs),
            'p90_wait_min': _p90(xs),
          };
          final parts = e.key.split('/');
          csv.writeln(
            [
              perHour,
              parts[0],
              parts[1],
              xs.length,
              _median(xs).toStringAsFixed(2),
              _mean(xs).toStringAsFixed(2),
              _p90(xs).toStringAsFixed(2),
            ].join(','),
          );
        }
        final fv = _mean(waits['fifo/vulnerable']!);
        final qv = _mean(waits['queue/vulnerable']!);
        row['vulnerable_mean_wait_reduction_pct'] = fv == 0
            ? 0
            : 100 * (fv - qv) / fv;
        results.add(row);
      }

      final summary = {
        'ran_at': DateTime.now().toIso8601String(),
        'units': _units,
        'surge_hours': _surge.inHours,
        'runs_per_rate': _runs,
        'results': results,
      };
      Directory(_out).createSync(recursive: true);
      File(
        '$_out/queue_simulation_summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
      File('$_out/queue_simulation.csv').writeAsStringSync(csv.toString());
      // ignore: avoid_print
      print(csv);

      // The queue never makes the vulnerable wait longer than first come,
      // first served.
      for (final r in results) {
        expect(
          r['vulnerable_mean_wait_reduction_pct']! as num,
          greaterThanOrEqualTo(0),
        );
      }
    },
    skip: run
        ? false
        : 'set SAGIP_EVAL=1 to run (writes docs/testing/objective1)',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
