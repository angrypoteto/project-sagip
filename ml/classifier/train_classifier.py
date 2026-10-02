"""Trains and exports the incident type classifier (FR12, plan 10.4).

TF-IDF over word unigrams and bigrams (the thesis parameters) with
multinomial logistic regression, four labels: flood, fire, medical,
structural.

Reads   ml/classifier/data/sample_reports.csv      (made-up sample data)
        ml/classifier/data/handwritten_check.csv   (written apart from it)
Writes  packages/shared/assets/classifier/incident_classifier_v1.json
        packages/shared/test/fixtures/classifier_reference.json
        ml/classifier/metrics.json
        ml/classifier/build/classifier_model.sql   (for a migration)

The exported model is rounded to 5 decimals. `classify()` below is the
reference for the two other implementations (`IncidentClassifier` in Dart
and `private.classify_report` in the database): all three must give the
numbers in classifier_reference.json.

Usage: python ml/classifier/train_classifier.py
"""

import csv
import json
import math
import re
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import confusion_matrix, precision_recall_fscore_support
from sklearn.model_selection import StratifiedKFold, cross_val_score, train_test_split
from sklearn.pipeline import make_pipeline

HERE = Path(__file__).parent
ROOT = HERE.parent.parent
SAMPLE = HERE / "data" / "sample_reports.csv"
HANDWRITTEN = HERE / "data" / "handwritten_check.csv"
MODEL_OUT = ROOT / "packages/shared/assets/classifier/incident_classifier_v1.json"
REFERENCE_OUT = ROOT / "packages/shared/test/fixtures/classifier_reference.json"
METRICS_OUT = HERE / "metrics.json"
SQL_OUT = HERE / "build" / "classifier_model.sql"

VERSION = "v1-sample"
NOTE = (
    "Trained on made-up sample descriptions, not MDRRMD records. "
    "Retrain on the real labelled set before reporting accuracy."
)
SEED = 42
# A word is two or more letters or digits; everything else separates words.
TOKEN = r"[a-zñ0-9]{2,}"
MAX_TERMS = 600
# Below this the report is left untagged and the resident's own choice, if
# any, is used instead.
MIN_CONFIDENCE = 0.5
DECIMALS = 5

# Texts for the reference file, besides a few from the handwritten check.
EDGE_CASES = [
    "",
    "   ",
    "???",
    "asdf qwerty zxcv",
    "a b c d",
    "baha",
    "BAHA NA SA ESPAÑA",
    "sunog sunog sunog",
    "Baha-baha, lampas-tao!",
    "may sunog\nat makapal na usok",
    "5 katao naipit sa 2nd floor, gumuho ang pader",
    "walang sunog, baha lang po",
    "nahimatay sa baha",
    "The bridge is on fire",
]


def read(path: Path) -> tuple[list[str], list[str]]:
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    return [r["description"] for r in rows], [r["label"] for r in rows]


def pipeline():
    return make_pipeline(
        TfidfVectorizer(
            lowercase=True,
            token_pattern=TOKEN,
            ngram_range=(1, 2),
            min_df=2,
            max_features=MAX_TERMS,
        ),
        LogisticRegression(C=10.0, max_iter=2000),
    )


def classify(model: dict, text: str) -> list[float]:
    """Inference from the exported model alone: the reference."""
    tokens = re.findall(model["tokenPattern"], text.lower())
    grams = tokens + [f"{a} {b}" for a, b in zip(tokens, tokens[1:])]
    counts: dict[str, int] = {}
    for g in grams:
        if g in model["terms"]:
            counts[g] = counts.get(g, 0) + 1
    scores = list(model["intercept"])
    norm = math.sqrt(sum((n * model["terms"][g][0]) ** 2 for g, n in counts.items()))
    if norm > 0:
        for g, n in counts.items():
            idf, *weights = model["terms"][g]
            for i, w in enumerate(weights):
                scores[i] += w * n * idf / norm
    top = max(scores)
    exps = [math.exp(s - top) for s in scores]
    total = sum(exps)
    return [e / total for e in exps]


def report(labels, truth, predicted) -> dict:
    p, r, f, n = precision_recall_fscore_support(
        truth, predicted, labels=labels, zero_division=0
    )
    return {
        "accuracy": round(float(np.mean(np.array(truth) == np.array(predicted))), 4),
        "perClass": {
            label: {
                "precision": round(float(p[i]), 4),
                "recall": round(float(r[i]), 4),
                "f1": round(float(f[i]), 4),
                "count": int(n[i]),
            }
            for i, label in enumerate(labels)
        },
        "confusionMatrix": {
            "rowsAreTruth": labels,
            "columnsArePredicted": labels,
            "counts": confusion_matrix(truth, predicted, labels=labels).tolist(),
        },
    }


def confident(labels, model, texts, truth) -> dict:
    """How many texts get a tag at MIN_CONFIDENCE, and how many are right."""
    tagged = right = 0
    for text, label in zip(texts, truth):
        probs = classify(model, text)
        best = max(range(len(probs)), key=probs.__getitem__)
        if probs[best] >= model["minConfidence"]:
            tagged += 1
            right += labels[best] == label
    return {
        "tagged": tagged,
        "of": len(texts),
        "accuracyWhenTagged": round(right / tagged, 4) if tagged else None,
    }


