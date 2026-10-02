import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

IncidentClassifier loadModel() => IncidentClassifier.fromJson(
  jsonDecode(
    File('assets/classifier/incident_classifier_v1.json').readAsStringSync(),
  ) as Map<String, Object?>,
);

Map<String, Object?> loadReference() => jsonDecode(
  File('test/fixtures/classifier_reference.json').readAsStringSync(),
) as Map<String, Object?>;

/// A two-word model small enough to check by hand.
IncidentClassifier tiny() => IncidentClassifier.fromJson({
  'version': 'tiny',
  'labels': ['fire', 'flood'],
  'minConfidence': 0.6,
  'tokenPattern': '[a-zñ0-9]{2,}',
  'intercept': [0.0, 0.0],
  'terms': {
    'sunog': [1.0, 2.0, -2.0],
    'baha': [1.0, -2.0, 2.0],
    'baha na': [2.0, -1.0, 1.0],
  },
});

void main() {
  group('the arithmetic', () {
    test('one known word: its weights decide', () {
      // x = 1 (one term, normalised), scores 2 and -2, softmax.
      final p = tiny().probabilities('Sunog!');
      expect(p[0], closeTo(1 / (1 + 0.01831563888), 1e-9));
      expect(p[0] + p[1], closeTo(1, 1e-12));
    });

    test('word pairs count, and the vector is normalised', () {
      // "baha na": baha (tf 1, idf 1) and "baha na" (tf 1, idf 2).
      // norm = sqrt(1 + 4); flood score = (2 * 1 + 1 * 2) / norm.
      final p = tiny().probabilities('baha na');
      final flood = 4 / math.sqrt(5);
      expect(p[1], closeTo(1 / (1 + math.exp(-2 * flood)), 1e-12));
      // Repeating a word changes nothing: its count scales out.
      expect(
        tiny().probabilities('baha baha')[1],
        closeTo(tiny().probabilities('baha')[1], 1e-12),
      );
    });

    test('case, punctuation, and one-letter words do not matter', () {
      final c = tiny();
      expect(c.probabilities('BAHA, na a b!'), c.probabilities('baha na'));
      expect(
        c.probabilities('baha\nna'),
        c.probabilities('baha na'),
        reason: 'a line break separates words like a space',
      );
    });

    test('no known words: the resting guess, and no tag', () {
      final c = tiny();
      expect(c.probabilities('???'), [0.5, 0.5]);
      expect(c.probabilities(''), [0.5, 0.5]);
      expect(c.suggest('asdf qwerty'), isNull);
      // On a tie the first label wins, as in the database.
      expect(c.classify('').type, IncidentType.fire);
    });

    test('a tag needs the minimum confidence', () {
      final c = tiny();
      expect(c.suggest('sunog')!.type, IncidentType.fire);
      // Both words: scores cancel, 0.5 each, below 0.6.
      expect(c.classify('sunog baha').confidence, closeTo(0.5, 1e-9));
      expect(c.suggest('sunog baha'), isNull);
    });
  });

  group('the exported model', () {
    final model = loadModel();
    final reference = loadReference();

    test('is the sample model, with the four types', () {
      expect(model.version, reference['model']);
      expect(model.version, 'v1-sample');
      expect(model.labels.toSet(), IncidentType.values.toSet());
      expect([for (final l in model.labels) l.name], reference['labels']);
      expect(model.minConfidence, 0.5);
      expect(model.termCount, 600);
    });

    // The same cases the database is checked with (rls_test.sql).
    test('gives the numbers in the reference file', () {
      final cases = (reference['cases']! as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThanOrEqualTo(30));
      for (final c in cases) {
        final text = c['text']! as String;
        final probs = model.probabilities(text);
        final expected = (c['probabilities']! as List).cast<num>();
        for (var i = 0; i < probs.length; i++) {
          expect(probs[i], closeTo(expected[i], 2e-6), reason: text);
        }
        final best = model.classify(text);
        expect(best.type.name, c['label'], reason: text);
        expect(best.confidence, closeTo(c['confidence']! as num, 2e-6));
        expect(model.suggest(text) != null, c['tagged'], reason: text);
      }
    });

    test('plain cases in each language', () {
      IncidentType? tag(String text) => model.suggest(text)?.type;
      expect(
        tag('Baha na po dito, hanggang bewang ang tubig'),
        IncidentType.flood,
      );
      expect(
        tag('There is a fire, thick smoke from the building'),
        IncidentType.fire,
      );
      expect(
        tag('May nahimatay, hindi humihinga, need ambulance'),
        IncidentType.medical,
      );
      expect(
        tag('Gumuho ang pader, nakaharang sa kalsada'),
        IncidentType.structural,
      );
      expect(tag('BAHA NA SA ESPAÑA'), IncidentType.flood);
      expect(tag('hello'), isNull);
    });
  });
}
