// The RAG step of the NDRRMC report (Objective 4; plan 10.6): which
// reference passages go with each section, what the language model is
// asked, and the checks on what it answers. Pure functions, tested with
// Node (rag.test.ts). The calls to Gemini are in index.ts.

export interface Section {
  key: string;
  title: string;
  body: string;
}

export interface Reference {
  id: number;
  /** The section the passage guides, or null for any. */
  sectionKey: string | null;
  title: string;
  body: string;
  embedding: number[] | null;
}

/** What the database accepts (`save_ndrrmc_report`). */
export const maxSections = 12;
export const maxBody = 6000;

/** Passages given to the model for each section. */
export const passagesPerSection = 3;

/**
 * The keys in one or more secrets: several may be given, separated by
 * commas, spaces, or line breaks, so that when one is refused or over its
 * limit the next is tried. Duplicates and blanks are dropped.
 */
export function keysFrom(...secrets: (string | undefined | null)[]): string[] {
  const out: string[] = [];
  for (const s of secrets) {
    for (const k of (s ?? "").split(/[\s,;]+/)) {
      if (k && !out.includes(k)) out.push(k);
    }
  }
  return out;
}

/** The same list starting at `start`, wrapping round: spreads the calls
 * over the keys instead of always using up the first. */
export function rotated<T>(list: T[], start: number): T[] {
  if (list.length === 0) return [];
  const n = ((Math.trunc(start) % list.length) + list.length) % list.length;
  return [...list.slice(n), ...list.slice(0, n)];
}

/**
 * Tries `call` with each key in turn until one works. A key that is
 * refused, over its limit, or slow does not stop the rewrite. Gives up
 * once `budgetMs` has passed, and throws the last failure.
 */
export async function withKeys<T>(
  keys: string[],
  call: (key: string) => Promise<T>,
  budgetMs = 100_000,
  now: () => number = Date.now,
): Promise<T> {
  if (keys.length === 0) throw new Error("no key");
  const started = now();
  let last: unknown = new Error("no key");
  for (const key of keys) {
    if (now() - started > budgetMs) break;
    try {
      return await call(key);
    } catch (e) {
      last = e;
    }
  }
  throw last;
}

/** The request body, checked: the assembled draft and the figures. */
export function readRequest(body: unknown): { sections: Section[]; source: Record<string, unknown> } | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, unknown>;
  if (!Array.isArray(b.sections) || b.sections.length < 1 || b.sections.length > maxSections) return null;
  if (!b.source || typeof b.source !== "object" || Array.isArray(b.source)) return null;
  const sections: Section[] = [];
  for (const s of b.sections) {
    if (!s || typeof s !== "object") return null;
    const { key, title, body: text } = s as Record<string, unknown>;
    if (typeof key !== "string" || !key || typeof title !== "string" || !title.trim()) return null;
    if (typeof text !== "string" || text.length > maxBody) return null;
    sections.push({ key, title: title.trim(), body: text });
  }
  if (new Set(sections.map((s) => s.key)).size !== sections.length) return null;
  return { sections, source: b.source as Record<string, unknown> };
}

export function cosine(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na === 0 || nb === 0 ? 0 : dot / Math.sqrt(na * nb);
}

const stop = new Set([
  "the", "and", "for", "with", "from", "that", "this", "were", "was", "are", "not", "its", "any",
  "how", "many", "each", "their", "them", "they", "has", "have", "had", "but", "when", "which",
]);

export function words(text: string): Set<string> {
  return new Set(
    (text.toLowerCase().match(/[a-z]{3,}/g) ?? []).filter((w) => !stop.has(w)),
  );
}

/** Share of the query's words found in the passage: the fallback when
 * embeddings are not available. */
export function overlap(query: string, passage: string): number {
  const q = words(query);
  if (q.size === 0) return 0;
  const p = words(passage);
  let hit = 0;
  for (const w of q) if (p.has(w)) hit++;
  return hit / q.size;
}

/** A passage written for this section counts a little more. */
const sameSectionBonus = 0.15;

/**
 * The passages closest to a section, best first. By embedding when both
 * the section and the passage have one, by shared words otherwise.
 */
