// The typhoon tracker's parsing (2026-11-02): GDACS tropical cyclones and
// PAGASA's CAP alerts turned into the rows `save_hazard_feeds` takes. Pure
// functions, tested with Node (parse.test.ts).
//
// Points are stored as [lat, lng] (as the dashboard draws them); GeoJSON
// gives [lng, lat], CAP gives "lat,lng".

// ------------------------------------------------------------------ shapes

export type LatLng = [number, number];

/** The Philippine Area of Responsibility (PAGASA), as [lat, lng]. */
export const par: LatLng[] = [
  [5, 115],
  [15, 115],
  [21, 120],
  [25, 120],
  [25, 135],
  [5, 135],
];

/** Whether [p] lies inside [ring] (ray casting; [lat, lng] both). */
export function inside(p: LatLng, ring: LatLng[]): boolean {
  let hit = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [yi, xi] = ring[i];
    const [yj, xj] = ring[j];
    if (yi > p[0] !== yj > p[0] && p[1] < ((xj - xi) * (p[0] - yi)) / (yj - yi) + xi) {
      hit = !hit;
    }
  }
  return hit;
}

const round = (v: number) => Math.round(v * 1000) / 1000;

/**
 * [ring] with points closer than [step] degrees to the last kept one
 * dropped, rounded to 3 decimals: GDACS draws a circle with hundreds of
 * points, more than a map of the Philippines needs.
 */
export function simplify(ring: LatLng[], step: number): LatLng[] {
  if (ring.length < 4) return ring.map(([a, b]) => [round(a), round(b)]);
  const out: LatLng[] = [ring[0]];
  for (let i = 1; i < ring.length - 1; i++) {
    const [a, b] = out[out.length - 1];
    if (Math.abs(ring[i][0] - a) >= step || Math.abs(ring[i][1] - b) >= step) out.push(ring[i]);
  }
  out.push(ring[ring.length - 1]);
  return (out.length < 4 ? ring : out).map(([a, b]) => [round(a), round(b)]);
}

/** The outer rings of a GeoJSON Polygon or MultiPolygon, as [lat, lng]. */
function outerRings(geometry: { type: string; coordinates: unknown }): LatLng[][] {
  const flip = (ring: number[][]): LatLng[] => ring.map(([lng, lat]) => [lat, lng]);
  if (geometry.type === "Polygon") {
    const rings = geometry.coordinates as number[][][];
    return rings.length ? [flip(rings[0])] : [];
  }
  if (geometry.type === "MultiPolygon") {
    return (geometry.coordinates as number[][][][]).filter((p) => p.length).map((p) => flip(p[0]));
  }
  return [];
}

// ------------------------------------------------------------------ GDACS

export interface Feature {
  geometry: { type: string; coordinates: unknown };
  properties: Record<string, unknown>;
}

export interface TrackPoint {
  t: string;
  lat: number;
  lng: number;
  category: string | null;
  forecast: boolean;
}

export interface StormRow {
  event_id: number;
  episode_id: number;
  name: string;
  alert_level: string;
  is_current: boolean;
  from_at: string;
  to_at: string;
  updated_at: string | null;
  max_wind_kmh: number | null;
  source: string | null;
  track: TrackPoint[];
  wind_zones: { kmh: number; rings: LatLng[][] }[];
  cone: LatLng[][];
}

/** GDACS gives UTC times without a zone. */
const utc = (s: unknown) => (typeof s === "string" && s ? (/[Zz]|[+-]\d\d:?\d\d$/.test(s) ? s : `${s}Z`) : null);

/**
 * The cyclones of a GDACS event list worth fetching: those GDACS says
 * touch the Philippines, or whose centre is over the western Pacific
 * (one still far out may be heading here). Newest first, at most [limit].
 */
export function candidates(list: { features?: Feature[] }, limit = 8): Feature[] {
  const out = (list.features ?? []).filter((f) => {
    const p = f.properties;
    if (p.eventtype !== "TC") return false;
    const countries = (p.affectedcountries as { iso3?: string }[] | undefined) ?? [];
    if (countries.some((c) => c.iso3 === "PHL")) return true;
    if (f.geometry?.type !== "Point") return false;
    const [lng, lat] = f.geometry.coordinates as number[];
    return lng >= 100 && lng <= 160 && lat >= -5 && lat <= 40;
  });
  out.sort((a, b) => String(b.properties.todate).localeCompare(String(a.properties.todate)));
  return out.slice(0, limit);
}

