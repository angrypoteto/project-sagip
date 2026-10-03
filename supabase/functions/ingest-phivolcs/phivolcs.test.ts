// Run with: node --test supabase/functions/ingest-phivolcs/phivolcs.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { kmBetween, manila, nearManila, parseEarthquakes, phivolcsTime } from "./phivolcs.ts";

const page = readFileSync(
  new URL("./fixtures/phivolcs_2026-10-03.html", import.meta.url),
  "utf8",
);

test("PHIVOLCS times are Philippine time", () => {
  assert.equal(phivolcsTime("03 October 2026 - 08:33 PM"), "2026-10-03T20:33:00+08:00");
  assert.equal(phivolcsTime("01 October 2026 - 12:05 AM"), "2026-10-01T00:05:00+08:00");
  assert.equal(phivolcsTime("Date - Time(Philippine Time)"), null);
});

test("every event row of the saved page is read; headings are not", () => {
  const quakes = parseEarthquakes(page);
  assert.ok(quakes.length >= 35, `${quakes.length} events`);
  const first = quakes[0];
  assert.equal(first.occurredAt, "2026-10-03T20:33:00+08:00");
  assert.equal(first.latitude, 13.17);
  assert.equal(first.longitude, 120.14);
  assert.equal(first.depthKm, 26);
  assert.equal(first.magnitude, 2);
  assert.equal(first.location, "044 km S 52° W of Paluan (Occidental Mindoro)");
  assert.ok(first.bulletinUrl!.startsWith("https://earthquake.phivolcs.dost.gov.ph/2026_Earthquake_Information/October/"));
  assert.equal(new Set(quakes.map((q) => q.key)).size, quakes.length, "keys are unique");
});

test("distance from Manila City Hall", () => {
  assert.equal(kmBetween(manila.lat, manila.lng, manila.lat, manila.lng), 0);
  const lobo = parseEarthquakes(page).find((q) => q.location.includes("Lobo (Batangas)"))!;
  assert.ok(Math.abs(lobo.distanceKm - 123) < 2, `${lobo.distanceKm} km`);
});

test("only the events near Manila and recent are kept", () => {
  const quakes = parseEarthquakes(page);
  const now = new Date("2026-10-03T21:00:00+08:00");
  const near = nearManila(quakes, now);
  assert.ok(near.length > 0 && near.length < quakes.length);
  assert.ok(near.every((q) => q.distanceKm <= 300));
  assert.ok(near.some((q) => q.location.includes("Lobo (Batangas)")));
  assert.equal(nearManila(quakes, new Date("2026-10-10T00:00:00+08:00")).length, 0, "two days later, none");
});

test("a page with no event rows gives nothing", () => {
  assert.deepEqual(parseEarthquakes("<html><body><table><tr><td>Maintenance</td></tr></table></body></html>"), []);
});
