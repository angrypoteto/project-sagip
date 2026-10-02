"""Checks for the forecast data preparation and the KDE.

Run with: python -m unittest discover -s ml/forecast -p "test_*.py"
"""

import importlib.util
import math
import unittest
from datetime import date, timedelta

import numpy as np

import kde
import prepare_windows as prep


def weather_rows(days, rain=None):
    start = date(2024, 1, 1)
    return [
        {
            "date": (start + timedelta(days=i)).isoformat(),
            "rainfall_total_mm": str((rain or {}).get(i, 0)),
            "rainfall_max_hourly_mm": "0",
            "typhoon_signal": "0",
            "max_wind_kph": "10",
            "storm_surge_m": "0",
        }
        for i in range(days)
    ]


def incident(day_index, hazard="flood", lat=14.60, lng=120.99):
    return {
        "date": (date(2024, 1, 1) + timedelta(days=day_index)).isoformat(),
        "hazard": hazard,
        "latitude": str(lat),
        "longitude": str(lng),
    }


class DataPreparation(unittest.TestCase):
    def test_weather_must_be_complete_and_in_range(self):
        rows = weather_rows(30)
        days, values = prep.load_weather(rows)
        self.assertEqual(len(days), 30)
        self.assertEqual(values.shape, (30, 5))

        with self.assertRaisesRegex(prep.DataError, "2024-01-11 has no weather record"):
            prep.load_weather(rows[:10] + rows[11:])
        with self.assertRaisesRegex(prep.DataError, "appears twice"):
            prep.load_weather(rows + rows[:1])
        bad = [dict(r) for r in rows]
        bad[3]["typhoon_signal"] = "7"
        with self.assertRaisesRegex(prep.DataError, "typhoon_signal = 7.0 is outside 0 to 5"):
            prep.load_weather(bad)
        bad[3]["typhoon_signal"] = ""
        with self.assertRaisesRegex(prep.DataError, "missing or not a number"):
            prep.load_weather(bad)

    def test_cleaning_counts_what_it_removes(self):
        rows = [
            incident(5),
            incident(5),  # the same record twice
            incident(5, lat=14.6005),  # another incident the same day
            incident(6, hazard="Storm Surge"),  # spelling is tidied
            incident(7, hazard="landslide"),
            incident(8, lat=14.40, lng=121.20),  # outside Manila
            incident(400),  # after the weather ends
            {"date": "soon", "hazard": "fire", "latitude": "14.6", "longitude": "120.99"},
            {"date": "2024-01-03", "hazard": "fire", "latitude": "", "longitude": "120.99"},
        ]
        kept, log = prep.clean_incidents(rows, date(2024, 1, 1), date(2024, 1, 30))
        self.assertEqual(
            log,
            {
                "read": 9,
                "removed_unreadable_date": 1,
                "removed_outside_period": 1,
                "removed_unknown_hazard": 1,
                "removed_bad_coordinates": 1,
                "removed_outside_manila": 1,
                "removed_duplicates": 1,
                "kept": 3,
            },
        )
        self.assertEqual([r["hazard"] for r in kept], ["flood", "flood", "storm_surge"])

    def test_features_and_labels_line_up(self):
        counts = np.zeros(40)
        counts[20] = 2
        counts[30] = 1
        weather = np.arange(40 * 5, dtype=float).reshape(40, 5)

        features = prep.daily_features(weather, counts)
        self.assertEqual(features.shape, (40, 6))
        # "Prior-day incident count": day 21 carries the count of day 20.
        self.assertEqual(features[21, 5], 2)
        self.assertEqual(features[20, 5], 0)
        self.assertEqual(features[0, 5], 0)

        label = prep.labels(counts)
        # An incident on day 20 is "within the next 72 hours" on days 17 to 19.
        self.assertEqual([t for t in range(40) if label[t] == 1], [17, 18, 19, 27, 28, 29])
        self.assertEqual(list(label[-3:]), [-1, -1, -1], "no full horizon at the end")

        x, y, ends = prep.build_windows(features, label)
        self.assertEqual(x.shape, (40 - 14 - 3, 14, 6))
        self.assertEqual(ends[0], 14)
        self.assertEqual(ends[-1], 36)
        # The window ending on day 19 holds days 6 to 19 and is labelled 1.
        i = list(ends).index(19)
        self.assertTrue(np.array_equal(x[i], features[6:20]))
        self.assertEqual(y[i], 1)
        # Nothing in that window knows about day 20's incidents.
        self.assertEqual(x[i][:, 5].sum(), 0)

    def test_split_is_in_time_order_with_a_gap(self):
        train, val, test = prep.split_in_time(1000)
        self.assertEqual(train, (0, 697))
        self.assertEqual(val, (700, 847))
        self.assertEqual(test, (850, 1000))

    def test_scaler_and_class_weights_use_training_only(self):
        x = np.zeros((10, 14, 6))
        x[:, :, 0] = 4.0
        x[:5, :, 1] = 2.0
        mean, std = prep.fit_scaler(x)
        self.assertEqual(mean[0], 4.0)
        self.assertEqual(std[0], 1.0, "a constant feature is left as it is")
        self.assertEqual(mean[1], 1.0)
        self.assertEqual(std[1], 1.0)

        weights = prep.class_weights(np.array([1, 0, 0, 0]))
        self.assertEqual(weights, {"0": 0.6667, "1": 2.0})
        self.assertIsNone(prep.class_weights(np.array([0, 0, 0])))

    def test_scores(self):
        y = np.array([1, 1, 0, 0])
        s = prep.scores(y, np.array([0.9, 0.2, 0.6, 0.1]))
        self.assertEqual(s["confusion"], {"tp": 1, "fp": 1, "fn": 1, "tn": 1})
        self.assertEqual((s["accuracy"], s["precision"], s["recall"], s["f1"]), (0.5, 0.5, 0.5, 0.5))
        self.assertAlmostEqual(s["rmse"], math.sqrt((0.01 + 0.64 + 0.36 + 0.01) / 4), places=4)

    def test_the_whole_preparation(self):
        # 200 days; it rains hard every 10th day and floods the day after.
        rain = {i: 80 for i in range(0, 200, 10)}
        incidents = [incident(i + 1) for i in range(0, 190, 10)]
        summary = prep.prepare(weather_rows(200, rain), incidents)
        flood = summary["hazards"]["flood"]
        self.assertEqual(summary["days"], 200)
        self.assertEqual(flood["incidents"], 19)
        self.assertEqual(flood["windows"], 200 - 14 - 3)
        parts = flood["parts"]
        self.assertEqual(
            [parts[p]["windows"] for p in ("train", "validation", "test")],
            [125, 24, 28],
        )
        self.assertLess(parts["train"]["last_window_ends"], parts["validation"]["first_window_ends"])
        self.assertLess(parts["validation"]["last_window_ends"], parts["test"]["first_window_ends"])
        # Three days in ten are within 72 hours before a flood.
        self.assertAlmostEqual(parts["train"]["positive_rate"], 0.3, delta=0.02)
        self.assertAlmostEqual(flood["class_weights"]["1"], 1 / (2 * 0.3), delta=0.1)
        # A hazard that never happened has no positives and no weights.
        self.assertIsNone(summary["hazards"]["fire"]["class_weights"])
        self.assertEqual(summary["hazards"]["fire"]["parts"]["test"]["positives"], 0)
        # The pattern is regular, so the baseline that sees the whole window
        # finds every flood, where the simpler ones find none.
        test = flood["baselines"]["test"]
        self.assertEqual(test["logistic_regression"]["recall"], 1.0)
        self.assertGreater(test["logistic_regression"]["f1"], 0.7)
        self.assertEqual(test["always_majority"]["recall"], 0.0)
        self.assertEqual(test["persistence"]["f1"], 0.0)


