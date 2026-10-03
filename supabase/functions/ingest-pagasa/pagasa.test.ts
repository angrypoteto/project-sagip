// Run with: node --test supabase/functions/ingest-pagasa/pagasa.test.ts
//
// Fixtures (fixtures/): PAGASA's NCR page and bulletin page as saved on
// 2026-10-03 (no warning, no cyclone), and the text of three Tropical
// Cyclone Bulletins as the Edge Function extracts it (unpdf 1.8.1):
// Kristine (2024) no. 14 and 18, with Metro Manila under Wind Signal No. 2,
// and Queenie (2026) no. 5, far out at sea. The Kristine PDFs come from the
// pagasa-parser/bulletin-archive mirror. Pages with a warning or a cyclone
// in effect are made here from the saved ones, using PAGASA's own wording.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  coversManila,
  htmlText,
  pagasaTime,
  parseBulletinPage,
  parseCycloneBulletin,
  parseRainfallWarning,
} from "./pagasa.ts";
import { bulletinPage, ingest, type IngestDeps } from "./ingest.ts";

const fixture = (name: string) =>
  readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

const ncrNone = fixture("ncr_no_warning_2026-10-03.html");
const bulletinNone = fixture("bulletin_none_2026-10-03.html");
const kristine14 = fixture("kristine_tcb14.txt");
const kristine18 = fixture("kristine_tcb18.txt");
const queenie5 = fixture("queenie_tcb5.txt");

const noWarning = "<div>As of today, there is no Heavy Rainfall Warning Issued.</div>";
function ncrWith(block: string): string {
  assert.ok(ncrNone.includes(noWarning));
  return ncrNone.replace(noWarning, `<div>${block}</div>`);
}
const orangeOverManila = ncrWith(
  "<h5>Heavy Rainfall Warning No. 3 #NCR_PRSD</h5>" +
    "<p>Weather System: Southwest Monsoon (Habagat)</p>" +
    "<p>Issued at: 11:00 AM, 07 September 2026(Monday)</p>" +
    "<p>ORANGE WARNING LEVEL: Metro Manila, Bataan, Zambales.</p>" +
    "<p>YELLOW WARNING LEVEL: Bulacan, Pampanga, Cavite(Magallanes, Naic).</p>" +
    "<p>ASSOCIATED HAZARD: FLOODING in flood-prone areas.</p>",
);
const yellowElsewhere = ncrWith(
  "<h5>Heavy Rainfall Warning No. 1 #NCR_PRSD</h5>" +
    "<p>Issued at: 9:50 AM, 07 September 2026(Monday)</p>" +
    "<p>YELLOW WARNING LEVEL: Bataan, Cavite(Magallanes, General Emilio Aguinaldo).</p>" +
    "<p>ASSOCIATED HAZARD: FLOODING in flood-prone areas. Meanwhile, light to moderate rains over Metro Manila.</p>",
);

const cycloneOn = "<h3>No Active Tropical Cyclone within the Philippine Area of Responsibility</h3>";
const bulletinActive = bulletinNone.replace(
  cycloneOn,
  '<h3>Severe Tropical Storm KRISTINE</h3>' +
    '<a href="https://pubfiles.pagasa.dost.gov.ph/tamss/weather/bulletin/TCB%2317_kristine.pdf">TCB#17</a>' +
    '<a href="https://pubfiles.pagasa.dost.gov.ph/tamss/weather/bulletin/TCB%2318_kristine.pdf">TCB#18</a>',
);

// ------------------------------------------------------------ helpers

test("page text: tags, scripts, and entities gone", () => {
  const t = htmlText("<p>A&amp;B</p><script>x=1</script><b>25&deg;</b>&#8211;");
  assert.equal(t, "A&B\n25°\n–");
});

test("Metro Manila, its parts, and what does not count", () => {
  assert.ok(coversManila("Bulacan, Metro Manila, Cavite"));
  assert.ok(coversManila("Bataan, Metro\nManila, Cavite"));
  assert.ok(coversManila("the National Capital Region"));
  assert.ok(coversManila("the western portion of Metro Manila (City of Manila, Pasay City)"));
  assert.ok(!coversManila("the northern portion of Metro Manila (Caloocan City, Valenzuela City)"));
  assert.ok(!coversManila("the coastal waters of Manila Bay, Bataan"));
  assert.ok(!coversManila("Bulacan, Pampanga"));
});

test("PAGASA's issue times in Manila time", () => {
  assert.equal(pagasaTime("8:00 PM, 23 October 2024"), "2024-10-23T20:00:00+08:00");
  assert.equal(
    pagasaTime("1:18 AM, 03 October 2026(Saturday)"),
    "2026-10-03T01:18:00+08:00",
  );
  assert.equal(pagasaTime("12:30 AM, 1 May 2025"), "2025-05-01T00:30:00+08:00");
  assert.equal(pagasaTime("noon"), null);
});

// ------------------------------------------------------------ rainfall

test("the saved NCR page: no rainfall warning", () => {
  assert.deepEqual(parseRainfallWarning(ncrNone), { state: "none", mmPerHour: 0 });
});

test("Orange over Metro Manila reads as 15 mm/hr", () => {
  assert.deepEqual(parseRainfallWarning(orangeOverManila), {
    state: "warning",
    level: "orange",
    mmPerHour: 15,
    number: 3,
    issued: "2026-09-07T11:00:00+08:00",
  });
});

test("a warning for other provinces is not Manila's", () => {
  const r = parseRainfallWarning(yellowElsewhere);
  assert.equal(r.state, "warning");
  assert.equal(r.state === "warning" && r.level, null);
  assert.equal(r.state === "warning" && r.mmPerHour, 0);
});