/** "14/10 12:00 UTC" as an ISO time, its year taken from [from]. */
export function labelTime(label: string, from: string): string | null {
  const m = /^(\d\d)\/(\d\d) (\d\d):(\d\d)/.exec(label.trim());
  if (!m) return null;
  const start = new Date(from);
  let year = start.getUTCFullYear();
  const month = Number(m[2]);
  // A storm that starts in December and runs into January.
  if (month < start.getUTCMonth() + 1) year += 1;
  const t = new Date(Date.UTC(year, month - 1, Number(m[1]), Number(m[3]), Number(m[4])));
  return Number.isNaN(t.getTime()) ? null : t.toISOString();
}

/**
 * One cyclone from its GDACS event properties and geometry (the
 * `getgeometry` FeatureCollection), or null when no position of its track,
 * past or forecast, is inside PAR.
 *
 * GDACS draws each position as a small circle labelled with its time
 * ("Point_Polygon_Point_N"), each leg of the track as a line labelled with
 * its category ("Line_Line_N"; TD, TS, TY, ...), the 60, 90, and 120 km/h
 * wind zones ("Poly_Green", "Poly_Orange", "Poly_Red"), and the forecast
 * cone ("Poly_Cones"). Positions after the event's last advisory are
 * forecasts.
 */
export function stormFrom(event: Record<string, unknown>, geometry: { features?: Feature[] }): StormRow | null {
  const from = utc(event.fromdate);
  const to = utc(event.todate);
  if (!from || !to) return null;
  const lastAdvisory = new Date(to).getTime();
  const features = geometry.features ?? [];
  const cls = (f: Feature) => String(f.properties.Class ?? "");

  const legs = features
    .filter((f) => cls(f).startsWith("Line_Line") && f.geometry.type === "LineString")
    .map((f) => ({
      start: (f.geometry.coordinates as number[][])[0],
      end: (f.geometry.coordinates as number[][]).at(-1)!,
      category: String(f.properties.polygonlabel ?? "") || null,
    }));
  // A leg's start names the category from that position on; the last
  // position has only a leg ending there.
  const nearest = (lat: number, lng: number, end: "start" | "end"): string | null => {
    let best: string | null = null;
    let bestD = 0.25;
    for (const leg of legs) {
      const [x, y] = leg[end];
      const d = Math.hypot(x - lng, y - lat);
      if (d < bestD) {
        bestD = d;
        best = leg.category;
      }
    }
    return best;
  };
  const categoryAt = (lat: number, lng: number) => nearest(lat, lng, "start") ?? nearest(lat, lng, "end");

  const track: TrackPoint[] = [];
  for (const f of features) {
    if (!cls(f).startsWith("Point_Polygon")) continue;
    const t = labelTime(String(f.properties.polygonlabel ?? ""), from);
    const ring = outerRings(f.geometry)[0];
    if (!t || !ring?.length) continue;
    const pts = ring.slice(0, -1).length ? ring.slice(0, -1) : ring;
    const lat = pts.reduce((s, p) => s + p[0], 0) / pts.length;
    const lng = pts.reduce((s, p) => s + p[1], 0) / pts.length;
    track.push({
      t,
      lat: round(lat),
      lng: round(lng),
      category: categoryAt(lat, lng),
      forecast: new Date(t).getTime() > lastAdvisory,
    });
  }
  track.sort((a, b) => a.t.localeCompare(b.t));
  if (!track.some((p) => inside([p.lat, p.lng], par))) return null;

  const zones = new Map<number, LatLng[][]>();
  const defaults: Record<string, number> = { Poly_Green: 60, Poly_Orange: 90, Poly_Red: 120 };
  for (const f of features) {
    const c = cls(f);
    if (!(c in defaults)) continue;
    const m = /(\d+)\s*km/.exec(String(f.properties.polygonlabel ?? ""));
    const kmh = m ? Number(m[1]) : defaults[c];
    const rings = outerRings(f.geometry).map((r) => simplify(r, 0.15));
    zones.set(kmh, [...(zones.get(kmh) ?? []), ...rings]);
  }
  const cone = features
    .filter((f) => cls(f) === "Poly_Cones")
    .flatMap((f) => outerRings(f.geometry).map((r) => simplify(r, 0.1)));

  const severity = (event.severitydata as { severity?: number } | undefined)?.severity;
  return {
    event_id: Number(event.eventid),
    episode_id: Number(event.episodeid),
    name: String(event.eventname || event.name || "Tropical cyclone"),
    alert_level: ["Green", "Orange", "Red"].includes(String(event.alertlevel)) ? String(event.alertlevel) : "Green",
    is_current: String(event.iscurrent) === "true",
    from_at: from,
    to_at: to,
    updated_at: utc(event.datemodified),
    max_wind_kmh: typeof severity === "number" ? Math.round(severity) : null,
    source: typeof event.source === "string" ? event.source : null,
    track,
    wind_zones: [...zones.entries()].sort((a, b) => a[0] - b[0]).map(([kmh, rings]) => ({ kmh, rings })),
    cone,
  };
}

