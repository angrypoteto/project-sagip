// Helpers for the road-conditions Edge Function: the TomTom request and
// turning its answer into the rows save_road_conditions() takes. Pure
// functions, tested with Node (roads.test.ts).

/** A box around Manila (lng, lat); the database keeps only roads touching the city. */
export const manilaBox = "120.94,14.55,121.03,14.645";

const fields =
  "{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay," +
  "events{description,iconCategory},from,to,length,delay,roadNumbers,startTime}}}";

/** TomTom Traffic Incidents (v5): what is happening now inside [box]. */
export function incidentsUrl(key: string, box = manilaBox): string {
  return `https://api.tomtom.com/traffic/services/5/incidentDetails?bbox=${box}` +
    `&fields=${encodeURIComponent(fields)}&language=en-GB&timeValidityFilter=present` +
    `&key=${encodeURIComponent(key)}`;
}

export type RoadKind = "jam" | "closed" | "flooding";

/** One row for save_road_conditions(). */
export interface RoadItem {
  id: string;
  kind: RoadKind;
  severity: number;
  road: string | null;
  from: string | null;
  to: string | null;
  delay: number | null;
  length: number | null;
  since: string | null;
  path: [number, number][];
}

// TomTom's icon categories the maps show.
const JAM = 6, CLOSED = 8, FLOODING = 11;

function text(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim().slice(0, 200) : null;
}

function whole(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.round(v) : null;
}

function point(v: unknown): [number, number] | null {
  if (!Array.isArray(v) || v.length < 2) return null;
  const [lng, lat] = v;
  if (typeof lng !== "number" || typeof lat !== "number") return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return [Math.round(lng * 1e6) / 1e6, Math.round(lat * 1e6) / 1e6];
}

/**
 * Jams, closed roads, and flooded roads from TomTom's answer. A report
 * whose events mention flooding counts as flooding even when TomTom files
 * it as a closure. Everything else (accidents, road works, lane closures)
 * is left out. A single point becomes a two-point line.
 */
export function roadItems(body: unknown): RoadItem[] {
  const list = (body as { incidents?: unknown })?.incidents;
  if (!Array.isArray(list)) return [];
  const out: RoadItem[] = [];
  for (const i of list) {
    const p = (i as { properties?: Record<string, unknown> })?.properties;
    const g = (i as { geometry?: { type?: unknown; coordinates?: unknown } })?.geometry;
    if (!p || !g) continue;
    const id = text(p.id);
    if (!id) continue;
    const events = Array.isArray(p.events) ? p.events as Record<string, unknown>[] : [];
    const flooded = p.iconCategory === FLOODING ||
      events.some((e) => e?.iconCategory === FLOODING || /flood/i.test(String(e?.description ?? "")));
    const kind: RoadKind | null = flooded
      ? "flooding"
      : p.iconCategory === CLOSED
      ? "closed"
      : p.iconCategory === JAM
      ? "jam"
      : null;
    if (!kind) continue;
    let path: [number, number][] = [];
    if (g.type === "LineString" && Array.isArray(g.coordinates)) {
      path = g.coordinates.map(point).filter((c): c is [number, number] => c !== null);
    } else if (g.type === "Point") {
      const c = point(g.coordinates);
      if (c) path = [c, c];
    }
    if (path.length < 2) continue;
    const severity = whole(p.magnitudeOfDelay);
    const roads = Array.isArray(p.roadNumbers)
      ? (p.roadNumbers as unknown[]).map(text).filter((r): r is string => r !== null)
      : [];
    out.push({
      id,
      kind,
      severity: severity !== null && severity <= 4 ? severity : 0,
      road: roads.length ? roads.join(", ").slice(0, 200) : null,
      from: text(p.from),
      to: text(p.to),
      delay: whole(p.delay),
      length: whole(p.length),
      since: text(p.startTime),
      path,
    });
  }
  return out;
}