test("a changed page is reported, not read as calm", () => {
  const r = parseRainfallWarning(ncrNone.replace(noWarning, "<div>Rainfall: see map</div>"));
  assert.equal(r.state, "unreadable");
});

// ------------------------------------------------------------ cyclones

test("the saved bulletin page: no cyclone, old bulletins ignored", () => {
  assert.deepEqual(parseBulletinPage(bulletinNone, bulletinPage), { state: "none" });
});

test("with a cyclone, the latest bulletin's PDF", () => {
  assert.deepEqual(parseBulletinPage(bulletinActive, bulletinPage), {
    state: "active",
    number: 18,
    pdfUrl: "https://pubfiles.pagasa.dost.gov.ph/tamss/weather/bulletin/TCB%2318_kristine.pdf",
  });
});

test("Kristine no. 14: Metro Manila under Signal No. 2, no surge for Manila", () => {
  assert.deepEqual(parseCycloneBulletin(kristine14), {
    state: "bulletin",
    number: 14,
    name: "KRISTINE",
    issued: "2024-10-23T20:00:00+08:00",
    signal: 2,
    surgeM: 0,
    final: false,
  });
});

test("Kristine no. 18 reads the same way", () => {
  const r = parseCycloneBulletin(kristine18);
  assert.equal(r.state, "bulletin");
  assert.equal(r.state === "bulletin" && r.number, 18);
  assert.equal(r.state === "bulletin" && r.signal, 2);
});

test("Queenie no. 5, far at sea: no signal, no surge", () => {
  const r = parseCycloneBulletin(queenie5);
  assert.equal(r.state === "bulletin" && r.signal, 0);
  assert.equal(r.state === "bulletin" && r.surgeM, 0);
  assert.equal(r.state === "bulletin" && r.name, "QUEENIE");
});

test("a storm surge warning that names Metro Manila gives its height", () => {
  const text = kristine14.replace(
    "coastal localities of Ilocos Norte,",
    "coastal localities of Metro Manila, Cavite, Bataan, Ilocos Norte,",
  ).replace("storm surge up to 2.0 m", "storm surge of 2.1 to 3.0 m");
  const r = parseCycloneBulletin(text);
  assert.equal(r.state === "bulletin" && r.surgeM, 3);
});

test("anything else is not a bulletin", () => {
  assert.equal(parseCycloneBulletin("Weather Advisory No. 5").state, "unreadable");
});

// ------------------------------------------------------------ one run

function fakeDeps(pages: Record<string, string>, pdfs: Record<string, string> = {}) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const deps: IngestDeps = {
    getText: async (u) => {
      if (!(u in pages)) throw new Error(`HTTP 503 for ${u}`);
      return pages[u];
    },
    getBytes: async (u) => {
      if (!(u in pdfs)) throw new Error(`HTTP 404 for ${u}`);
      return new TextEncoder().encode(pdfs[u]);
    },
    pdfText: async (b) => new TextDecoder().decode(b),
    rpc: async <T>(name: string, params: Record<string, unknown>) => {
      calls.push({ name, params });
      return (name === "record_pagasa_reading" ? "recorded" : null) as T;
    },
  };
  return { deps, calls };
}

const ncr = "https://bagong.pagasa.dost.gov.ph/regional-forecast/ncrprsd";
const kristinePdf =
  "https://pubfiles.pagasa.dost.gov.ph/tamss/weather/bulletin/TCB%2318_kristine.pdf";

test("a calm day: zeros recorded, both sources fine", async () => {
  const { deps, calls } = fakeDeps({ [ncr]: ncrNone, [bulletinPage]: bulletinNone });
  const s = await ingest(deps);
  assert.equal(s.recorded, "recorded");
  assert.deepEqual(calls[0], {
    name: "record_pagasa_reading",
    params: { p_rainfall: 0, p_signal: 0, p_surge_m: 0 },
  });
  assert.deepEqual(
    calls.slice(1).map((c) => [c.params.p_source, c.params.p_ok]),
    [["pagasa_rainfall", true], ["pagasa_cyclone", true]],
  );
});

test("a typhoon and an orange warning: 15 mm/hr, Signal No. 2", async () => {
  const { deps, calls } = fakeDeps(
    { [ncr]: orangeOverManila, [bulletinPage]: bulletinActive },
    { [kristinePdf]: kristine18 },
  );
  await ingest(deps);
  assert.deepEqual(calls[0].params, { p_rainfall: 15, p_signal: 2, p_surge_m: 0 });
  assert.equal((calls[2].params.p_seen as { number: number }).number, 18);
});

test("a page that cannot be read keeps the last value and is reported", async () => {
  const { deps, calls } = fakeDeps({ [ncr]: ncrNone }); // bulletin page down
  const s = await ingest(deps);
  assert.equal(s.cyclone.ok, false);
  assert.deepEqual(calls[0].params, { p_rainfall: 0, p_signal: null, p_surge_m: null });
  const cyclone = calls.find((c) => c.params.p_source === "pagasa_cyclone")!;
  assert.equal(cyclone.params.p_ok, false);
  assert.match(String(cyclone.params.p_error), /503/);
});

test("both down: nothing recorded, both reported", async () => {
  const { deps, calls } = fakeDeps({});
  const s = await ingest(deps);
  assert.equal(s.recorded, null);
  assert.deepEqual(calls.map((c) => c.name), ["record_feed_status", "record_feed_status"]);
});
