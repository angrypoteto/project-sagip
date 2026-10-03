// Reads PHIVOLCS's public list of recent earthquakes
// (https://earthquake.phivolcs.dost.gov.ph/), for the advisory relay of
// FR14: the dispatcher sees the ones near Manila on the Weather page and
// decides whether to pass one on. Pure functions, tested with Node
// (phivolcs.test.ts) on a saved copy of the page.

export interface Quake {
  /** Stable id: the time and place as PHIVOLCS lists them. */
  key: string;
  /** ISO time with the Philippine offset. */
  occurredAt: string;
  latitude: number;
  longitude: number;
  depthKm: number;
  magnitude: number;
  /** "023 km S 66° E of Lobo (Batangas)". */
  location: string;
  /** Great-circle distance from Manila City Hall, in kilometres. */
  distanceKm: number;
  /** The event's PHIVOLCS bulletin, when the row links one. */
  bulletinUrl: string | null;
}

export const phivolcsPage = "https://earthquake.phivolcs.dost.gov.ph/";

/** Manila City Hall, the point distances are measured from. */
export const manila = { lat: 14.5896, lng: 120.981 };

const months = [
  "january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december",
];

const entities: Record<string, string> = {
  "&nbsp;": " ", "&deg;": "°", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&#176;": "°", "&quot;": "\"",
};

function cellText(html: string): string {
  return html
    .replace(/<[^>]+>/g, " ")
    .replace(/&[#a-z0-9]+;/gi, (e) => entities[e.toLowerCase()] ?? " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** "03 October 2026 - 08:33 PM" as an ISO time in Philippine time. */
export function phivolcsTime(s: string): string | null {
  const m = /(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s*-\s*(\d{1,2}):(\d{2})\s*([AP])M/i.exec(s);
  if (!m) return null;
  const month = months.indexOf(m[2].toLowerCase());
  if (month < 0) return null;
  let hour = parseInt(m[4], 10) % 12;
  if (m[6].toUpperCase() === "P") hour += 12;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${m[3]}-${pad(month + 1)}-${pad(parseInt(m[1], 10))}T${pad(hour)}:${m[5]}:00+08:00`;
}

/** Haversine distance in kilometres. */
export function kmBetween(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = (d: number) => (d * Math.PI) / 180;
  const a = Math.sin(r(lat2 - lat1) / 2) ** 2 +
    Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(a));
}

/**
 * Every event row of the page: date and time, latitude, longitude, depth,
 * magnitude, and location. Rows that do not read as an event (titles,
 * month headings, the column headings) are skipped.
 */
export function parseEarthquakes(html: string, base = phivolcsPage): Quake[] {
  const out: Quake[] = [];
  for (const row of html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...row[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map((c) => c[1]);
    if (cells.length < 6) continue;
    const time = phivolcsTime(cellText(cells[0]));
    const [lat, lng, depth, mag] = cells.slice(1, 5).map((c) => Number(cellText(c)));
    if (!time || ![lat, lng, depth, mag].every(Number.isFinite)) continue;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180 || mag < 0 || mag > 10) continue;
    const href = /href="([^"]+)"/i.exec(cells[0])?.[1];
    out.push({
      key: `${time}|${lat.toFixed(2)}|${lng.toFixed(2)}`,
      occurredAt: time,
      latitude: lat,
      longitude: lng,
      depthKm: depth,
      magnitude: mag,
      location: cellText(cells[5]),
      distanceKm: Math.round(kmBetween(manila.lat, manila.lng, lat, lng) * 10) / 10,
      bulletinUrl: href ? new URL(href.replace(/\\/g, "/"), base).toString() : null,
    });
  }
  return out;
}

/**
 * The events worth keeping for Manila: within [withinKm] of the city and
 * no older than [hours] before [now]. The Weather page narrows further
 * (magnitude 3 and up within 200 km, provisional).
 */
export function nearManila(
  quakes: Quake[],
  now: Date,
  { withinKm = 300, hours = 48 } = {},
): Quake[] {
  const since = now.getTime() - hours * 3600_000;
  return quakes.filter((q) => q.distanceKm <= withinKm && Date.parse(q.occurredAt) >= since);
}
