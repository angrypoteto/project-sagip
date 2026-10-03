// Run with: node --test supabase/functions/send-alerts/alerts.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";

import { semaphoreNumber } from "../send-sms/sms.ts";
import {
  acceptedCount,
  alertSmsText,
  chunk,
  type ClaimedConfirmation,
  cleanNumbers,
  confirmationSmsText,
  ended,
  facebookOutcome,
  facebookPostText,
  notSetUp,
  planBroadcast,
  smsOutcome,
} from "./alerts.ts";

// The six texts the threshold engine writes (private.weather_alert_text).
const engineAlerts: [string, string][] = [
  [
    "Heavy rainfall warning",
    "PAGASA reports rain of 22 mm per hour over Manila. Flooding is possible in low-lying areas.",
  ],
  [
    "Torrential rainfall warning",
    "PAGASA reports rain of 35 mm per hour over Manila. Serious flooding is expected in low-lying areas.",
  ],
  [
    "Wind Signal No. 2 raised over Manila",
    "PAGASA raised Tropical Cyclone Wind Signal No. 2. Strong winds are expected.",
  ],
  [
    "Wind Signal No. 3 raised over Manila",
    "PAGASA raised Tropical Cyclone Wind Signal No. 3. Destructive winds are expected.",
  ],
  [
    "Storm surge warning for Manila Bay",
    "A storm surge of up to 1.5 m is possible along Manila Bay.",
  ],
  [
    "Storm surge warning for Manila Bay",
    "A storm surge of up to 2.5 m is expected along Manila Bay. Coastal areas may flood quickly.",
  ],
];

test("every automatic alert fits one SMS, whole", () => {
  for (const [title, body] of engineAlerts) {
    const text = alertSmsText(title, body);
    assert.ok(text.length <= 160, `${text.length}: ${text}`);
    assert.ok(text.startsWith(`S.A.G.I.P.: ${title}.`));
    assert.ok(text.endsWith(body), "nothing was cut");
  }
});

test("a long alert is cut at a word, never inside the title", () => {
  const long = alertSmsText(
    "Flooding on Dapitan St and España Blvd",
    "Rescue teams are responding to knee-deep flooding along Dapitan St. Avoid the area if you can. " +
      "If you need rescue, hold the SOS button in the app.",
  );
  assert.ok(long.length <= 160);
  assert.ok(long.startsWith("S.A.G.I.P.: Flooding on Dapitan St and España Blvd."));
  assert.ok(long.endsWith("…"));
  assert.ok(!/\s…$/.test(long), "no space before the ellipsis");
  assert.equal(alertSmsText("Road closed!", "  Use  Quezon Blvd. "), "S.A.G.I.P.: Road closed. Use Quezon Blvd.");
});

test("numbers are made local, unique, and Philippine mobiles only", () => {
  assert.deepEqual(
    cleanNumbers(
      ["+63 917 000 4821", "09170004821", "639180003310", "0285270000", "", "12025550123"],
      semaphoreNumber,
    ),
    ["09170004821", "09180003310"],
  );
});

test("the daily cap decides who is texted now", () => {
  const numbers = ["09170000001", "09170000002", "09170000003"];
  assert.deepEqual(planBroadcast(numbers, 500), { send: numbers, overCap: 0 });
  assert.deepEqual(planBroadcast(numbers, 2), { send: numbers.slice(0, 2), overCap: 1 });
  assert.deepEqual(planBroadcast(numbers, 0), { send: [], overCap: 3 });
  assert.deepEqual(planBroadcast(numbers, -4), { send: [], overCap: 3 });
});

test("batches hold at most 1,000 numbers", () => {
  const batches = chunk(Array.from({ length: 2300 }, (_, i) => i));
  assert.deepEqual(batches.map((b) => b.length), [1000, 1000, 300]);
  assert.deepEqual(chunk([]), []);
});

