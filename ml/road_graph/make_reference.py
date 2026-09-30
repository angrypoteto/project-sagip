"""Reference answers for the Dart Dijkstra test (plan 10.2: "test against a
reference library (networkx) on 50 random origin and destination pairs;
results must match").

Reads the exported graph file itself, so both sides use exactly the same
float32 travel times, and writes
packages/shared/test/fixtures/road_graph_reference.json.

    .venv/Scripts/python ml/road_graph/make_reference.py
"""

from __future__ import annotations

import json
import random
import struct
from pathlib import Path

import networkx as nx

ROOT = Path(__file__).resolve().parents[2]
GRAPH = ROOT / "packages" / "shared" / "assets" / "road_graph" / "manila_drive_v1.bin"
OUT = ROOT / "packages" / "shared" / "test" / "fixtures" / "road_graph_reference.json"

PAIRS = 50
SEED = 20260930


def read_graph(raw: bytes) -> tuple[nx.DiGraph, int]:
    assert raw[:8] == b"SAGIPRG1"
    _version, _built, n, m, _k, _g = struct.unpack_from("<6I", raw, 8)
    pos = 8 + 24 + n * 8
    offsets = struct.unpack_from(f"<{n + 1}I", raw, pos)
    pos += (n + 1) * 4
    targets = struct.unpack_from(f"<{m}I", raw, pos)
    pos += m * 4
    seconds = struct.unpack_from(f"<{m}f", raw, pos)
    graph = nx.DiGraph()
    graph.add_nodes_from(range(n))
    for u in range(n):
        for e in range(offsets[u], offsets[u + 1]):
            graph.add_edge(u, targets[e], seconds=seconds[e])
    return graph, n


def main() -> None:
    graph, n = read_graph(GRAPH.read_bytes())
    rng = random.Random(SEED)

    pairs = []
    for _ in range(PAIRS):
        s, t = rng.randrange(n), rng.randrange(n)
        seconds, path = nx.single_source_dijkstra(graph, s, t, weight="seconds")
        pairs.append({"from": s, "to": t, "seconds": seconds, "hops": len(path) - 1})

    # One-to-many on the reversed graph: the travel time from each of several
    # places to one incident, as the unit suggestions compute it.
    incident = rng.randrange(n)
    starts = [rng.randrange(n) for _ in range(8)]
    to_incident = nx.single_source_dijkstra_path_length(
        graph.reverse(copy=False), incident, weight="seconds"
    )
    many = {
        "incident": incident,
        "units": [{"from": s, "seconds": to_incident[s]} for s in starts],
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "source": "networkx " + nx.__version__ + ", " + GRAPH.name,
                "seed": SEED,
                "pairs": pairs,
                "toIncident": many,
            },
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"{len(pairs)} pairs and {len(starts)} units -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
