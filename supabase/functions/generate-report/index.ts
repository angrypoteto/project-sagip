// generate-report: the RAG step of the NDRRMC report (Objective 4; plan
// 10.6). Proof of concept.
//
// A6 sends a draft's figures and its assembled sections. For each section
// the function finds the closest reference passages (report_reference, by
// embedding; by shared words if embeddings fail) and asks Google Gemini to
// write the section from the figures, following the passages. It answers
// with the new text; the administrator reviews and saves it. Nothing is
// saved here.
//
// What is sent to Gemini: counts, barangay names, and times. No names,
// numbers, addresses, or coordinates: report_source never had them.
//
// Admins only: the caller's own sign-in is checked by
// begin_report_rewrite(), which also limits rewrites to 20 an hour each.
//
// Secrets: GEMINI_API_KEYS (from Google AI Studio; one key, or several
// separated by commas: when one is refused or over its limit the next is
// tried). If every Gemini key fails, the text is written through Groq
// instead when GROQ_API_KEYS is set (same figures, same rules; passages
// are then matched by shared words unless Gemini's embeddings worked).
// With no key at all the function answers `not_set_up` and A6 keeps the
// assembled draft. GEMINI_API_KEY and GROQ_API_KEY (one key each) are
// read too. Optional: GEMINI_MODEL (default gemini-3.8-flash),
// GEMINI_EMBEDDING_MODEL (default gemini-embedding-001), GROQ_MODEL
// (default openai/gpt-oss-120b).
//
// Deploy with JWT checking on (the default):
//   supabase functions deploy generate-report

import {
  buildPrompt,
  keysFrom,
  readAnswer,
  readRequest,
  type Reference,
  retrieve,
  rotated,
  type Section,
  systemInstruction,
  unknownNumbers,
  withKeys,
} from "./rag.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const geminiKeys = keysFrom(Deno.env.get("GEMINI_API_KEYS"), Deno.env.get("GEMINI_API_KEY"));
const groqKeys = keysFrom(Deno.env.get("GROQ_API_KEYS"), Deno.env.get("GROQ_API_KEY"));
const model = Deno.env.get("GEMINI_MODEL") || "gemini-3.8-flash";
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

/** A database function, as the service role or as the caller. */
async function rpc<T>(
  name: string,
  params: Record<string, unknown>,
  authorization = `Bearer ${serviceKey}`,
): Promise<{ ok: boolean; status: number; data: T | null; code: string | null }> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: authorization === `Bearer ${serviceKey}` ? serviceKey! : (anonKey ?? serviceKey!),
      Authorization: authorization,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });
  const text = await res.text();
  let data: unknown = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    // Not JSON: leave it null.
  }
  const message = !res.ok && data && typeof data === "object"
    ? String((data as { message?: unknown }).message ?? "")
    : null;
  return { ok: res.ok, status: res.status, data: res.ok ? (data as T) : null, code: message };
}

