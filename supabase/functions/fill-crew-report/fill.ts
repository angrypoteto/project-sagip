// The parts of fill-crew-report that need no network: the form's allowed
// answers, removing names from the notes, the prompt, and checking the
// model's answer. Tested in fill.test.ts.

/** The answers MDRRMD's forms allow, as the phone stores them
 * (CompletionDetails in packages/shared). */
export const allowed = {
  emr_type: ["roadAccident", "medicalCall", "medicalStandby", "patientTransport"],
  accident_cause: [
    "drunkDriving", "lossOfControl", "brakeFailure", "overspeeding", "driverNegligence",
    "roadCondition", "roadHazards", "inclementWeather", "roadTrafficCollision", "other",
  ],
  vehicles: [
    "pedestrian", "bicycle", "motorcycle", "eBike", "tricycle", "eTrike", "sedan", "suv", "van",
    "taxi", "puj", "puv", "truck", "ambulance", "fireTruck", "other",
  ],
  age: [
    "upTo17", "from18To25", "from26To30", "from31To35", "from36To40", "from41To45",
    "from46To50", "from51To60", "from61",
  ],
  gender: ["male", "female", "other"],
  flood_cause: ["cloggedWaterways", "heavyRainfall", "tropicalCyclone", "stormSurge"],
  flood_level: ["gutter", "halfKnee", "halfTire", "knee", "tire", "waist", "chest", "aboveChest", "head"],
  flood_status: ["patv", "nplv", "npatv"],
  fire_kind: [
    "rubbish", "electrical", "commercial", "residential", "governmentOffice", "vehicular",
    "warehouse", "residentialCommercial",
  ],
  highest_alarm: [
    "firstAlarm", "secondAlarm", "thirdAlarm", "fourthAlarm", "fifthAlarm", "taskForceAlpha",
    "taskForceBravo", "taskForceCharlie", "taskForceDelta", "taskForceEcho", "generalAlarm",
  ],
} as const;

/** RECEIVING HOSPITAL, as on the form (and receivingHospitals in the app). */
export const hospitals = [
  "Refused to transport",
  "Double two upon arrival",
  "Philippine Orthopedic Center (P.O.C.)",
  "Ospital ng Maynila (OSMA)",
  "Ospital ng Sampaloc (OSAM)",
  "Ospital ng Tondo",
  "Philippine General Hospital (PGH)",
  "Sta. Ana Hospital",
  "Gat Andres Bonifacio Hospital",
  "Tondo Medical Hospital",
  "Jose Reyes Hospital",
  "Chinese General Hospital",
  "Metropolitan Hospital",
  "Manila Medical Center",
  "St. Jude Hospital",
  "Infant Jesus Hospital",
  "UST Hospital",
  "Manila Doctor's Hospital",
  "Mary Johnston Hospital",
  "Justice Jose Abad Santos General Hospital (JJASGEN)",
  "UERM",
  "Other",
];

export type IncidentType = "medical" | "flood" | "fire" | "structural";
export const maxNotes = 2000;

/** The figures on every crew report the notes can give. */
export const figureKeys = ["persons_assisted", "injured", "missing", "affected_families", "houses_damaged"];

// ------------------------------------------------------------------ privacy

/**
 * The notes with the given names (the SOS sender's, from the server) and
 * anything that looks like a phone number taken out, before they go to the
 * language model (RA 10173). Each part of a name of 3 letters or more is
 * removed too ("Maria" as well as "Maria Santos").
 */
export function redact(notes: string, names: string[]): string {
  let out = notes;
  const parts = new Set<string>();
  for (const n of names) {
    const full = n.trim();
    if (full.length >= 3) parts.add(full);
    for (const p of full.split(/\s+/)) if (p.length >= 3) parts.add(p);
  }
  // Longest first, so the full name goes before its parts.
  for (const p of [...parts].sort((a, b) => b.length - a.length)) {
    out = out.replace(new RegExp(`\\b${escape(p)}\\b`, "gi"), "the patient");
  }
  return out.replace(/(\+?\d[\d\s-]{6,}\d)/g, (m) => (m.replace(/\D/g, "").length >= 7 ? "[number]" : m));
}

