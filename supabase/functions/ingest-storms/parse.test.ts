// Run with: node --test supabase/functions/ingest-storms/parse.test.ts
//
// Small made-up samples in the shapes GDACS and PAGASA publish (checked
// against CHAMPI-26 and PAGASA's feed on 2026-11-02).
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  candidates,
  capWarning,
  decode,
  type Feature,
  feedEntries,
  inside,
  labelTime,
  par,
  simplify,
  stormFrom,
} from "./parse.ts";

const circle = (lng: number, lat: number, r = 0.1): number[][] => {
  const ring: number[][] = [];
  for (let k = 0; k <= 8; k++) {
    const a = (k / 8) * 2 * Math.PI;
    ring.push([lng + r * Math.cos(a), lat + r * Math.sin(a)]);
  }
  return ring;
};

const event = {
  eventtype: "TC",
  eventid: 42,
  episodeid: 7,
  eventname: "TESTA-26",
  alertlevel: "Orange",
  iscurrent: "true",
  fromdate: "2026-12-30T00:00:00",
  todate: "2026-12-31T00:00:00",
  datemodified: "2026-12-31T01:00:00",
  source: "JTWC",
  severitydata: { severity: 129.6 },
};

const point = (label: string, lng: number, lat: number): Feature => ({
  geometry: { type: "Polygon", coordinates: [circle(lng, lat)] },
  properties: { Class: "Point_Polygon_Point_0", polygonlabel: label },
});
const leg = (category: string, from: number[], to: number[]): Feature => ({
  geometry: { type: "LineString", coordinates: [from, to] },
  properties: { Class: "Line_Line_0", polygonlabel: category },
});

const geometry = {
  features: [
    point("30/12 00:00 UTC", 132, 12),
    point("31/12 00:00 UTC", 128, 13),
    point("01/01 00:00 UTC", 124, 14),
    leg("TS", [132, 12], [128, 13]),
    leg("TY", [128, 13], [124, 14]),
    {
      geometry: { type: "Polygon", coordinates: [circle(128, 13, 2)] },
      properties: { Class: "Poly_Green", polygonlabel: "60 km/h" },
    },
    {
      geometry: { type: "Polygon", coordinates: [circle(128, 13, 1)] },
      properties: { Class: "Poly_Red", polygonlabel: "" },
    },
    {
      geometry: { type: "Polygon", coordinates: [circle(126, 13.5, 1.5)] },
      properties: { Class: "Poly_Cones" },
    },
  ] as Feature[],
};

test("PAR: Manila is inside, Guam and Taipei are not", () => {
  assert.equal(inside([14.6, 121.0], par), true);
  assert.equal(inside([13.4, 144.8], par), false);
  assert.equal(inside([25.03, 121.56], par), false);
});

test("a label's time takes the year of the storm, across New Year", () => {
  assert.equal(labelTime("31/12 18:00 UTC", "2026-12-30T00:00:00Z"), "2026-12-31T18:00:00.000Z");
  assert.equal(labelTime("01/01 06:00 UTC", "2026-12-30T00:00:00Z"), "2027-01-01T06:00:00.000Z");
  assert.equal(labelTime("Centroid", "2026-12-30T00:00:00Z"), null);
});

test("a storm: its track with categories and forecasts, zones, and cone", () => {
  const s = stormFrom(event, geometry)!;
  assert.equal(s.name, "TESTA-26");
  assert.equal(s.is_current, true);
  assert.equal(s.max_wind_kmh, 130);
  assert.equal(s.to_at, "2026-12-31T00:00:00Z");
  assert.deepEqual(s.track.map((p) => [p.lat, p.lng]), [[12, 132], [13, 128], [14, 124]]);
  assert.deepEqual(s.track.map((p) => p.category), ["TS", "TY", "TY"]);
  assert.deepEqual(s.track.map((p) => p.forecast), [false, false, true]);
  assert.deepEqual(s.wind_zones.map((z) => z.kmh), [60, 120]);
  assert.equal(s.cone.length, 1);
  // [lat, lng]: the cone's points sit around 13.5 N, 126 E.
  assert.ok(Math.abs(s.cone[0][0][0] - 13.5) < 1.6 && Math.abs(s.cone[0][0][1] - 126) < 1.6);
});

test("a storm that never comes near PAR is left out", () => {
  const far = {
    features: [point("30/12 00:00 UTC", 150, 15), point("31/12 00:00 UTC", 152, 18)],
  };
  assert.equal(stormFrom(event, far), null);
});

