// Reads PAGASA's public river level list for the Pasig-Marikina-Tullahan
// basin, for the Weather page (FR5). Pure functions, tested with Node
// (efcos.test.ts) on a saved copy of the list.

export const riverPage = "https://pasig-marikina-tullahanffws.pagasa.dost.gov.ph/water/main_list.do";

export interface RiverLevel {
  code: string;
  name: string;
  latitude: number;
  longitude: number;
  observedAt: string;
  levelM: number;
  changeM: number | null;
  alertM: number | null;
  alarmM: number | null;
  criticalM: number | null;
  flagged: boolean;
}

/** "202610111120" as an ISO time in Philippine time. */
export function riverTime(ymdhm: string): string | null {
  if (!/^\d{12}$/.test(ymdhm)) return null;
  return `${ymdhm.slice(0, 4)}-${ymdhm.slice(4, 6)}-${ymdhm.slice(6, 8)}T${ymdhm.slice(8, 10)}:${ymdhm.slice(10, 12)}:00+08:00`;
}

function numberOrNull(value: unknown): number | null {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (typeof value === "string" && !value.trim()) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Station rows with coordinates, a readable time, and a numeric level. */
export function parseLevels(text: string): RiverLevel[] {
  const rows = JSON.parse(text);
  if (!Array.isArray(rows)) throw new Error("The river level list is not a JSON array");
  const out: RiverLevel[] = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    if (typeof row.obscd !== "string" || !row.obscd ||
      typeof row.obsnm !== "string" || !row.obsnm.trim()) continue;
    const latitude = numberOrNull(row.lat);
    const longitude = numberOrNull(row.lon);
    const observedAt = typeof row.ymdhm === "string" ? riverTime(row.ymdhm) : null;
    const flagged = typeof row.wl === "string" && row.wl.endsWith("(*)");
    const levelM = numberOrNull(flagged ? row.wl.slice(0, -3) : row.wl);
    if (latitude === null || longitude === null || !observedAt || levelM === null) continue;
    out.push({
      code: row.obscd,
      name: row.obsnm.trim(),
      latitude,
      longitude,
      observedAt,
      levelM,
      changeM: numberOrNull(row.wlchange),
      alertM: numberOrNull(row.alertwl),
      alarmM: numberOrNull(row.alarmwl),
      criticalM: numberOrNull(row.criticalwl),
      flagged,
    });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}

export type RiverState = "normal" | "alert" | "alarm" | "critical";

/** The highest threshold reached; stations without an alert level have no state. */
export function levelState(l: RiverLevel): RiverState | null {
  if (l.alertM === null) return null;
  if (l.criticalM !== null && l.levelM >= l.criticalM) return "critical";
  if (l.alarmM !== null && l.levelM >= l.alarmM) return "alarm";
  if (l.levelM >= l.alertM) return "alert";
  return "normal";
}
