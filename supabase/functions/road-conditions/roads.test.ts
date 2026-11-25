// Run with: node --test supabase/functions/road-conditions/roads.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { incidentsUrl, roadItems } from "./roads.ts";

const line = { type: "LineString", coordinates: [[120.98, 14.6], [120.99, 14.61]] };

test("the request asks for Manila's box now, with the key encoded", () => {
  const u = incidentsUrl("a+b");
  assert.match(u, /bbox=120\.94,14\.55,121\.03,14\.645/);
  assert.match(u, /timeValidityFilter=present/);
  assert.match(u, /key=a%2Bb$/);
});

test("jams, closures, and floods are kept; other kinds are not", () => {
  const items = roadItems({
    incidents: [
      { geometry: line, properties: { id: "j", iconCategory: 6, magnitudeOfDelay: 3, from: "A", to: "B", delay: 240, length: 900 } },
      { geometry: line, properties: { id: "c", iconCategory: 8, magnitudeOfDelay: 4 } },
      { geometry: line, properties: { id: "f", iconCategory: 11 } },
      { geometry: line, properties: { id: "a", iconCategory: 1 } },
      { geometry: line, properties: { id: "w", iconCategory: 9 } },
    ],
  });
  assert.deepEqual(items.map((i) => [i.id, i.kind, i.severity]), [
    ["j", "jam", 3],
    ["c", "closed", 4],
    ["f", "flooding", 0],
  ]);
  assert.equal(items[0].delay, 240);
  assert.equal(items[0].from, "A");
});

test("a closure because of flooding counts as flooding", () => {
  const [i] = roadItems({
    incidents: [{
      geometry: line,
      properties: { id: "x", iconCategory: 8, events: [{ description: "Closed due to flooding" }] },
    }],
  });
  assert.equal(i.kind, "flooding");
});

test("a point becomes a two-point line; bad shapes and missing ids are dropped", () => {
  const items = roadItems({
    incidents: [
      { geometry: { type: "Point", coordinates: [120.98, 14.6] }, properties: { id: "p", iconCategory: 6 } },
      { geometry: { type: "LineString", coordinates: [[120.98, 14.6]] }, properties: { id: "s", iconCategory: 6 } },
      { geometry: line, properties: { iconCategory: 6 } },
      { geometry: { type: "LineString", coordinates: [[999, 14.6], [120.98, 14.6]] }, properties: { id: "b", iconCategory: 6 } },
    ],
  });
  assert.deepEqual(items.map((i) => i.id), ["p"]);
  assert.deepEqual(items[0].path, [[120.98, 14.6], [120.98, 14.6]]);
});

test("an answer without incidents gives none", () => {
  assert.deepEqual(roadItems(null), []);
  assert.deepEqual(roadItems({ incidents: "x" }), []);
});