class Kde(unittest.TestCase):
    def cluster(self, n=400, spread_m=250, seed=1):
        rng = np.random.default_rng(seed)
        lat0, lng0 = 14.6000, 120.9900
        north = rng.normal(0, spread_m, n)
        east = rng.normal(0, spread_m, n)
        lat = lat0 + np.degrees(north / kde.EARTH_RADIUS_M)
        lng = lng0 + np.degrees(east / (kde.EARTH_RADIUS_M * math.cos(math.radians(lat0))))
        return np.column_stack([lat, lng])

    def test_haversine(self):
        self.assertAlmostEqual(kde.haversine_m(14.0, 121.0, 15.0, 121.0), 111_195, delta=5)
        self.assertEqual(kde.haversine_m(14.6, 120.99, 14.6, 120.99), 0)
        # One degree of longitude is shorter away from the equator.
        self.assertAlmostEqual(
            kde.haversine_m(14.6, 120.0, 14.6, 121.0),
            111_195 * math.cos(math.radians(14.6)),
            delta=20,
        )

    def test_bandwidth_comes_from_the_list_by_held_out_likelihood(self):
        tight = self.cluster(spread_m=120)
        best, means = kde.select_bandwidth(tight)
        self.assertEqual(sorted(means), [100, 200, 300, 400, 500])
        self.assertEqual(best, max(means, key=means.get))
        self.assertEqual(best, 100)
        # Widely scattered incidents are better described by a wider kernel.
        rng = np.random.default_rng(3)
        scattered = np.column_stack([rng.uniform(14.56, 14.63, 60), rng.uniform(120.96, 121.02, 60)])
        self.assertEqual(kde.select_bandwidth(scattered)[0], 500)
        # The same data and seed give the same answer.
        self.assertEqual(kde.select_bandwidth(tight), (best, means))
        with self.assertRaises(ValueError):
            kde.select_bandwidth(tight[:8])

    def test_grid_is_100_m(self):
        grid = kde.make_grid()
        lats = np.unique(grid[:, 0])
        lngs = np.unique(grid[:, 1])
        self.assertEqual(len(grid), len(lats) * len(lngs))
        self.assertAlmostEqual(kde.haversine_m(lats[0], lngs[0], lats[1], lngs[0]), 100, delta=0.5)
        self.assertAlmostEqual(kde.haversine_m(lats[70], lngs[0], lats[70], lngs[1]), 100, delta=0.5)
        box = kde.MANILA_BOX
        self.assertTrue((grid[:, 0] > box["south"]).all() and (grid[:, 0] < box["north"]).all())
        self.assertTrue((grid[:, 1] > box["west"]).all() and (grid[:, 1] < box["east"]).all())

    def test_density_is_in_incidents_per_square_kilometre(self):
        points = self.cluster(n=400, spread_m=250)
        grid = kde.make_grid()
        density = kde.density_per_km2(points, grid, 200)
        # Added up over the grid, the surface holds the incidents.
        self.assertAlmostEqual(density.sum() * 0.01, 400, delta=4)
        # Densest at the centre of the cluster, almost nothing 3 km away.
        peak = grid[int(density.argmax())]
        self.assertLess(kde.haversine_m(peak[0], peak[1], 14.6000, 120.9900), 150)
        far = kde.haversine_m(14.6000, 120.9900, grid[:, 0], grid[:, 1]) > 3000
        self.assertLess(density[far].max(), 0.01)
        # A Gaussian cluster of 400 with a 250 m spread, smoothed by 200 m,
        # peaks near n / (2 pi (250^2 + 200^2)) per square metre.
        expected = 400 / (2 * math.pi * (0.25**2 + 0.20**2))
        self.assertAlmostEqual(density.max(), expected, delta=expected * 0.15)

    def test_average_per_barangay_by_centre_and_by_boundary(self):
        points = self.cluster(n=400, spread_m=250)
        grid = kde.make_grid()
        density = kde.density_per_km2(points, grid, 200)
        barangays = [
            {"name": "At the cluster", "district": "X", "latitude": 14.6000, "longitude": 120.9900},
            {"name": "One km north", "district": "X", "latitude": 14.6090, "longitude": 120.9900},
        ]
        by_centre = kde.average_per_barangay(grid, density, barangays)
        near, away = by_centre["At the cluster"], by_centre["One km north"]
        self.assertEqual((near["rank"], away["rank"]), (1, 2))
        self.assertEqual(near["relative"], 1.0)
        self.assertLess(away["relative"], 0.1)
        self.assertEqual(near["area"], "within 400 m of the centre")
        # About pi * 400^2 / 100^2 cells.
        self.assertAlmostEqual(near["cells"], 50, delta=4)

        # With a boundary: a 300 m square around the cluster's centre.
        dlat = math.degrees(150 / kde.EARTH_RADIUS_M)
        dlng = dlat / math.cos(math.radians(14.6))
        square = [
            [120.99 - dlng, 14.6 - dlat], [120.99 + dlng, 14.6 - dlat],
            [120.99 + dlng, 14.6 + dlat], [120.99 - dlng, 14.6 + dlat],
            [120.99 - dlng, 14.6 - dlat],
        ]
        boundaries = {"At the cluster": {"type": "Polygon", "coordinates": [square]}}
        by_boundary = kde.average_per_barangay(grid, density, barangays, boundaries)
        inside = by_boundary["At the cluster"]
        self.assertEqual(inside["area"], "boundary")
        self.assertEqual(inside["cells"], 9)
        self.assertGreater(inside["mean_per_km2"], near["mean_per_km2"], "a smaller area nearer the peak")
        self.assertEqual(by_boundary["One km north"]["area"], "within 400 m of the centre")

    def test_boundaries_with_holes_and_several_parts(self):
        grid = np.array([[0.5, 0.5], [0.5, 2.5], [0.5, 5.0], [0.1, 0.1]])
        outer = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]
        hole = [[0.4, 0.4], [0.6, 0.4], [0.6, 0.6], [0.4, 0.6], [0.4, 0.4]]
        second = [[2, 0], [3, 0], [3, 1], [2, 1], [2, 0]]
        self.assertEqual(
            list(kde.inside_geometry(grid, {"type": "Polygon", "coordinates": [outer]})),
            [True, False, False, True],
        )
        self.assertEqual(
            list(kde.inside_geometry(grid, {"type": "Polygon", "coordinates": [outer, hole]})),
            [False, False, False, True],
        )
        self.assertEqual(
            list(kde.inside_geometry(grid, {"type": "MultiPolygon", "coordinates": [[outer, hole], [second]]})),
            [False, True, False, True],
        )



