# Forecast: 72-hour disaster risk heatmap (FR4, Objective 2)

Two machine learning models make the forecast. Each has its own folder:

| Folder | Model | What it answers |
|---|---|---|
| `lstm/` | **LSTM** (Long Short-Term Memory neural network) | **When:** the chance of at least one flood, fire, or storm surge incident in the City of Manila in the next 72 hours, from the last 14 days of weather and incidents |
| `kde/` | **KDE** (Kernel Density Estimation) | **Where:** how incidents of each hazard spread over the 897 barangays, from where past incidents happened |
| `heatmap/` | LSTM + KDE together | The **heatmap**: each barangay's risk level (low, moderate, high) for the next 72 hours, and how accurate that is |
| `data_prep/` | (no model) | Getting and preparing the records both models learn from: cleaning, geocoding, and time-aligning, with the number of records retained, corrected, and removed at each step |

Shared by all four:

- `data/`: the input records (weather, incidents, UP NOAH hazard shares). `data/noah/` holds UP NOAH's maps as downloaded and is git-ignored.
- `build/`: trained models and windows (git-ignored).
- `test_forecast.py`: the checks for all of it (`python -m unittest test_forecast`, run from this folder).

Every script runs from the repo root or from here, for example `../../.venv-tf/Scripts/python lstm/train_lstm.py`. Details, data sources, and results: `ml/README.md` and `docs/OBJECTIVE-2-RESULTS.md`.