function escape(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ------------------------------------------------------------------ retrieval

export interface Passage {
  id: number;
  title: string;
  body: string;
  embedding: number[] | null;
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

export function words(text: string): Set<string> {
  return new Set(text.toLowerCase().match(/[a-z]{3,}/g) ?? []);
}

/** The passages closest to the notes, best first: by embedding when both
 * have one, by shared words otherwise. */
export function closest(notes: string, notesEmbedding: number[] | null, passages: Passage[], limit = 3): Passage[] {
  const q = words(notes);
  return passages
    .map((p) => {
      let score: number;
      if (notesEmbedding && p.embedding) {
        score = cosine(notesEmbedding, p.embedding);
      } else {
        const w = words(`${p.title} ${p.body}`);
        let hit = 0;
        for (const x of q) if (w.has(x)) hit++;
        score = q.size ? hit / q.size : 0;
      }
      return { p, score };
    })
    .sort((a, b) => b.score - a.score || a.p.id - b.p.id)
    .slice(0, limit)
    .map((x) => x.p);
}

// ------------------------------------------------------------------ prompt

export const systemInstruction = [
  "You help a Manila MDRRMD field responder file the crew report for an incident.",
  "From the responder's notes you fill in the questions of MDRRMD's form for the incident's type and write a short narrative.",
  "Use only facts in the notes. Never guess: leave out any answer the notes do not give.",
  "The narrative restates only what the notes say: do not add outcomes or events they do not mention (for example that a fire was contained, put out, or under control, that a patient was stable, or that people were evacuated).",
  "For each answer use exactly one of the allowed values listed. Numbers must come from the notes.",
  "Never write anyone's name, phone number, or exact address. Refer to people as the patient, the driver, a resident.",
  "The notes may be in English, Filipino, or both. Write the narrative in English: 2 to 4 sentences, past tense, plain words, no headings.",
  "Answer with JSON only.",
].join(" ");

function questionsFor(type: IncidentType): string {
  switch (type) {
    case "medical":
      return [
        `"emr_type": one of ${list(allowed.emr_type)}`,
        `"accident_cause": only for a road accident, one of ${list(allowed.accident_cause)}`,
        `"vehicles": only for a road accident, a list of ${list(allowed.vehicles)} (one entry per vehicle or pedestrian involved)`,
        `"patients": a list, one object per patient, each with "age" (one of ${list(allowed.age)}), "gender" (one of ${list(allowed.gender)}), "hospital" (exactly one of ${list(hospitals)}), "chief_complaint" (a few words), "remarks" (a few words); leave out what is not in the notes; never a name`,
      ].join("\n");
    case "flood":
      return [
        `"flood_cause": one of ${list(allowed.flood_cause)}`,
        `"cyclone_name": the tropical cyclone's name, only if the cause is a tropical cyclone`,
        `"wind_signal": 1 to 5, only if the cause is a tropical cyclone and the notes say the signal`,
        `"flood_level": one of ${list(allowed.flood_level)}`,
        `"flood_status": one of ${list(allowed.flood_status)}`,
      ].join("\n");
    case "fire":
      return [
        `"fire_kind": one of ${list(allowed.fire_kind)}`,
        `"highest_alarm": one of ${list(allowed.highest_alarm)}`,
        `"estimated_damage": pesos, a number`,
        `"affected_individuals": a number`,
      ].join("\n");
    default:
      return "(no form questions for this type: answers stays empty)";
  }
}

function list(values: readonly string[]): string {
  return values.map((v) => JSON.stringify(v)).join(", ");
}

export function buildPrompt(
  type: IncidentType,
  notes: string,
  passages: Passage[],
  examples: unknown[],
): string {
  return [
    `Incident type: ${type}.`,
    "",
    "MDRRMD's form guidance (retrieved):",
    ...passages.map((p, i) => `[${i + 1}] ${p.title}: ${p.body}`),
    "",
    examples.length
      ? `Validated past crew reports of this type, as examples of the answers (JSON): ${JSON.stringify(examples).slice(0, 4000)}`
      : "No validated past reports of this type yet.",
    "",
    "The responder's notes:",
    notes,
    "",
    "Answer as JSON with:",
    `"answers": an object with, where the notes give them:\n${questionsFor(type)}`,
    `"figures": an object with any of ${list(figureKeys)} the notes give (numbers)`,
    `"narrative": the short narrative for MDRRMD`,
  ].join("\n");
}

// ------------------------------------------------------------------ the answer

/** Every number written in a text, as digits ("2,000" and "2000" alike). */
export function numbersIn(text: string): Set<string> {
  const out = new Set<string>();
  for (const m of text.match(/\d[\d,]*(\.\d+)?/g) ?? []) {
    out.add(String(Number(m.replace(/,/g, ""))));
  }
  // Numbers written as words, the common small ones.
  const named: Record<string, number> = {
    one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
    isa: 1, dalawa: 2, tatlo: 3, apat: 4, lima: 5, anim: 6, pito: 7, walo: 8, siyam: 9, sampu: 10,
  };
  for (const w of text.toLowerCase().match(/[a-z]+/g) ?? []) {
    if (w in named) out.add(String(named[w]));
  }
  return out;
}

export interface Filled {
  answers: Record<string, unknown>;
  figures: Record<string, number>;
  narrative: string;
  /** What was dropped or needs a look, for the log and the responder. */
  check: string[];
}

function pick<T extends string>(value: unknown, values: readonly T[]): T | undefined {
  return typeof value === "string" && (values as readonly string[]).includes(value) ? value as T : undefined;
}

/** The hospital as the form writes it: exact, or by its short name
 * ("OSMA", "PGH", "UERM"). */
export function hospitalFrom(value: unknown): string | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  const v = value.trim().toLowerCase();
  const exact = hospitals.find((h) => h.toLowerCase() === v);
  if (exact) return exact;
  return hospitals.find((h) => {
    const short = h.match(/\(([^)]+)\)/)?.[1]?.replace(/\./g, "").toLowerCase();
    return (short && v.replace(/\./g, "") === short) || h.toLowerCase().startsWith(v);
  });
}