@unittest.skipUnless(
    importlib.util.find_spec("tensorflow"),
    "TensorFlow is not installed (it runs in .venv-tf, Python 3.12)",
)
class Lstm(unittest.TestCase):
    def test_the_architecture_follows_the_thesis(self):
        import tensorflow as tf

        import train_lstm

        model = train_lstm.build_model(14, 6)
        kinds = [type(layer).__name__ for layer in model.layers]
        self.assertEqual(kinds, ["LSTM", "Dropout", "LSTM", "Dropout", "Dense"])
        first, drop1, second, drop2, out = model.layers
        self.assertEqual((first.units, first.return_sequences), (64, True))
        self.assertEqual((second.units, second.return_sequences), (32, False))
        self.assertEqual((drop1.rate, drop2.rate), (0.2, 0.2))
        self.assertEqual((out.units, out.activation.__name__), (1, "sigmoid"))
        self.assertEqual(model.input_shape, (None, 14, 6))
        self.assertAlmostEqual(float(model.optimizer.learning_rate.numpy()), 0.001, places=7)
        self.assertEqual(model.loss, "binary_crossentropy")
        self.assertEqual(
            (train_lstm.BATCH, train_lstm.MAX_EPOCHS, train_lstm.PATIENCE), (32, 100, 10)
        )
        tf.keras.backend.clear_session()

    def test_the_phone_copy_gives_the_same_answers(self):
        import tensorflow as tf

        import train_lstm

        tf.keras.utils.set_random_seed(1)
        model = train_lstm.build_model(14, 6)
        x = np.random.default_rng(2).normal(size=(6, 14, 6)).astype(np.float32)
        copy = train_lstm.inference_copy(model, 14, 6)
        for i in range(len(x)):
            self.assertAlmostEqual(
                float(copy(x[i : i + 1], training=False)[0][0]),
                float(model(x[i : i + 1], training=False)[0][0]),
                places=5,
            )
        tf.keras.backend.clear_session()


if __name__ == "__main__":
    unittest.main()
