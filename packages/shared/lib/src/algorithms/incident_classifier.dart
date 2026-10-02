import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/enums.dart';

/// Loads the bundled classifier model (about 33 KB).
Future<IncidentClassifier> loadIncidentClassifier([AssetBundle? bundle]) async {
  final text = await (bundle ?? rootBundle).loadString(
    IncidentClassifier.assetKey,
  );
  return IncidentClassifier.fromJson(jsonDecode(text) as Map<String, Object?>);
}

/// The classifier's reading of one description.
@immutable
class TypeSuggestion {
  const TypeSuggestion(this.type, this.confidence);

  final IncidentType type;

  /// The model's probability for [type], 0 to 1.
  final double confidence;
}

/// The incident type classifier (FR12): TF-IDF over word unigrams and
/// bigrams, then multinomial logistic regression over the four types.
///
/// The model is trained and exported by `ml/classifier/train_classifier.py`.
/// The database runs the same arithmetic in `private.classify_report` when a
/// crowd report arrives; this class is the app-side copy (sample data, and
/// anything that needs a suggestion before the server answers). Both must
/// give the numbers in `test/fixtures/classifier_reference.json`.
class IncidentClassifier {
  IncidentClassifier._(
    this.version,
    this.labels,
    this.minConfidence,
    this._intercept,
    this._terms,
    this._token,
  );

  factory IncidentClassifier.fromJson(Map<String, Object?> json) =>
      IncidentClassifier._(
        json['version']! as String,
        [
          for (final l in json['labels']! as List)
            IncidentType.values.byName(l as String),
        ],
        (json['minConfidence']! as num).toDouble(),
        [for (final b in json['intercept']! as List) (b as num).toDouble()],
        {
          for (final e in (json['terms']! as Map<String, Object?>).entries)
            e.key: [for (final v in e.value! as List) (v as num).toDouble()],
        },
        RegExp(json['tokenPattern']! as String),
      );

  /// The model file's asset key, for `rootBundle.loadString`.
  static const assetKey =
      'packages/sagip_shared/assets/classifier/incident_classifier_v1.json';

  /// Which training run this is, for example `v1-sample`.
  final String version;

  /// The types in the order the model scores them.
  final List<IncidentType> labels;

  /// Below this a report is left untagged, and the resident's own choice,
  /// if any, is used instead.
  final double minConfidence;

  final List<double> _intercept;

  /// Per term: its idf, then one weight per label.
  final Map<String, List<double>> _terms;
  final RegExp _token;

  int get termCount => _terms.length;

  /// The probability of each type, in [labels] order. A description with no
  /// known words gets the model's resting guess, which is close to even.
  List<double> probabilities(String text) {
    final tokens = [
      for (final m in _token.allMatches(text.toLowerCase())) m[0]!,
    ];
    final counts = <String, int>{};
    void count(String gram) {
      if (_terms.containsKey(gram)) counts[gram] = (counts[gram] ?? 0) + 1;
    }

    for (var i = 0; i < tokens.length; i++) {
      count(tokens[i]);
      if (i + 1 < tokens.length) count('${tokens[i]} ${tokens[i + 1]}');
    }

    final scores = [..._intercept];
    var squares = 0.0;
    for (final e in counts.entries) {
      final x = e.value * _terms[e.key]![0];
      squares += x * x;
    }
    if (squares > 0) {
      final norm = math.sqrt(squares);
      for (final e in counts.entries) {
        final term = _terms[e.key]!;
        final x = e.value * term[0] / norm;
        for (var i = 0; i < scores.length; i++) {
          scores[i] += term[i + 1] * x;
        }
      }
    }

    final top = scores.reduce(math.max);
    final exps = [for (final s in scores) math.exp(s - top)];
    final total = exps.reduce((a, b) => a + b);
    return [for (final e in exps) e / total];
  }

  /// The most likely type, however unsure the model is.
  TypeSuggestion classify(String text) {
    final probs = probabilities(text);
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return TypeSuggestion(labels[best], probs[best]);
  }

  /// The tag a crowd report gets: null when the model is not sure enough.
  TypeSuggestion? suggest(String text) {
    final best = classify(text);
    return best.confidence >= minConfidence ? best : null;
  }
}