def main() -> None:
    texts, labels_all = read(SAMPLE)
    hand_texts, hand_labels = read(HANDWRITTEN)
    train_x, test_x, train_y, test_y = train_test_split(
        texts, labels_all, test_size=0.2, random_state=SEED, stratify=labels_all
    )

    folds = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
    cv = cross_val_score(pipeline(), train_x, train_y, cv=folds)

    fitted = pipeline().fit(train_x, train_y)
    vectorizer, classifier = fitted.steps[0][1], fitted.steps[1][1]
    labels = [str(c) for c in classifier.classes_]

    terms = {
        term: [round(float(vectorizer.idf_[i]), DECIMALS)]
        + [round(float(w), DECIMALS) for w in classifier.coef_[:, i]]
        for term, i in sorted(vectorizer.vocabulary_.items())
    }
    model = {
        "version": VERSION,
        "note": NOTE,
        "labels": labels,
        "minConfidence": MIN_CONFIDENCE,
        "tokenPattern": TOKEN,
        "intercept": [round(float(b), DECIMALS) for b in classifier.intercept_],
        "terms": terms,
    }

    # The rounded export must agree with scikit-learn itself.
    everything = test_x + hand_texts + EDGE_CASES
    theirs = fitted.predict_proba(everything)
    worst = 0.0
    for text, expected in zip(everything, theirs):
        ours = classify(model, text)
        worst = max(worst, max(abs(a - b) for a, b in zip(ours, expected)))
    assert worst < 2e-3, f"export differs from scikit-learn by {worst}"

    def predict(xs):
        return [labels[int(np.argmax(classify(model, x)))] for x in xs]

    counts = {label: labels_all.count(label) for label in labels}
    metrics = {
        "model": VERSION,
        "warning": NOTE,
        "data": {
            "sample": {"file": SAMPLE.name, "rows": len(texts), "perClass": counts},
            "split": "stratified 80/20, random_state 42; the model is fitted on the 80%",
            "handwritten": {"file": HANDWRITTEN.name, "rows": len(hand_texts)},
        },
        "features": {
            "tfidf": "word unigrams and bigrams, lowercase, l2 norm, smooth idf",
            "tokenPattern": TOKEN,
            "minDf": 2,
            "terms": len(terms),
        },
        "classifier": "multinomial logistic regression, C=10, lbfgs",
        "noSkillAccuracy": round(max(counts.values()) / len(texts), 4),
        "crossValidation": {
            "folds": 5,
            "accuracyMean": round(float(cv.mean()), 4),
            "accuracyStd": round(float(cv.std()), 4),
        },
        "heldOutSample": report(labels, test_y, predict(test_x)),
        "handwrittenCheck": report(labels, hand_labels, predict(hand_texts)),
        "atMinConfidence": {
            "minConfidence": MIN_CONFIDENCE,
            "heldOutSample": confident(labels, model, test_x, test_y),
            "handwrittenCheck": confident(labels, model, hand_texts, hand_labels),
        },
        "exportVsScikitLearnMaxDifference": round(worst, 6),
    }

    by_label: dict[str, list[str]] = {label: [] for label in labels}
    for text, label in zip(hand_texts, hand_labels):
        if len(by_label[label]) < 6:
            by_label[label].append(text)
    cases = []
    for text in [t for group in by_label.values() for t in group] + EDGE_CASES:
        probs = classify(model, text)
        best = int(np.argmax(probs))
        cases.append(
            {
                "text": text,
                "label": labels[best],
                "confidence": round(probs[best], 6),
                "probabilities": [round(p, 6) for p in probs],
                "tagged": probs[best] >= MIN_CONFIDENCE,
            }
        )
    reference = {"model": VERSION, "labels": labels, "cases": cases}

    def dump(path: Path, value, indent=None) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        text = json.dumps(
            value,
            ensure_ascii=False,
            indent=indent,
            separators=None if indent else (",", ":"),
        )
        path.write_text(text + "\n", encoding="utf-8", newline="\n")

    dump(MODEL_OUT, model)
    dump(REFERENCE_OUT, reference, indent=1)
    dump(METRICS_OUT, metrics, indent=2)

    # Eight terms to a line, so the migration can be read and reviewed.
    entries = [
        json.dumps(term, ensure_ascii=False) + ":" + json.dumps(v, separators=(",", ":"))
        for term, v in model["terms"].items()
    ]
    compact = (
        "{\n"
        + ",\n".join(",".join(entries[i : i + 8]) for i in range(0, len(entries), 8))
        + "\n}"
    )
    assert "$model$" not in compact and "'" not in NOTE
    SQL_OUT.parent.mkdir(parents=True, exist_ok=True)
    SQL_OUT.write_text(
        "insert into public.classifier_model\n"
        "  (model_id, is_active, note, labels, intercept, min_confidence, terms)\n"
        "values (\n"
        f"  '{VERSION}', true,\n"
        f"  '{NOTE}',\n"
        f"  array[{', '.join(repr(l) for l in labels)}],\n"
        f"  array[{', '.join(str(b) for b in model['intercept'])}]::double precision[],\n"
        f"  {MIN_CONFIDENCE},\n"
        f"  $model${compact}$model$::jsonb\n"
        ");\n",
        encoding="utf-8",
        newline="\n",
    )

    print(f"terms: {len(terms)}  model file: {MODEL_OUT.stat().st_size} bytes")
    print(f"5-fold accuracy on the training part: {cv.mean():.4f} (+/- {cv.std():.4f})")
    print(f"held-out sample accuracy: {metrics['heldOutSample']['accuracy']}")
    print(f"handwritten check accuracy: {metrics['handwrittenCheck']['accuracy']}")
    print(f"tagged at {MIN_CONFIDENCE}: {metrics['atMinConfidence']}")
    print(f"export vs scikit-learn, largest difference: {worst:.6f}")


if __name__ == "__main__":
    main()
