// Reading PAGASA's public pages (FR5): Joshua decided on 2026-10-03 to parse
// what PAGASA publishes instead of waiting for API access (plan Q35,
// docs/PAGASA-PARSER-PLAN.md). Pure functions only, so Node tests can run
// them on saved copies of real pages and bulletins.
//
// Three readings for Metro Manila, the ones the threshold engine watches:
// - rainfall: the NCR Heavy Rainfall Warning level, as its lower bound in
//   mm/hr (Yellow 7.5, Orange 15, Red 30; PAGASA's own bands);
// - wind signal: the highest Tropical Cyclone Wind Signal naming Metro
//   Manila in the latest Tropical Cyclone Bulletin;
// - storm surge: the highest surge height the bulletin gives for coasts
//   that include Metro Manila.

export type RainLevel = "yellow" | "orange" | "red";

/** PAGASA's rainfall bands: the lower bound of each, in mm per hour. */
export const rainLevelMm: Record<RainLevel, number> = {
  yellow: 7.5,
  orange: 15,
  red: 30,
};

export type RainfallReading =
  | { state: "none"; mmPerHour: 0 }
  | {
    state: "warning";
    /** The level over Metro Manila; null when the warning is elsewhere. */
    level: RainLevel | null;
    mmPerHour: number;
    number: number;
    issued: string | null;
  }
  | { state: "unreadable"; reason: string };

export type BulletinPage =
  | { state: "none" }
  | { state: "active"; pdfUrl: string; number: number }
  | { state: "unreadable"; reason: string };

export type CycloneReading =
  | {
    state: "bulletin";
    number: number;
    name: string | null;
    issued: string | null;
    /** The highest wind signal naming Metro Manila, 0 when none does. */
    signal: number;
    /** The highest storm surge height for coasts in Metro Manila, else 0. */
    surgeM: number;
    final: boolean;
  }
  | { state: "unreadable"; reason: string };

// ------------------------------------------------------------ text helpers

const entities: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  deg: "°",
};

/** The visible text of an HTML page, one block per line. */
export function htmlText(html: string): string {
  return html
    .replace(/<(script|style|noscript)[^>]*>[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<[^>]+>/g, "\n")
    .replace(/&(#\d+|#x[0-9a-f]+|[a-z]+);/gi, (m, e: string) => {
      if (e[0] === "#") {
        const code = e[1].toLowerCase() === "x"
          ? parseInt(e.slice(2), 16)
          : parseInt(e.slice(1), 10);
        return Number.isFinite(code) ? String.fromCodePoint(code) : m;
      }
      return entities[e.toLowerCase()] ?? m;
    })
    .split("\n")
    .map((l) => l.replace(/[ \t\u00a0]+/g, " ").trim())
    .filter((l) => l.length > 0)
    .join("\n");
}

const flat = (s: string) => s.replace(/\s+/g, " ").trim();

/**
 * Whether a list of areas covers the City of Manila. "Metro Manila" and
 * "National Capital Region" count; "a portion of Metro Manila (A, B)"
 * counts only when the list names Manila itself. "Manila Bay" does not.
 */
export function coversManila(areas: string): boolean {
  const t = flat(areas);
  const metro = /Metro Manila(\s*\(([^)]*)\))?/gi;
  for (const m of t.matchAll(metro)) {
    const before = t.slice(Math.max(0, (m.index ?? 0) - 40), m.index);
    const portion = /portions? of\s+(the\s+)?$/i.test(before);
    if (portion && m[2] !== undefined) {
      if (/\b(City of )?Manila\b/i.test(m[2])) return true;
      continue;
    }
    return true;
  }
  return /\bNational Capital Region\b|\bNCR\b|\bCity of Manila\b/.test(t);
}

const months = [
  "january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december",
];

/**
 * "8:00 PM, 23 October 2024" (Manila time) as an ISO time, or null.
 * PAGASA writes it a few ways: "Issued at: 1:18 AM, 03 October 2026
 * (Saturday)", "Issued at 11:00 AM, 25 September 2026".
 */
