"""Trains the LSTM of the 72-hour forecast (FR4, plan 10.5) on the windows
that prepare_windows.py wrote, and compares it with the baselines.

The thesis parameters (CLAUDE.md, "Algorithm parameters"):
  - input: 14 days of the six daily features
  - two stacked LSTM layers of 64 and 32 units, dropout 0.2 after each
  - a dense output layer with a sigmoid: the probability of at least one
    incident in the next 72 hours
  - binary cross-entropy weighted by the class weights from the
    preparation (inversely proportional to class frequency)
  - Adam at a learning rate of 0.001, batch 32, up to 100 epochs, early
    stopping after 10 epochs without a better validation loss (the best
    weights are kept)

Needs TensorFlow, which needs Python 3.12 (see ml/README.md):
  .venv-tf/Scripts/python ml/forecast/prepare_windows.py
  .venv-tf/Scripts/python ml/forecast/train_lstm.py

Writes ml/forecast/lstm_metrics.json, and build/lstm_<hazard>.keras and
build/lstm_<hazard>.tflite (git-ignored).

On the sample data nothing here is a result: the data is made up.
"""

import json
import os
import time
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import tensorflow as tf  # noqa: E402

from prepare_windows import HAZARDS, scores  # noqa: E402

HERE = Path(__file__).parent
BUILD = HERE / "build"
SEED = 20261002

UNITS = (64, 32)
DROPOUT = 0.2
LEARNING_RATE = 0.001
BATCH = 32
MAX_EPOCHS = 100
PATIENCE = 10


def build_model(window, features):
    """The thesis architecture."""
    model = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(window, features)),
            tf.keras.layers.LSTM(UNITS[0], return_sequences=True),
            tf.keras.layers.Dropout(DROPOUT),
            tf.keras.layers.LSTM(UNITS[1]),
            tf.keras.layers.Dropout(DROPOUT),
            tf.keras.layers.Dense(1, activation="sigmoid"),
        ]
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss="binary_crossentropy",
        metrics=[tf.keras.metrics.AUC(name="auc")],
    )
    return model


def train(hazard, data, verbose=0):
    """Trains one hazard's model. Returns (model, history, seconds)."""
    tf.keras.utils.set_random_seed(SEED)
    x_train, y_train = data["x_train"], data["y_train"]
    x_val, y_val = data["x_val"], data["y_val"]
    weights = data["class_weight"]
    model = build_model(x_train.shape[1], x_train.shape[2])
    stop = tf.keras.callbacks.EarlyStopping(
        monitor="val_loss", patience=PATIENCE, restore_best_weights=True
    )
    started = time.perf_counter()
    history = model.fit(
        x_train,
        y_train,
        validation_data=(x_val, y_val),
        epochs=MAX_EPOCHS,
        batch_size=BATCH,
        class_weight={0: float(weights[0]), 1: float(weights[1])},
        callbacks=[stop],
        shuffle=True,
        verbose=verbose,
    )
    return model, history.history, time.perf_counter() - started


def inference_copy(model, window, features):
    """The same network and weights, for one window at a time, with the 14
    steps unrolled. TFLite then needs only its built-in operations (no
    TensorFlow "select ops", which would add megabytes to the app)."""
    copy = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(window, features), batch_size=1),
            tf.keras.layers.LSTM(UNITS[0], return_sequences=True, unroll=True),
            tf.keras.layers.Dropout(DROPOUT),
            tf.keras.layers.LSTM(UNITS[1], unroll=True),
            tf.keras.layers.Dropout(DROPOUT),
            tf.keras.layers.Dense(1, activation="sigmoid"),
        ]
    )
    copy.set_weights(model.get_weights())
    return copy


def export_tflite(model, x_check, path):
    """The on-device copy (plan Q2: still to decide whether it is needed).
    Returns its size and the largest difference from Keras over the check
    windows, or the reason it could not be made."""
    copy = inference_copy(model, x_check.shape[1], x_check.shape[2])
    converter = tf.lite.TFLiteConverter.from_keras_model(copy)
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    try:
        blob = converter.convert()
    except Exception as e:  # noqa: BLE001 - the reason goes in the metrics
        return {"error": f"not converted: {type(e).__name__}"}
    path.write_bytes(blob)
    interpreter = tf.lite.Interpreter(model_content=blob)
    interpreter.allocate_tensors()
    given = interpreter.get_input_details()[0]["index"]
    result = interpreter.get_output_details()[0]["index"]
    expected = model.predict(x_check, verbose=0).ravel()
    worst = 0.0
    for i in range(len(x_check)):
        interpreter.set_tensor(given, x_check[i : i + 1].astype(np.float32))
        interpreter.invoke()
        worst = max(worst, abs(float(interpreter.get_tensor(result)[0][0]) - float(expected[i])))
    return {"bytes": len(blob), "largest_difference_from_keras": float(f"{worst:.2e}")}


def main():
    prep = json.loads((HERE / "prep_summary.json").read_text(encoding="utf-8"))
    out = {
        "data": prep.get("data", "as given"),
        "tensorflow": tf.__version__,
        "architecture": {
            "lstm_units": list(UNITS),
            "dropout": DROPOUT,
            "output": "dense, sigmoid",
            "loss": "binary cross-entropy with class weights",
            "optimizer": f"Adam, learning rate {LEARNING_RATE}",
            "batch": BATCH,
            "max_epochs": MAX_EPOCHS,
            "early_stopping_patience": PATIENCE,
        },
        "threshold": 0.5,
        "hazards": {},
    }
    for hazard in HAZARDS:
        path = BUILD / f"windows_{hazard}.npz"
        if not path.exists():
            raise SystemExit(f"{path} is missing: run prepare_windows.py first")
        data = dict(np.load(path))
        if data["y_train"].min() == data["y_train"].max():
            out["hazards"][hazard] = {"skipped": "only one class in training"}
            continue
        model, history, seconds = train(hazard, data)
        best = int(np.argmin(history["val_loss"]))
        result = {
            "epochs_run": len(history["loss"]),
            "best_epoch": best + 1,
            "best_val_loss": round(float(history["val_loss"][best]), 4),
            "train_seconds": round(seconds, 1),
        }
        for name, x, y in (("validation", data["x_val"], data["y_val"]), ("test", data["x_test"], data["y_test"])):
            p = model.predict(x, verbose=0).ravel()
            result[name] = {
                "windows": int(len(y)),
                "positives": int(y.sum()),
                "lstm": scores(y, p),
                "baselines": prep["hazards"][hazard]["baselines"].get(name, {}),
            }
        test = result["test"]
        best_baseline = max(
            (b["f1"] for b in test["baselines"].values() if isinstance(b, dict) and "f1" in b),
            default=0.0,
        )
        result["test_f1_vs_best_baseline"] = [test["lstm"]["f1"], best_baseline]
        model.save(BUILD / f"lstm_{hazard}.keras")
        result["tflite"] = export_tflite(model, data["x_test"], BUILD / f"lstm_{hazard}.tflite")
        out["hazards"][hazard] = result
        print(
            f"  {hazard}: {result['epochs_run']} epochs (best {result['best_epoch']}), "
            f"test accuracy {test['lstm']['accuracy']}, F1 {test['lstm']['f1']} "
            f"(best baseline F1 {best_baseline}), {result['train_seconds']} s"
        )
    (HERE / "lstm_metrics.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