async function references(): Promise<Reference[]> {
  const res = await fetch(
    `${url}/rest/v1/report_reference?select=reference_id,section_key,title,body,embedding,embedding_model&order=reference_id`,
    { headers: { apikey: serviceKey!, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!res.ok) throw new Error(`report_reference: HTTP ${res.status}`);
  const rows = (await res.json()) as Record<string, unknown>[];
  return rows.map((r) => ({
    id: r.reference_id as number,
    sectionKey: (r.section_key as string | null) ?? null,
    title: r.title as string,
    body: r.body as string,
    // An embedding from another model cannot be compared with ours.
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
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`embedding: HTTP ${res.status}`);
  const data = (await res.json()) as { embeddings?: { values?: number[] }[] };
  const out = (data.embeddings ?? []).map((e) => e.values ?? []);
  if (out.length !== texts.length || out.some((v) => v.length === 0)) {
    throw new Error("embedding: unexpected answer");
  }
  return out;
}

async function writeWithGemini(key: string, prompt: string): Promise<string> {
  const res = await fetch(`${gemini}/models/${model}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": key },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
    }),
    signal: AbortSignal.timeout(90_000),
  });
  if (!res.ok) throw new Error(`model: HTTP ${res.status}`);
  const data = (await res.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = (data.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("");
  if (!text) throw new Error("model: empty answer");
  return text;
}

async function writeWithGroq(key: string, prompt: string): Promise<string> {
  const res = await fetch(groq, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: groqModel,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemInstruction },
        { role: "user", content: prompt },
      ],
    }),
    signal: AbortSignal.timeout(90_000),
  });
  if (!res.ok) throw new Error(`groq: HTTP ${res.status}`);
  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const text = data.choices?.[0]?.message?.content ?? "";
  if (!text) throw new Error("groq: empty answer");
  return text;
}

/** The sections from the first model that answers with them: each Gemini
 * key in turn, then each Groq key. */
async function write(
  prompt: string,
  asked: Section[],
  turn: number,
): Promise<{ sections: Section[]; model: string }> {
  const read = (text: string): Section[] => {
    const sections = readAnswer(text, asked);
    if (!sections) throw new Error("model: the answer was not the sections asked for");
    return sections;
  };
  let failure: unknown = new Error("no key");
  if (geminiKeys.length) {
    try {
      const sections = await withKeys(
        rotated(geminiKeys, turn),
        async (k) => read(await writeWithGemini(k, prompt)),
      );
      return { sections, model };
    } catch (e) {
      failure = e;
    }
  }
  if (groqKeys.length) {
    const sections = await withKeys(
      rotated(groqKeys, turn),
      async (k) => read(await writeWithGroq(k, prompt)),
    );
    return { sections, model: groqModel };
  }
  throw failure;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not_configured" });
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json(401, { error: "not_allowed" });

  const input = readRequest(await req.json().catch(() => null));
  if (!input) return json(400, { error: "invalid_value" });

  // Admins only, and the hourly limit: checked with the caller's sign-in.
  const begun = await rpc<number>("begin_report_rewrite", {}, authorization);
  if (!begun.ok || begun.data == null) {
    const limited = begun.code === "rate_limited";
    return json(limited ? 429 : 403, { error: limited ? "rate_limited" : "not_allowed" });
  }
  const rewriteId = begun.data;
  const started = Date.now();
  let usedModel = model;
  const finish = (ok: boolean, detail: string | null) =>
    rpc("finish_report_rewrite", {
      p_rewrite_id: rewriteId,
      p_ok: ok,
      p_model: usedModel,
      p_duration_ms: Date.now() - started,
      p_detail: detail,
    }).catch(() => {});

  if (geminiKeys.length + groqKeys.length === 0) {
    await finish(false, "not set up");
    return json(503, { error: "not_set_up" });
  }

  try {
    const refs = await references();
    // Embeddings are best effort: without them the passages are matched by
    // shared words.
    let sectionVectors: (number[] | null)[] = input.sections.map(() => null);
    let retrieval = "words";
    try {
      const keys = rotated(geminiKeys, rewriteId);
      const missing = refs.filter((r) => !r.embedding);
      if (missing.length) {
        const made = await withKeys(keys, (k) =>
          embed(k, missing.map((r) => `${r.title}\n${r.body}`), "RETRIEVAL_DOCUMENT"), 40_000);
        await Promise.all(missing.map((r, i) => {
          r.embedding = made[i];
          return rpc("record_reference_embedding", {
            p_reference_id: r.id,
            p_model: embeddingModel,
            p_embedding: made[i],
          });
        }));
      }
      sectionVectors = await withKeys(keys, (k) =>
        embed(k, input.sections.map((s) => `${s.title}\n${s.body}`), "RETRIEVAL_QUERY"), 40_000);
      retrieval = "embedding";
    } catch {
      for (const r of refs) r.embedding = null;
    }

    const passages = new Map<string, Reference[]>();
    input.sections.forEach((s, i) => passages.set(s.key, retrieve(s, sectionVectors[i], refs)));
    const written = await write(
      buildPrompt(input.sections, input.source, passages),
      input.sections,
      rewriteId,
    );
    const sections = written.sections;
    usedModel = written.model;

    const used = new Map<number, Reference>();
    for (const list of passages.values()) for (const r of list) used.set(r.id, r);
    await finish(true, retrieval);
    return json(200, {
      sections,
      references: [...used.values()].map((r) => ({ id: r.id, title: r.title })),
      check: unknownNumbers(sections, input.sections, input.source),
      model: usedModel,
      retrieval,
      ms: Date.now() - started,
    });
  } catch (e) {
    const error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
    await finish(false, error);
    return json(502, { error: "failed", detail: error });
  }
});
