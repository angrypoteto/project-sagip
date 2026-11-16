// fill-crew-report: RAG on the responder's crew report (Objective 4;
// Joshua, 2026-11-17: "can we make the responder report have the rag so it
// will be the rag part", with a narrative too).
//
// The responder's app sends the incident id and the notes the responder
// wrote or dictated. The function:
//   1. checks the caller (begin_crew_report_fill: a responder whose unit
//      holds the open incident; at most 30 runs an hour) and learns the
//      incident's type and the SOS sender's name;
//   2. removes that name and phone numbers from the notes (RA 10173);
//   3. retrieves MDRRMD's form guidance for the type (report_reference,
//      section_key 'crew_<type>'; by Gemini embedding, by shared words if
//      that fails) and up to three validated past crew reports of the type
//      (crew_report_examples, without names);
//   4. asks the language model (Groq first, Gemini if Groq fails, as
//      generate-report) to fill in the form's answers and write a short
//      narrative, as JSON;
//   5. keeps only the form's allowed answers and numbers that are in the
//      notes (fill.ts), and answers with them. Nothing is saved but the
//      run's timing (crew_report_fill); the responder checks the answers
//      and submits the report as usual.
//
// Secrets: the same as generate-report (GROQ_API_KEYS or GROQ_API_KEY,
// GEMINI_API_KEYS or GEMINI_API_KEY; optional GROQ_MODEL, GEMINI_MODEL,
// GEMINI_EMBEDDING_MODEL). Deploy with JWT checking on.

import {
  buildPrompt,
  closest,
  type IncidentType,
  keysFrom,
  maxNotes,
  type Passage,
  readFilled,
  redact,
  rotated,
  systemInstruction,
  withKeys,
} from "./fill.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const geminiKeys = keysFrom(Deno.env.get("GEMINI_API_KEYS"), Deno.env.get("GEMINI_API_KEY"));
const groqKeys = keysFrom(Deno.env.get("GROQ_API_KEYS"), Deno.env.get("GROQ_API_KEY"));
const geminiModel = Deno.env.get("GEMINI_MODEL") || "gemini-3.8-flash";
const embeddingModel = Deno.env.get("GEMINI_EMBEDDING_MODEL") || "gemini-embedding-001";
const groqModel = Deno.env.get("GROQ_MODEL") || "openai/gpt-oss-120b";
const gemini = "https://generativelanguage.googleapis.com/v1beta";
const groq = "https://api.groq.com/openai/v1/chat/completions";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

async function rpc<T>(
  name: string,
  params: Record<string, unknown>,
  authorization = `Bearer ${serviceKey}`,
): Promise<{ ok: boolean; data: T | null; code: string | null }> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: authorization === `Bearer ${serviceKey}` ? serviceKey! : (anonKey ?? serviceKey!),
      Authorization: authorization,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });
  const body = await res.text();
  let data: unknown = null;
  try {
    data = body ? JSON.parse(body) : null;
  } catch {
    // Not JSON.
  }
  const code = !res.ok && data && typeof data === "object"
    ? String((data as { message?: unknown }).message ?? "")
    : null;
  return { ok: res.ok, data: res.ok ? (data as T) : null, code };
}

async function passagesFor(type: string): Promise<Passage[]> {
  const res = await fetch(
    `${url}/rest/v1/report_reference?select=reference_id,title,body,embedding,embedding_model&section_key=eq.crew_${type}&order=reference_id`,
    { headers: { apikey: serviceKey!, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!res.ok) throw new Error(`report_reference: HTTP ${res.status}`);
  return ((await res.json()) as Record<string, unknown>[]).map((r) => ({
    id: r.reference_id as number,
    title: r.title as string,
    body: r.body as string,
    embedding: r.embedding_model === embeddingModel && Array.isArray(r.embedding)
      ? (r.embedding as number[])
      : null,
  }));
}

async function embed(key: string, texts: string[], taskType: string): Promise<number[][]> {
  const res = await fetch(`${gemini}/models/${embeddingModel}:batchEmbedContents`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      requests: texts.map((text) => ({
        model: `models/${embeddingModel}`,
        content: { parts: [{ text }] },
        taskType,
        outputDimensionality: 768,
      })),
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`embedding: HTTP ${res.status}`);
  const data = (await res.json()) as { embeddings?: { values?: number[] }[] };
  const out = (data.embeddings ?? []).map((e) => e.values ?? []);
  if (out.length !== texts.length || out.some((v) => v.length === 0)) throw new Error("embedding: unexpected answer");
  return out;
}

async function askGroq(key: string, prompt: string): Promise<string> {
  const res = await fetch(groq, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: groqModel,
      temperature: 0.1,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemInstruction },
        { role: "user", content: prompt },
      ],
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`groq: HTTP ${res.status}`);
  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const text = data.choices?.[0]?.message?.content ?? "";
  if (!text) throw new Error("groq: empty answer");
  return text;
}

