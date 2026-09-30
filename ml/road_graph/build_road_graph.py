"""Builds the directed Manila road graph for Dijkstra (plan 10.2, FR3).

Nodes are intersections and dead ends; edges are road segments between them,
one per allowed direction (one-way streets have one edge). The edge weight is
the estimated travel time: length divided by a speed for the road class
(thesis algorithm parameters; plan Q19).

Output: packages/shared/assets/road_graph/manila_drive_v1.bin, read by
`RoadGraph.decode` in packages/shared/lib/src/algorithms/road_graph.dart.
The format is described in FORMAT below and in that file.

Run (about a minute; needs internet for OpenStreetMap's Overpass API):

    python -m venv .venv
    .venv/Scripts/python -m pip install -r ml/requirements-road-graph.txt
    .venv/Scripts/python ml/road_graph/build_road_graph.py

Then run ml/road_graph/make_reference.py to refresh the test fixture.
Map data (c) OpenStreetMap contributors, ODbL 1.0.
"""

from __future__ import annotations

import datetime as dt
import struct
import sys
from pathlib import Path

import osmnx as ox

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "packages" / "shared" / "assets" / "road_graph" / "manila_drive_v1.bin"

PLACE = "Manila, Metro Manila, Philippines"
# Units and routes cross the city line (stations near the border, the
# shortest way round a closed road), so the graph reaches a little past it.
BUFFER_M = 1500

FORMAT_VERSION = 1

# Speeds per OSM road class in km/h. Provisional values for an emergency
# vehicle in Manila traffic; tune them with MDRRMD's dispatch records (thesis
# Table 3.1 item 2). OSM maxspeed tags are ignored: they are legal limits,
# not the speeds reached in the city.
SPEED_KMH = {
    "motorway": 60,
    "trunk": 40,
    "primary": 35,
    "secondary": 30,
    "tertiary": 25,
    "unclassified": 20,
    "residential": 15,
    "living_street": 10,
    "road": 15,
    "busway": 30,
}
DEFAULT_SPEED_KMH = 15

# Road class codes stored per edge (for later penalties, such as roads inside
# a flooded area). Links share their parent's code.
CLASS_CODE = {
    "motorway": 1,
    "trunk": 2,
    "primary": 3,
    "secondary": 4,
    "tertiary": 5,
    "unclassified": 6,
    "residential": 7,
    "living_street": 8,
}
OTHER_CLASS = 9

FORMAT = """
All numbers little-endian.
  magic        8 bytes  "SAGIPRG1"
  version      uint32   1
  built        uint32   build date as YYYYMMDD
  nodeCount    uint32   N
  edgeCount    uint32   M
  nameCount    uint32   K
  geomCount    uint32   G   (shape points inside edges)
  nodes        N x (int32 lat, int32 lng), microdegrees
  offsets      (N + 1) x uint32; node i's edges are offsets[i] .. offsets[i+1]-1
  targets      M x uint32
  seconds      M x float32   travel time
  meters       M x float32   length
  name         M x uint16    index into names, 0xFFFF for none
  roadClass    M x uint8     CLASS_CODE
  geomOffsets  (M + 1) x uint32
  geom         G x (int32 lat, int32 lng), the edge's shape between its ends
  names        K x (uint16 byteLength, UTF-8 bytes)
"""


def first(value):
    """OSM tags on merged edges can be lists; take the first."""
    if isinstance(value, list):
        return value[0] if value else None
    return value


def road_class(highway) -> str:
    h = first(highway) or "road"
    return h.removesuffix("_link")


def main() -> None:
    ox.settings.use_cache = True
    ox.settings.log_console = False

    boundary = ox.geocode_to_gdf(PLACE)
    projected = ox.projection.project_gdf(boundary)
    buffered = projected.buffer(BUFFER_M).to_crs(boundary.crs).iloc[0]

    graph = ox.graph_from_polygon(
        buffered, network_type="drive", simplify=True, retain_all=True
    )
    # Every intersection must reach every other one, or Dijkstra would find
    # no way out of a one-way dead end.
    graph = ox.truncate.largest_component(graph, strongly=True)

    node_ids = sorted(graph.nodes)
    index = {n: i for i, n in enumerate(node_ids)}

    names: list[str] = []
    name_index: dict[str, int] = {}

    def name_of(data) -> int:
        n = first(data.get("name"))
        if not n:
            return 0xFFFF
        n = str(n).strip()
        if n not in name_index:
            name_index[n] = len(names)
            names.append(n)
        return name_index[n]

    # Edges grouped by their start node (CSR). Parallel edges between the
    # same two nodes keep only the fastest.
    best: dict[tuple[int, int], dict] = {}
    for u, v, data in graph.edges(data=True):
        if u == v:
            continue
        cls = road_class(data.get("highway"))
        length = float(data["length"])
        seconds = length / (SPEED_KMH.get(cls, DEFAULT_SPEED_KMH) / 3.6)
        key = (index[u], index[v])
        if key in best and best[key]["seconds"] <= seconds:
            continue
        geom = data.get("geometry")
        shape = list(geom.coords)[1:-1] if geom is not None else []
        best[key] = {
            "seconds": seconds,
            "meters": length,
            "name": name_of(data),
            "class": CLASS_CODE.get(cls, OTHER_CLASS),
            "shape": [(lat, lng) for (lng, lat) in shape],
        }

    if len(names) >= 0xFFFF:
        sys.exit("Too many street names for a uint16 index.")

    edges = sorted(best.items())
    n, m = len(node_ids), len(edges)
    offsets = [0] * (n + 1)
    for (u, _), _ in edges:
        offsets[u + 1] += 1
    for i in range(n):
        offsets[i + 1] += offsets[i]

    geom_offsets = [0]
    geom: list[tuple[float, float]] = []
    for _, e in edges:
        geom.extend(e["shape"])
        geom_offsets.append(len(geom))

    def micro(x: float) -> int:
        return round(x * 1_000_000)

    built = int(dt.date.today().strftime("%Y%m%d"))
    out = bytearray()
    out += b"SAGIPRG1"
    out += struct.pack("<6I", FORMAT_VERSION, built, n, m, len(names), len(geom))
    for node in node_ids:
        d = graph.nodes[node]
        out += struct.pack("<ii", micro(d["y"]), micro(d["x"]))
    out += struct.pack(f"<{n + 1}I", *offsets)
    out += struct.pack(f"<{m}I", *(v for (_, v), _ in edges))
    out += struct.pack(f"<{m}f", *(e["seconds"] for _, e in edges))
    out += struct.pack(f"<{m}f", *(e["meters"] for _, e in edges))
    out += struct.pack(f"<{m}H", *(e["name"] for _, e in edges))
    out += struct.pack(f"<{m}B", *(e["class"] for _, e in edges))
    out += struct.pack(f"<{m + 1}I", *geom_offsets)
    for lat, lng in geom:
        out += struct.pack("<ii", micro(lat), micro(lng))
    for name in names:
        raw = name.encode("utf-8")
        out += struct.pack("<H", len(raw)) + raw

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(bytes(out))
    print(
        f"{n} intersections, {m} road segments, {len(names)} street names, "
        f"{len(geom)} shape points: {len(out) / 1024:.0f} KB -> {OUT.relative_to(ROOT)}"
    )


if __name__ == "__main__":
    main()