test("accepted texts are counted from Semaphore's answer", () => {
  const answer = [
    { message_id: 1, recipient: "639170000001", status: "Pending" },
    { message_id: 2, recipient: "639170000002", status: "Queued" },
    { message_id: 3, recipient: "639170000003", status: "Failed" },
  ];
  assert.equal(acceptedCount(true, answer, 3), 2);
  assert.equal(acceptedCount(false, answer, 3), 0, "a failed call sends nothing");
  assert.equal(acceptedCount(true, { message: "Invalid API key" }, 3), 0, "an error object");
  assert.equal(acceptedCount(true, null, 3), 0);
});

test("the outcome carries the counts and why some were not sent", () => {
  assert.deepEqual(smsOutcome(120, 120, 0), {
    status: "sent",
    recipients: 120,
    delivered: 120,
    failed: 0,
    detail: null,
  });
  const capped = smsOutcome(120, 100, 20);
  assert.equal(capped.status, "sent");
  assert.equal(capped.failed, 20);
  assert.equal(capped.detail, "20 not sent: the daily limit was reached");
  assert.equal(smsOutcome(120, 0, 0).status, "failed");
  const nobody = smsOutcome(0, 0, 0);
  assert.equal(nobody.status, "sent", "nobody to text is not a failure");
  assert.equal(nobody.detail, "No registered residents in the affected barangays");
});

test("channels with no provider say why", () => {
  assert.equal(notSetUp("push").status, "notSetUp");
  assert.equal(notSetUp("push").detail, "Push needs the Firebase project");
  assert.equal(notSetUp("facebook").detail, "Facebook posting needs the page's access token");
  assert.equal(notSetUp("sms").detail, "No Semaphore key");
  assert.equal(ended.status, "ended");
});

test("every rescue confirmation fits one SMS and names the incident", () => {
  const base: ClaimedConfirmation = {
    confirmation_id: 1,
    incident_id: "INC-0147",
    kind: "assigned",
    unit_call_sign: "R-03",
    to: "09170004821",
  };
  for (const kind of ["assigned", "onScene", "resolved"] as const) {
    for (const unit of ["R-03", "Rescue Boat 12", null, "  "]) {
      const text = confirmationSmsText({ ...base, kind, unit_call_sign: unit });
      assert.ok(text.length <= 160, `${kind}: ${text.length} characters`);
      assert.ok(text.startsWith("S.A.G.I.P.: "));
      assert.ok(text.includes("INC-0147"));
      assert.ok(!text.includes("09170004821"), "no number in the text");
    }
  }
  assert.equal(
    confirmationSmsText({ ...base, unit_call_sign: null }),
    "S.A.G.I.P.: A rescue team has been sent to your location. Stay where you are if it is safe and keep your phone on. Ref INC-0147.",
  );
});

test("a Facebook post names the level and the areas", () => {
  const alert = {
    alert_id: "alert-a",
    level: "critical",
    title: "Flood warning ",
    body: "Water is rising along the Pasig River.",
    barangays: ["Barangay 649", "Barangay 650"],
    ended: false,
  };
  assert.equal(
    facebookPostText(alert),
    "[CRITICAL] Flood warning\n\nWater is rising along the Pasig River.\n\n" +
      "Areas: Barangay 649, Barangay 650\n\n" +
      "Sent through S.A.G.I.P. For rescue, hold SOS in the S.A.G.I.P. app or call MDRRMD.",
  );
  const many = Array.from({ length: 25 }, (_, i) => `Barangay ${i + 1}`);
  assert.ok(facebookPostText({ ...alert, barangays: many }).includes("Barangay 20, and 5 more"));
  assert.ok(facebookPostText({ ...alert, body: "x".repeat(5000) }).length <= 2000);
});

test("the Graph API's answer becomes the delivery outcome", () => {
  assert.equal(facebookOutcome(true, { id: "1_2" }, 200).status, "sent");
  assert.equal(facebookOutcome(true, { id: "1_2" }, 200).detail, "post 1_2");
  assert.equal(
    facebookOutcome(false, { error: { message: "Bad token", code: 190 } }, 400).detail,
    "Facebook refused the post (HTTP 400): Bad token",
  );
  assert.equal(facebookOutcome(false, null, 502).detail, "Facebook refused the post (HTTP 502)");
});