async function askGemini(key: string, prompt: string): Promise<string> {
  const res = await fetch(`${gemini}/models/${geminiModel}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (!res.ok) throw new Error(`gemini: HTTP ${res.status}`);
  const data = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
  if (!text) throw new Error("gemini: empty answer");
  return text;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not_configured" });
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json(401, { error: "not_allowed" });

  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  const incidentId = typeof body?.incident_id === "string" ? body.incident_id : "";
  const notes = typeof body?.notes === "string" ? body.notes.trim() : "";
  if (!incidentId || notes.length < 3 || notes.length > maxNotes) return json(400, { error: "invalid_value" });

  const begun = await rpc<{ fill_id: number; type: string | null; names: string[] }>(
    "begin_crew_report_fill",
    { p_incident_id: incidentId },
    authorization,
  );
  if (!begun.ok || !begun.data) {
    const limited = begun.code === "rate_limited";
    return json(limited ? 429 : 403, { error: limited ? "rate_limited" : "not_allowed" });
  }
  const { fill_id: fillId, names } = begun.data;
  const type = (["medical", "flood", "fire", "structural"].includes(begun.data.type ?? "")
    ? begun.data.type
    : "structural") as IncidentType;
  const started = Date.now();
  let model = groqKeys.length ? groqModel : geminiModel;
  let retrieval = "words";
  const finish = (ok: boolean, detail: string | null) =>
    rpc("finish_crew_report_fill", {
      p_fill_id: fillId,
      p_ok: ok,
      p_model: model,
      p_duration_ms: Date.now() - started,
      p_retrieval: retrieval,
      p_detail: detail,
    }).catch(() => {});

  if (geminiKeys.length + groqKeys.length === 0) {
    await finish(false, "not set up");
    return json(503, { error: "not_set_up" });
  }

  try {
    const safeNotes = redact(notes, names ?? []);
    const all = await passagesFor(type);
    let notesVector: number[] | null = null;
    try {
      const keys = rotated(geminiKeys, fillId);
      const missing = all.filter((p) => !p.embedding);
      if (missing.length) {
        const made = await withKeys(keys, (k) =>
          embed(k, missing.map((p) => `${p.title}\n${p.body}`), "RETRIEVAL_DOCUMENT"), 10_000);
        await Promise.all(missing.map((p, i) => {
          p.embedding = made[i];
          return rpc("record_reference_embedding", {
            p_reference_id: p.id,
            p_model: embeddingModel,
            p_embedding: made[i],
          });
        }));
      }
      [notesVector] = await withKeys(keys, (k) => embed(k, [safeNotes], "RETRIEVAL_QUERY"), 10_000);
      retrieval = "embedding";
    } catch {
      for (const p of all) p.embedding = null;
    }
    const passages = closest(safeNotes, notesVector, all, 3);
    const examples = await rpc<unknown[]>("crew_report_examples", { p_type: type, p_limit: 3 });
    const prompt = buildPrompt(type, safeNotes, passages, examples.data ?? []);

    const read = (text: string) => {
      const filled = readFilled(text, type, safeNotes);
      if (!filled) throw new Error("model: not the JSON asked for");
      return filled;
    };
    let filled;
    try {
      filled = await withKeys(rotated(groqKeys, fillId), async (k) => read(await askGroq(k, prompt)), 40_000);
      model = groqModel;
    } catch (e) {
      if (!geminiKeys.length) throw e;
      filled = await withKeys(rotated(geminiKeys, fillId), async (k) => read(await askGemini(k, prompt)), 25_000);
      model = geminiModel;
    }

    await finish(true, filled.check.length ? filled.check.join("; ") : null);
    return json(200, {
      answers: filled.answers,
      figures: filled.figures,
      narrative: filled.narrative,
      check: filled.check,
      references: passages.map((p) => ({ id: p.id, title: p.title })),
      examples: (examples.data ?? []).length,
      model,
      retrieval,
      ms: Date.now() - started,
    });
  } catch (e) {
    const error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
    await finish(false, error);
    return json(502, { error: "failed", detail: error });
  }
});