function text(value: unknown, max = 200): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : undefined;
}

/**
 * The model's answer, kept only where it is one of the form's allowed
 * values and its numbers are in the notes. Names are never kept.
 */
export function readFilled(raw: string, type: IncidentType, notes: string): Filled | null {
  let data: unknown;
  try {
    data = JSON.parse(raw.replace(/^```(json)?\s*|\s*```$/g, ""));
  } catch {
    return null;
  }
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, unknown>;
  const a = (d.answers && typeof d.answers === "object" ? d.answers : {}) as Record<string, unknown>;
  const check: string[] = [];
  const said = numbersIn(notes);
  const fromNotes = (n: unknown, what: string): number | undefined => {
    if (typeof n !== "number" || !Number.isFinite(n) || n < 0) return undefined;
    if (!said.has(String(n))) {
      check.push(`${what} ${n} is not in the notes`);
      return undefined;
    }
    return Math.round(n);
  };
  const keep = (key: string, value: unknown, values: readonly string[]) => {
    const v = pick(value, values);
    if (v) answers[key] = v;
    else if (value !== undefined && value !== null && value !== "") check.push(`${key} "${value}" is not on the form`);
  };

  const answers: Record<string, unknown> = {};
  if (type === "medical") {
    keep("emr_type", a.emr_type, allowed.emr_type);
    if (answers.emr_type === "roadAccident") {
      keep("accident_cause", a.accident_cause, allowed.accident_cause);
      const vehicles = Array.isArray(a.vehicles)
        ? a.vehicles.map((v) => pick(v, allowed.vehicles)).filter((v): v is NonNullable<typeof v> => !!v)
        : [];
      if (vehicles.length) answers.vehicles = vehicles.slice(0, 10);
    }
    if (Array.isArray(a.patients)) {
      const patients = a.patients.slice(0, 30).map((p) => {
        const q = (p && typeof p === "object" ? p : {}) as Record<string, unknown>;
        const out: Record<string, unknown> = {};
        const age = pick(q.age, allowed.age);
        const gender = pick(q.gender, allowed.gender);
        const hospital = hospitalFrom(q.hospital);
        if (age) out.age = age;
        if (gender) out.gender = gender;
        if (hospital) out.hospital = hospital;
        else if (q.hospital) check.push(`hospital "${q.hospital}" is not on the form`);
        const complaint = text(q.chief_complaint, 100);
        const remarks = text(q.remarks, 100);
        if (complaint) out.chief_complaint = complaint;
        if (remarks) out.remarks = remarks;
        return out;
      });
      if (patients.length) answers.patients = patients;
    }
  } else if (type === "flood") {
    keep("flood_cause", a.flood_cause, allowed.flood_cause);
    if (answers.flood_cause === "tropicalCyclone") {
      const name = text(a.cyclone_name, 40);
      if (name) answers.cyclone_name = name;
      const signal = fromNotes(a.wind_signal, "wind signal");
      if (signal && signal >= 1 && signal <= 5) answers.wind_signal = signal;
    }
    keep("flood_level", a.flood_level, allowed.flood_level);
    keep("flood_status", a.flood_status, allowed.flood_status);
  } else if (type === "fire") {
    keep("fire_kind", a.fire_kind, allowed.fire_kind);
    keep("highest_alarm", a.highest_alarm, allowed.highest_alarm);
    const damage = fromNotes(a.estimated_damage, "estimated damage");
    if (damage !== undefined) answers.estimated_damage = damage;
    const individuals = fromNotes(a.affected_individuals, "affected individuals");
    if (individuals !== undefined) answers.affected_individuals = individuals;
  }

  const f = (d.figures && typeof d.figures === "object" ? d.figures : {}) as Record<string, unknown>;
  const figures: Record<string, number> = {};
  const patientCount = Array.isArray(answers.patients) ? (answers.patients as unknown[]).length : 0;
  for (const k of figureKeys) {
    const n = f[k];
    // The number of patients counts as said (the notes list them).
    if (typeof n === "number" && n === patientCount && patientCount > 0 && (k === "injured" || k === "persons_assisted")) {
      figures[k] = n;
      continue;
    }
    const v = fromNotes(n, k.replace(/_/g, " "));
    if (v !== undefined) figures[k] = v;
  }

  let narrative = text(d.narrative, 2000) ?? "";
  // Every number in the narrative must be in the notes or the answers.
  const known = new Set([...said, ...numbersIn(JSON.stringify(answers)), ...Object.values(figures).map(String)]);
  for (const n of numbersIn(narrative)) {
    if (!known.has(n)) check.push(`the narrative's ${n} is not in the notes`);
  }
  narrative = narrative.replace(/\s+/g, " ").trim();
  return { answers, figures, narrative, check };
}

// ------------------------------------------------------------------ keys

export function keysFrom(...secrets: (string | undefined | null)[]): string[] {
  const out: string[] = [];
  for (const s of secrets) {
    for (const k of (s ?? "").split(/[\s,;]+/)) if (k && !out.includes(k)) out.push(k);
  }
  return out;
}

export function rotated<T>(list: T[], start: number): T[] {
  if (list.length === 0) return [];
  const n = ((Math.trunc(start) % list.length) + list.length) % list.length;
  return [...list.slice(n), ...list.slice(0, n)];
}

export async function withKeys<T>(keys: string[], call: (key: string) => Promise<T>, budgetMs: number): Promise<T> {
  if (keys.length === 0) throw new Error("no key");
  const started = Date.now();
  let last: unknown = new Error("no key");
  for (const key of keys) {
    if (Date.now() - started > budgetMs) break;
    try {
      return await call(key);
    } catch (e) {
      last = e;
    }
  }
  throw last;
}
