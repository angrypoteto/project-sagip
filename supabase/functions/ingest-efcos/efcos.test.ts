// Run with: node --test supabase/functions/ingest-efcos/efcos.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { levelState, parseLevels, riverTime } from "./efcos.ts";

const page = readFileSync(
  new URL("./fixtures/water_2026-10-11.json", import.meta.url),
  "utf8",
);

test("river times are Philippine time", () => {
  assert.equal(riverTime("202610111120"), "2026-10-11T11:20:00+08:00");
  assert.equal(riverTime("2026"), null);
});

test("every station with coordinates is read, sorted by name, with unique codes", () => {
  const levels = parseLevels(page);
  assert.equal(levels.length, 17);
  const names = levels.map((l) => l.name);
  assert.deepEqual(names, [...names].sort((a, b) => a.localeCompare(b)));
  assert.equal(new Set(levels.map((l) => l.code)).size, levels.length, "codes are unique");
});

test("Fort Santiago's flagged level and thresholds are read", () => {
  const level = parseLevels(page).find((l) => l.name === "Fort Santiago")!;
  assert.equal(level.levelM, 11.42);
  assert.equal(level.flagged, true);
  assert.equal(level.changeM, -0.02);
  assert.equal(level.alertM, 12);
  assert.equal(level.alarmM, 12.5);
  assert.equal(level.criticalM, 13);
  assert.equal(level.observedAt, "2026-10-11T11:20:00+08:00");
  assert.equal(levelState(level), "normal");
});

test("Burgos has no numeric change and is not flagged", () => {
  const level = parseLevels(page).find((l) => l.name === "Burgos")!;
  assert.equal(level.changeM, null);
  assert.equal(level.flagged, false);
});

test("Angono has no threshold state", () => {
  const level = parseLevels(page).find((l) => l.name === "Angono")!;
  assert.equal(levelState(level), null);
});

test("La Mesa Dam has reached alarm", () => {
  const level = parseLevels(page).find((l) => l.name === "La Mesa Dam")!;
  assert.equal(level.levelM, 79.48);
  assert.equal(level.alertM, 79);
  assert.equal(level.alarmM, 79.3);
  assert.equal(level.criticalM, 79.5);
  assert.equal(levelState(level), "alarm");
});

test("Ugong has reached critical", () => {
  const level = parseLevels(page).find((l) => l.name === "Ugong")!;
  assert.equal(level.levelM, 20.57);
  assert.equal(level.criticalM, 16.6);
  assert.equal(levelState(level), "critical");
});

test("the river level list must be a JSON array", () => {
  assert.throws(() => parseLevels("{}"), { message: "The river level list is not a JSON array" });
});