// ------------------------------------------------------------------ PAGASA

export interface FeedEntry {
  id: string;
  title: string;
  updated: string;
  href: string;
  /** The feed's folder: wcp, gfa, ... */
  kind: string;
}

const entities: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

/** XML text with its entities decoded and its carriage returns dropped. */
export function decode(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&(amp|lt|gt|quot|apos);/g, (_, e) => entities[e])
    .replace(/\r/g, "")
    .trim();
}

const tag = (name: string, s: string): string | null => {
  const m = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(s);
  return m ? decode(m[1]) : null;
};
const tags = (name: string, s: string): string[] =>
  [...s.matchAll(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`, "g"))].map((m) => m[1]);

/** The entries of PAGASA's Atom feed (publicalert.pagasa.dost.gov.ph/feeds/). */
export function feedEntries(xml: string): FeedEntry[] {
  return tags("entry", xml).flatMap((e) => {
    const href = /<link[^>]*href="([^"]+)"/.exec(e)?.[1];
    const id = tag("id", e)?.replace(/^urn:uuid:/, "");
    const updated = tag("updated", e);
    if (!href || !id || !updated) return [];
    return [{
      id,
      title: tag("title", e)?.replace(/\s+/g, " ") ?? "",
      updated,
      href,
      kind: /\/output\/([a-z0-9_]+)\//i.exec(href)?.[1]?.toLowerCase() ?? "other",
    }];
  });
}

export interface WarningRow {
  id: string;
  kind: string;
  event: string;
  headline: string | null;
  description: string | null;
  instruction: string | null;
  msg_type: string | null;
  response_type: string | null;
  severity: string | null;
  urgency: string | null;
  signal_level: number | null;
  sent_at: string;
  expires_at: string | null;
  refs: string[];
  areas: { name: string; rings: LatLng[][] }[];
}

/** One CAP 1.2 alert from PAGASA, or null when it is not one. */
export function capWarning(xml: string, kind: string): WarningRow | null {
  const body = xml.split("<Signature")[0];
  const id = tag("identifier", body);
  const sent = tag("sent", body);
  const info = tags("info", body)[0];
  if (!id || !sent || !info) return null;
  const event = tag("event", info);
  if (!event) return null;
  let signal: number | null = null;
  for (const p of tags("parameter", info)) {
    if (/signal level/i.test(tag("valueName", p) ?? "")) {
      const v = Number.parseInt(tag("value", p) ?? "", 10);
      if (v >= 0 && v <= 5) signal = v;
    }
  }
  const areas = tags("area", info).map((a) => ({
    name: tag("areaDesc", a) ?? "",
    rings: tags("polygon", a).map((poly) =>
      simplify(
        decode(poly).split(/\s+/).map((pair) => pair.split(",").map(Number) as LatLng)
          .filter(([lat, lng]) => Number.isFinite(lat) && Number.isFinite(lng)),
        0.01,
      )
    ).filter((r) => r.length >= 4),
  }));
  // "sender,identifier,sent" triples, space-separated.
  const refs = (tag("references", body) ?? "").split(/\s+/).map((r) => r.split(",")[1]).filter(Boolean);
  const text = (s: string | null, max: number) => (s && s.length > max ? `${s.slice(0, max - 1)}…` : s);
  return {
    id,
    kind,
    event,
    headline: tag("headline", info),
    description: text(tag("description", info), 4000),
    instruction: text(tag("instruction", info), 2000),
    msg_type: tag("msgType", body),
    response_type: tag("responseType", info),
    severity: tag("severity", info),
    urgency: tag("urgency", info),
    signal_level: signal,
    sent_at: sent,
    expires_at: tag("expires", info),
    refs,
    areas,
  };
}
