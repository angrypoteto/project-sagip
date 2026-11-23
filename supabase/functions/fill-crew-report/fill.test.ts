// Run with: node --test supabase/functions/fill-crew-report/fill.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildPrompt, closest, countsIn, hospitalFrom, numbersIn, readFilled, redact } from "./fill.ts";

test("names and phone numbers leave the notes", () => {
  const out = redact("Si Maria Santos, 0917 000 1234, sakit ng dibdib. Maria ok na.", ["Maria Santos"]);
  assert.equal(out.includes("Maria"), false);
  assert.equal(out.includes("Santos"), false);
  assert.equal(out.includes("1234"), false);
  assert.match(out, /the patient/);
  assert.match(out, /\[number\]/);
  assert.equal(redact("2 patients, 19 inches", []), "2 patients, 19 inches", "short numbers stay");
});

test("only the form's answers are kept; numbers must be in the notes", () => {
  const notes = "Motorcycle hit a pedestrian, overspeeding. Two patients: lolo about 70 to OSMA, rider male 28 to PGH.";
  const raw = JSON.stringify({
    answers: {
      emr_type: "roadAccident",
      accident_cause: "overspeeding",
      vehicles: ["motorcycle", "pedestrian", "spaceship"],
      patients: [
        { name: "Juan", age: "from61", gender: "male", hospital: "OSMA", chief_complaint: "leg injury" },
        { age: "from26To30", gender: "male", hospital: "Philippine General Hospital (PGH)" },
      ],
    },
    figures: { injured: 2, persons_assisted: 2, houses_damaged: 9 },
    narrative: "A motorcycle hit a pedestrian. Two patients were taken to hospital.",
  });
  const f = readFilled(raw, "medical", notes)!;
  assert.equal(f.answers.emr_type, "roadAccident");
  assert.deepEqual(f.answers.vehicles, ["motorcycle", "pedestrian"]);
  const patients = f.answers.patients as Record<string, unknown>[];
  assert.equal(patients.length, 2);
  assert.equal("name" in patients[0], false, "never a name");
  assert.equal(patients[0].hospital, "Ospital ng Maynila (OSMA)");
  assert.deepEqual(f.figures, { injured: 2, persons_assisted: 2 });
  assert.ok(f.check.some((c) => c.includes("houses damaged 9")));
});

test("flood: the cyclone's signal only when said; fire: damage from the notes", () => {
  const flood = readFilled(JSON.stringify({
    answers: { flood_cause: "tropicalCyclone", cyclone_name: "Uwan", wind_signal: 3, flood_level: "knee", flood_status: "nplv" },
    narrative: "Knee-deep flood.",
  }), "flood", "Baha hanggang tuhod dahil sa bagyong Uwan, signal 2.")!;
  assert.equal(flood.answers.wind_signal, undefined, "3 was not in the notes");
  assert.equal(flood.answers.flood_level, "knee");
  const fire = readFilled(JSON.stringify({
    answers: { fire_kind: "residential", highest_alarm: "secondAlarm", estimated_damage: 150000, affected_individuals: 12 },
    narrative: "A house fire reached the 2nd alarm.",
  }), "fire", "Residential fire, 2nd alarm, damage 150,000 pesos, 12 affected.")!;
  assert.equal(fire.answers.estimated_damage, 150000);
  assert.equal(fire.answers.affected_individuals, 12);
  assert.equal(fire.check.length, 0);
});

test("a narrative number not in the notes is flagged; bad JSON is refused", () => {
  const f = readFilled(JSON.stringify({ answers: {}, narrative: "Five houses burned." }), "fire", "house fire")!;
  assert.ok(f.check.some((c) => c.includes("5")));
  assert.equal(readFilled("not json", "fire", "x"), null);
  assert.ok(numbersIn("dalawa at 1,500").has("2"));
  assert.ok(numbersIn("dalawa at 1,500").has("1500"));
});

test("hospitals by short name; passages by shared words; the prompt lists the answers", () => {
  assert.equal(hospitalFrom("pgh"), "Philippine General Hospital (PGH)");
  assert.equal(hospitalFrom("Mars General"), undefined);
  const passages = [
    { id: 1, title: "Flood level", body: "knee deep waist deep", embedding: null },
    { id: 2, title: "Cause", body: "clogged waterways rainfall", embedding: null },
  ];
  assert.equal(closest("waist deep water", null, passages, 1)[0].id, 1);
  const prompt = buildPrompt("flood", "knee deep", passages, []);
  assert.match(prompt, /"flood_level": one of "gutter"/);
  assert.match(prompt, /No validated past reports/);
});

test("plain counts are read from the notes, with or without commas", () => {
  // The 2026-11-17 trial's note, typed without commas.
  assert.deepEqual(
    countsIn("Knee deep na baha sa Kahilum St dahil sa malakas na ulan hindi passable sa light vehicles 3 families 12 persons assisted walang injured"),
    { persons_assisted: 12, injured: 0, affected_families: 3 },
  );
  assert.deepEqual(
    countsIn("3 families, 12 persons assisted, no missing"),
    { persons_assisted: 12, missing: 0, affected_families: 3 },
  );
  assert.deepEqual(countsIn("tatlong pamilya, apat na bahay nasunog, 1 sugatan"), { injured: 1, affected_families: 3, houses_damaged: 4 });
  assert.deepEqual(countsIn("families: 4"), { affected_families: 4 });
  assert.deepEqual(countsIn("Patient 2 the rider, 28, male, brought to PGH"), {});
  // The model left the families out: the notes' count fills it in.
  const f = readFilled(
    JSON.stringify({ answers: { flood_level: "knee" }, figures: { persons_assisted: 12 }, narrative: "" }),
    "flood",
    "knee deep 3 families 12 persons assisted walang injured",
  )!;
  assert.deepEqual(f.figures, { persons_assisted: 12, injured: 0, affected_families: 3 });
});