export function retrieve(
  section: Section,
  sectionEmbedding: number[] | null,
  references: Reference[],
  limit = passagesPerSection,
): Reference[] {
  const query = `${section.title}\n${section.body}`;
  return references
    .map((r) => {
      const base = sectionEmbedding && r.embedding
        ? cosine(sectionEmbedding, r.embedding)
        : overlap(query, `${r.title}\n${r.body}`);
      return { r, score: base + (r.sectionKey === section.key ? sameSectionBonus : 0) };
    })
    .sort((a, b) => b.score - a.score || a.r.id - b.r.id)
    .slice(0, limit)
    .map((x) => x.r);
}

export const systemInstruction = [
  "You write sections of a situation report that a city disaster office (Manila City MDRRMD) submits to the NDRRMC.",
  "For each section you are given: the facts (a draft assembled from the records, and the figures as JSON) and reference passages on how that section is written.",
  "Rules:",
  "1. Use only the facts given. Never add a number, place, date, name, or event that is not in them.",
  "2. Keep every number exactly as given, in digits (write 14, not fourteen). Do not round, convert, or estimate.",
  "3. Where a fact is missing, say it is not available. Do not fill the gap.",
  "4. Follow the reference passages for structure and wording. They are guidance, not facts: take no figures from them. Use a passage only for the section it is listed under, and do not repeat one section's content in another.",
  "5. Formal, plain English. Short sentences. No headings, no bullet symbols, no markdown: plain paragraphs only.",
  "6. No names of persons, contact numbers, addresses, or coordinates.",
  "7. At most 1,200 characters per section.",
  "Answer with JSON only: {\"sections\": [{\"key\": \"...\", \"body\": \"...\"}]}, one item for each section asked, with the same keys.",
].join("\n");

/** The figures, without what the model has no use for. */
export function figuresForPrompt(source: Record<string, unknown>): string {
  return JSON.stringify(source);
}

export function buildPrompt(
  sections: Section[],
  source: Record<string, unknown>,
  passages: Map<string, Reference[]>,
): string {
  const parts = [`FIGURES (JSON):\n${figuresForPrompt(source)}`];
  for (const s of sections) {
    const refs = passages.get(s.key) ?? [];
    parts.push([
      `SECTION key="${s.key}" title="${s.title}"`,
      `FACTS (assembled draft):\n${s.body.trim() || "(nothing recorded)"}`,
      refs.length
        ? `REFERENCE PASSAGES:\n${refs.map((r, i) => `[${i + 1}] ${r.title}: ${r.body}`).join("\n")}`
        : "REFERENCE PASSAGES: none",
    ].join("\n"));
  }
  return parts.join("\n\n");
}

/** The model's answer as sections, in the order asked. Null when it is
 * not the JSON asked for or a section is missing. */
export function readAnswer(text: string, asked: Section[]): Section[] | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, "").trim());
  } catch {
    return null;
  }
  const list = (parsed as { sections?: unknown })?.sections;
  if (!Array.isArray(list)) return null;
  const byKey = new Map<string, string>();
  for (const item of list) {
    const { key, body } = (item ?? {}) as Record<string, unknown>;
    if (typeof key === "string" && typeof body === "string") byKey.set(key, body);
  }
  const out: Section[] = [];
  for (const s of asked) {
    const body = byKey.get(s.key)?.trim();
    if (!body) return null;
    out.push({ key: s.key, title: s.title, body: body.slice(0, maxBody) });
  }
  return out;
}

/** Numbers as they appear in a text: "1,204" and "1204" are the same,
 * "4.50" and "4.5" are the same. */
export function numbersIn(text: string): Set<string> {
  const out = new Set<string>();
  for (const m of text.matchAll(/\d[\d,]*(?:\.\d+)?/g)) {
    const n = Number(m[0].replace(/,/g, ""));
    if (Number.isFinite(n)) out.add(String(n));
  }
  return out;
}

/**
 * Numbers in the model's text that are in none of the facts it was given
 * (the figures and the assembled draft). The editor shows them so the
 * administrator checks those sentences first. Numbers in section titles
 * and the facts' own text count as known.
 */
export function unknownNumbers(
  written: Section[],
  facts: Section[],
  source: Record<string, unknown>,
): { key: string; numbers: string[] }[] {
  const known = numbersIn(JSON.stringify(source));
  for (const f of facts) {
    for (const n of numbersIn(`${f.title} ${f.body}`)) known.add(n);
  }
  const out: { key: string; numbers: string[] }[] = [];
  for (const s of written) {
    const extra = [...numbersIn(s.body)].filter((n) => !known.has(n));
    if (extra.length) out.push({ key: s.key, numbers: extra });
  }
  return out;
}
