"""Exports the forecast for the live feed (thesis scope: "LSTM and KDE
trained, simulated live feed"): everything the `run-forecast` Edge Function
needs to make a forecast run on its own, every few hours, without
TensorFlow.

Writes supabase/data/forecast_live_v1.json (kept in git; it is the sample
model, nothing secret):
  - the three LSTMs' weights (Keras LSTM gates in the order i, f, c, o;
    tanh and sigmoid; the dropout layers do nothing at inference) and each
    hazard's scaler,
  - the replayed weather: every day of the weather file with its five
    readings, and each hazard's incident count of the day before (the sixth
    feature), so the feed replays the records day by day as if they were
    today's,
  - the KDE's relative density per barangay (only the barangays at or above
    the lowest density the rule uses; the rest are low whatever the
    probability),
  - the provisional rule (run_forecast.RULE, plan Q22),
  - test vectors: Keras's own probability for a few windows, which the
    Edge Function's tests must match.

Usage (TensorFlow is in .venv-tf), after train_lstm.py and kde.py:
  ../../.venv-tf/Scripts/python export_live.py
"""

import json
from pathlib import Path

import numpy as np

from prepare_windows import (
    FEATURES,
    HAZARDS,
    WINDOW,
    clean_incidents,
    daily_counts,
    daily_features,
    load_weather,
    read_csv,
)
from run_forecast import RULE

HERE = Path(__file__).parent
BUILD = HERE / "build"
OUT = HERE.parent.parent / "supabase" / "data" / "forecast_live_v1.json"
VERSION = "lstm-kde-v1"


def r(x, digits=7):
    """Floats as JSON numbers with float32's precision."""
    return [float(f"{v:.{digits}g}") for v in np.asarray(x, dtype=float).ravel()]


def lstm_layer(layer):
    c = layer.get_config()
    assert c["activation"] == "tanh" and c["recurrent_activation"] == "sigmoid"
    assert c["use_bias"] and not c["go_backwards"]
    kernel, recurrent, bias = layer.get_weights()
    return {
        "units": c["units"],
        "return_sequences": c["return_sequences"],
        "kernel": r(kernel),  # [inputs][4 * units], row-major
        "recurrent": r(recurrent),  # [units][4 * units]
        "bias": r(bias),
    }


def export_model(model):
    lstms = [l for l in model.layers if type(l).__name__ == "LSTM"]
    dense = [l for l in model.layers if type(l).__name__ == "Dense"]
    assert len(lstms) == 2 and len(dense) == 1
    w, b = dense[0].get_weights()
    return {
        "layers": [lstm_layer(l) for l in lstms],
        "dense": {"weights": r(w), "bias": r(b)},
    }


def main():
    import tensorflow as tf

    days, weather = load_weather(read_csv(HERE / "data" / "sample_weather_daily.csv"))
    incidents, _ = clean_incidents(
        read_csv(HERE / "data" / "sample_incidents.csv"), days[0], days[-1]
    )
    kde = json.loads((HERE / "kde_summary.json").read_text(encoding="utf-8"))
    floor = min(
        [RULE["high"]["density"]] + [m["density"] for m in RULE["moderate"]]
    )

    hazards = {}
    vectors = []
    checks = [days.index(days[-1]), len(days) // 2, WINDOW + 40]
    for hazard in HAZARDS:
        data = np.load(BUILD / f"windows_{hazard}.npz")
        model = tf.keras.models.load_model(BUILD / f"lstm_{hazard}.keras")
        counts = daily_counts(days, incidents, hazard)
        features = daily_features(weather, counts)
        mean, std = data["scaler_mean"], data["scaler_std"]
        scored = kde["hazards"][hazard]["barangays"]
        hazards[hazard] = {
            "scaler_mean": r(mean),
            "scaler_std": r(std),
            "prior_day_incidents": [int(v) for v in features[:, 5]],
            "model": export_model(model),
            "density": {
                name: round(b["relative"], 4)
                for name, b in sorted(scored.items())
                if b["relative"] >= floor
            },
        }
        for end in checks:
            x = (features[end - WINDOW + 1 : end + 1] - mean) / std
            p = float(model.predict(x[np.newaxis, ...], verbose=0).ravel()[0])
            vectors.append({"hazard": hazard, "window_end": days[end].isoformat(), "probability": p})

    out = {
        "version": VERSION,
        "data": "SAMPLE (made up by make_sample_data.py); nothing here is a result",
        "features": list(FEATURES),
        "window": WINDOW,
        "horizon_hours": 72,
        "rule": RULE,
        "days": [d.isoformat() for d in days],
        "weather": [r(row, 6) for row in weather],
        "hazards": hazards,
        "test_vectors": vectors,
    }
    OUT.write_text(json.dumps(out, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