export function pagasaTime(s: string | null | undefined): string | null {
  if (!s) return null;
  const m = /(\d{1,2}):(\d{2})\s*([AP])\.?M\.?,?\s*(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/i
    .exec(s);
  if (!m) return null;
  const month = months.indexOf(m[5].toLowerCase());
  if (month < 0) return null;
  let hour = parseInt(m[1], 10) % 12;
  if (m[3].toUpperCase() === "P") hour += 12;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${m[6]}-${pad(month + 1)}-${pad(parseInt(m[4], 10))}T${pad(hour)}:${m[2]}:00+08:00`;
}

// ------------------------------------------------------------ rainfall

/** The NCR regional page: is a Heavy Rainfall Warning in effect for Manila? */
export function parseRainfallWarning(html: string): RainfallReading {
  const text = htmlText(html);
  if (/no Heavy Rainfall Warning/i.test(text)) {
    return { state: "none", mmPerHour: 0 };
  }
  const head = /Heavy Rainfall Warning No\.?\s*(\d+)/i.exec(text);
  if (!head) {
    return {
      state: "unreadable",
      reason: "No rainfall warning and no \"no warning\" notice on the NCR page",
    };
  }
  // Only the warning itself: from its title to the next few thousand
  // characters, so the forecast text elsewhere on the page is not read.
  const block = text.slice(head.index, head.index + 4000);
  const issued = /Issued at:?\s*([^\n]+)/i.exec(block)?.[1] ?? null;
  let level: RainLevel | null = null;
  for (const lvl of ["red", "orange", "yellow"] as RainLevel[]) {
    const m = new RegExp(
      `${lvl} WARNING LEVEL:?([\\s\\S]*?)(?=(?:RED|ORANGE|YELLOW) WARNING LEVEL|ASSOCIATED HAZARD|Meanwhile|The public|Heavy Rainfall Warning No|$)`,
      "i",
    ).exec(block);
    if (m && coversManila(m[1])) {
      level = lvl;
      break;
    }
  }
  return {
    state: "warning",
    level,
    mmPerHour: level ? rainLevelMm[level] : 0,
    number: parseInt(head[1], 10),
    issued: pagasaTime(issued),
  };
}

// ------------------------------------------------------------ cyclones

/** The bulletin page: no cyclone, or the latest bulletin's PDF. */
export function parseBulletinPage(html: string, base: string): BulletinPage {
  if (/No Active Tropical Cyclone/i.test(htmlText(html))) return { state: "none" };
  let best: { pdfUrl: string; number: number } | null = null;
  for (const m of html.matchAll(/href="([^"]*TCB[^"]*\.pdf)"/gi)) {
    const n = /TCB(?:%23|#)(\d+)/i.exec(m[1]);
    if (!n) continue;
    const number = parseInt(n[1], 10);
    if (!best || number > best.number) {
      best = { pdfUrl: new URL(m[1], base).toString(), number };
    }
  }
  return best
    ? { state: "active", ...best }
    : { state: "unreadable", reason: "A cyclone is active but no bulletin PDF is linked" };
}

/** The text of a Tropical Cyclone Bulletin (PDF): Manila's signal and surge. */
export function parseCycloneBulletin(text: string): CycloneReading {
  const number = /TROPICAL CYCLONE BULLETIN\s+(?:NR|NO)\.?\s*(\d+)/i.exec(text);
  if (!number) {
    return { state: "unreadable", reason: "Not a Tropical Cyclone Bulletin" };
  }
  const name = /(?:Super Typhoon|Typhoon|Severe Tropical Storm|Tropical Storm|Tropical Depression)\s+([A-Z][A-Z-]+)/
    .exec(text)?.[1] ?? null;
  const issued = /Issued at:?\s*([^\n]+)/i.exec(text)?.[1] ?? null;

  // The signal table repeats its header on every page; each level starts
  // with the number alone on a line, then "Wind threat:".
  let signal = 0;
  const level = /(?:^|\n)\s*([1-5])\s*\n\s*Wind threat:([\s\S]*?)(?=\n\s*[1-5]\s*\n\s*Wind threat:|Warning lead time|$)/g;
  for (const m of text.matchAll(level)) {
    const n = parseInt(m[1], 10);
    if (n > signal && coversManila(m[2])) signal = n;
  }

  // "... storm surge up to 2.0 m above normal tide levels ... over the
  // low-lying or exposed coastal localities of A, B, and C."
  let surgeM = 0;
  const sentences = flat(text).split(/(?<=\.)\s+(?=[A-Z])/);
  for (const s of sentences) {
    if (!/storm surge/i.test(s) || !coversManila(s)) continue;
    for (const h of s.matchAll(/(\d+(?:\.\d+)?)\s*(?:m|meters?)\b/gi)) {
      surgeM = Math.max(surgeM, parseFloat(h[1]));
    }
  }

  return {
    state: "bulletin",
    number: parseInt(number[1], 10),
    name,
    issued: pagasaTime(issued),
    signal,
    surgeM,
    final: /FINAL/i.test(text.slice(0, 400)),
  };
}
