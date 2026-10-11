// Run with: node --test supabase/functions/generate-report/rag.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildPrompt,
  cosine,
  numbersIn,
  overlap,
  readAnswer,
  readRequest,
  type Reference,
  retrieve,
  type Section,
  unknownNumbers,
} from "./rag.ts";

const sections: Section[] = [
  {
    key: "incidents",
    title: "Incidents reported",
    body: "14 incidents were received: 9 flood, 3 fire, 2 medical. 1 false report.",
  },
  {
    key: "response",
    title: "Response actions",
    body: "6 units were deployed in 12 dispatches. Median dispatch time 4 min 12 s.",
  },
];
const source = { incidents: 14, sos: 11, clusters: 3, dispatches: 12, units_deployed: 6, median_dispatch_s: 252 };

const ref = (id: number, sectionKey: string | null, title: string, body: string, embedding: number[] | null = null): Reference =>
  ({ id, sectionKey, title, body, embedding });

test("the request must be sections and figures, within the report's limits", () => {
  assert.deepEqual(readRequest({ sections, source })?.sections.length, 2);
  assert.equal(readRequest(null), null);
  assert.equal(readRequest({ sections: [], source }), null);
  assert.equal(readRequest({ sections, source: [] }), null);
  assert.equal(readRequest({ sections: [{ key: "a", title: " ", body: "" }], source }), null);
  assert.equal(readRequest({ sections: [{ key: "a", title: "A", body: "x".repeat(6001) }], source }), null);
  assert.equal(readRequest({ sections: [sections[0], sections[0]], source }), null, "keys are unique");
  assert.equal(readRequest({ sections: Array.from({ length: 13 }, (_, i) => ({ key: `k${i}`, title: "T", body: "" })), source }), null);
});

test("cosine similarity", () => {
  assert.equal(cosine([1, 0], [1, 0]), 1);
  assert.equal(cosine([1, 0], [0, 1]), 0);
  assert.equal(cosine([1, 0], [-1, 0]), -1);
  assert.equal(cosine([1, 0], [1, 0, 0]), 0, "different sizes do not compare");
  assert.equal(cosine([0, 0], [1, 0]), 0);
});

test("shared words, without the little ones", () => {
  assert.equal(overlap("flood incidents", "Count the flood incidents by type"), 1);
  assert.equal(overlap("flood incidents", "Response units and dispatches"), 0);
  assert.equal(overlap("the and for", "anything"), 0);
});

test("passages are ranked by embedding, with a nudge for the same section", () => {
  const refs = [
    ref(1, "response", "Response", "units dispatches", [0, 1]),
    ref(2, "incidents", "Incidents", "types counts", [1, 0]),
    ref(3, null, "Style", "formal english", [0.9, 0.1]),
  ];
  assert.deepEqual(retrieve(sections[0], [1, 0], refs, 2).map((r) => r.id), [2, 3]);
  assert.deepEqual(retrieve(sections[1], [0, 1], refs, 1).map((r) => r.id), [1]);
});

test("without embeddings, passages are ranked by shared words", () => {
  const refs = [
    ref(1, null, "Units", "units deployed dispatches median dispatch time"),
    ref(2, null, "Houses", "houses damaged"),
    ref(3, "response", "Response actions", "what to include"),
  ];
  const got = retrieve(sections[1], null, refs, 2).map((r) => r.id);
  assert.deepEqual(got, [1, 3]);
});

test("the prompt carries the figures, each section's facts, and its passages", () => {
  const passages = new Map([["incidents", [ref(2, "incidents", "Structure", "List incidents by type.")]]]);
  const prompt = buildPrompt(sections, source, passages);
  assert.ok(prompt.includes('"incidents":14'));
  assert.ok(prompt.includes('SECTION key="incidents" title="Incidents reported"'));
  assert.ok(prompt.includes("[1] Structure: List incidents by type."));
  assert.ok(prompt.includes("REFERENCE PASSAGES: none"), "the response section has none here");
  const empty = buildPrompt([{ key: "damage", title: "Damage", body: " " }], source, new Map());
  assert.ok(empty.includes("(nothing recorded)"));
});

test("the answer must be the sections asked for", () => {
  const good = JSON.stringify({
    sections: [
      { key: "response", body: " Six units. " },
      { key: "incidents", body: "Fourteen incidents." },
      { key: "extra", body: "ignored" },
    ],
  });
  const read = readAnswer(good, sections)!;
  assert.deepEqual(read.map((s) => s.key), ["incidents", "response"], "in the order asked");
  assert.equal(read[1].body, "Six units.");
  assert.equal(read[0].title, "Incidents reported", "titles are ours, not the model's");
  assert.equal(readAnswer("```json\n" + good + "\n```", sections)?.length, 2);
  assert.equal(readAnswer("Here you go!", sections), null);
  assert.equal(readAnswer(JSON.stringify({ sections: [{ key: "incidents", body: "x" }] }), sections), null);
  assert.equal(readAnswer(JSON.stringify({ sections: [{ key: "incidents", body: "" }, { key: "response", body: "x" }] }), sections), null);
});

test("numbers are compared as numbers", () => {
  assert.deepEqual([...numbersIn("1,204 families, 4.50 m, and 12.")].sort(), ["12", "1204", "4.5"]);
});

test("numbers the facts do not have are pointed out", () => {
  const written: Section[] = [
    { key: "incidents", title: "Incidents reported", body: "A total of 14 incidents were received, 9 of them floods." },
    { key: "response", title: "Response actions", body: "6 units made 12 dispatches and rescued 37 persons in 252 seconds." },
  ];
  assert.deepEqual(unknownNumbers(written, sections, source), [{ key: "response", numbers: ["37"] }]);
  assert.deepEqual(unknownNumbers([written[0]], sections, source), []);
});