test("candidates: touching the Philippines or over the western Pacific", () => {
  const f = (name: string, lng: number, lat: number, iso3?: string, type = "TC"): Feature => ({
    geometry: { type: "Point", coordinates: [lng, lat] },
    properties: {
      eventtype: type,
      eventname: name,
      todate: `2026-10-${name.length}T00:00:00`,
      affectedcountries: iso3 ? [{ iso3 }] : [],
    },
  });
  const out = candidates({
    features: [f("INDIA", 82, 13, "IND"), f("PACIFIC", 140, 20), f("PH", 127, 31, "PHL"), f("EQ", 120, 14, "PHL", "EQ")],
  });
  assert.deepEqual(out.map((x) => x.properties.eventname).sort(), ["PACIFIC", "PH"]);
});

test("simplify keeps a ring's ends and drops points closer than the step", () => {
  const ring: [number, number][] = [[0, 0], [0, 0.01], [0, 0.2], [0.2, 0.2], [0.2, 0.21], [0, 0]];
  assert.deepEqual(simplify(ring, 0.1), [[0, 0], [0, 0.2], [0.2, 0.2], [0, 0]]);
});

const feed = `<?xml version='1.0' encoding='UTF-8'?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry>
  <id>urn:uuid:21b29a06-e297-47bd-a79d-20826e724a2c</id>
  <title>TCWS #1   - Batanes</title>
  <updated>2026-10-24T04:50:38+08:00</updated>
  <link type="application/cap+xml" href="https://publicalert.pagasa.dost.gov.ph/output/wcp/21b29a06-e297-47bd-a79d-20826e724a2c.cap"/>
</entry>
</feed>`;

test("the feed's entries, with the kind from the folder", () => {
  assert.deepEqual(feedEntries(feed), [{
    id: "21b29a06-e297-47bd-a79d-20826e724a2c",
    title: "TCWS #1 - Batanes",
    updated: "2026-10-24T04:50:38+08:00",
    href: "https://publicalert.pagasa.dost.gov.ph/output/wcp/21b29a06-e297-47bd-a79d-20826e724a2c.cap",
    kind: "wcp",
  }]);
});

const cap = `<?xml version="1.0"?>
<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>abc</identifier><sender>PAGASA-DOST</sender><sent>2026-10-31T17:02:11+08:00</sent><status>Actual</status><msgType>Update</msgType><scope>Public</scope><references>PAGASA-DOST,old-1,2026-10-31T05:15:35+08:00 PAGASA-DOST,old-2,2026-10-30T05:15:35+08:00</references><info><category>Met</category><event>Tropical Cyclone Warning</event><responseType>Prepare</responseType><urgency>Future</urgency><severity>Minor</severity><expires>2026-11-01T05:02:11+08:00</expires><headline>Typhoon Rosal (CHAMPI) Signal #2</headline><description>Winds of 62-88 kph&#xD;
at 12.1&#xB0;N &amp; more</description><parameter><valueName>Public Storm Warning Signal Level</valueName><value>2</value></parameter><area><areaDesc>Batanes</areaDesc><geocode><valueName>SAME</valueName><value>020900000</value></geocode></area><area><areaDesc>Cagayan</areaDesc><polygon>18.0,121.0 18.5,121.5 18.0,122.0 17.5,121.5 18.0,121.0</polygon></area></info><Signature xmlns="http://www.w3.org/2000/09/xmldsig#"><SignedInfo>x</SignedInfo></Signature></alert>`;

test("a CAP alert: signal, references, areas named or outlined", () => {
  const w = capWarning(cap, "wcp")!;
  assert.equal(w.id, "abc");
  assert.equal(w.event, "Tropical Cyclone Warning");
  assert.equal(w.signal_level, 2);
  assert.equal(w.msg_type, "Update");
  assert.equal(w.expires_at, "2026-11-01T05:02:11+08:00");
  assert.deepEqual(w.refs, ["old-1", "old-2"]);
  assert.equal(w.description, "Winds of 62-88 kph\nat 12.1°N & more");
  assert.deepEqual(w.areas, [
    { name: "Batanes", rings: [] },
    { name: "Cagayan", rings: [[[18, 121], [18.5, 121.5], [18, 122], [17.5, 121.5], [18, 121]]] },
  ]);
  assert.equal(capWarning("<feed/>", "wcp"), null);
});

test("entities are decoded", () => {
  assert.equal(decode("A &amp; B &lt;3 &#176; &#xB0;"), "A & B <3 ° °");
});
