# Objective 4 timed trial: steps

**Changed 2026-11-17 (Joshua):** the post-incident report is made and
submitted by the **responder (field rescue personnel)**, not by an
administrator or dispatcher. Today the responder fills in MDRRMD's own
online forms on a phone (Emergency Medical Response Form, Flood
Monitoring/Roving Form, Fire Incident 2026 form), and MDRRMD records the
report. In S.A.G.I.P. the responder files the completion report (F6),
which now asks the same questions as those forms, with photos, and MDRRMD
**validates that report** on the dashboard. The trial compares the two.

**Reduction = (T_current − T_with_system) / T_current × 100.** Target: 30%
or more.

## What is timed

| Step | Current way | With S.A.G.I.P. |
|---|---|---|
| **1. The responder's report** | Open MDRRMD's form for the incident type, fill in every question (encoder or team leader, date and time, map pin, typed address, district, admin district or zone, barangay, month, quarter, the type-specific questions, photos), press Submit | From **Complete rescue** to **Submit report** in F6. Date, time, place, district, barangay, month and quarter are filled in by the app; the responder answers the type-specific questions and adds photos |
| **2. MDRRMD records it** | MDRRMD's usual step for a submitted form (opening it and recording it in their records) | The dispatcher opens the incident, reads the crew's report and photos, presses **Review**, then **Validate** |

T for each method = step 1 + step 2. Report each step on its own too.

## Who and what

| Item | Notes |
|---|---|
| **Responder** | An MDRRMD field rescuer who uses the forms today (best), or a team member who has practised both. The same person does both methods for a card, **current way first**, so knowing the facts does not speed up the form they already know |
| **MDRRMD staff** | For step 2: the person who records the forms today, and a dispatcher on staff.sagip.me |
| **Cards** | The same facts for both methods. One card per form: a road accident with 2 patients (EMR), a knee-deep flood from heavy rainfall (flood), a residential fire at 2nd alarm (fire). Write each card's answers in advance (patients' age, gender, hospital, complaint; flood level and status; fire type, alarm, damage, affected) |
| **Photos** | The same photos in the phone's gallery for both methods: EMR 3 (the form's minimum: PCR front and back plus one), fire 2, flood none |
| **Phones** | The responder's own phone for the current form; the POCO with S.A.G.I.P. build 33, signed in as a responder, for F6. For F6 the incident must be assigned to the responder's unit and marked on scene first (not timed) |
| **Timer** | A phone stopwatch, or Claude timing from the phones and the board as in Objectives 1 and 3; fill in `timed_trial_tally.csv` |

## Steps for one card

1. Read the card to the responder.
2. **Current way, step 1:** start when the responder opens the form; stop
   when the form shows it was submitted.
3. **Current way, step 2:** start when MDRRMD opens the submitted form;
   stop when it is recorded.
4. **S.A.G.I.P., step 1:** start when the responder taps **Complete rescue**;
   stop at **Report sent**.
5. **S.A.G.I.P., step 2:** start when the dispatcher opens the incident;
   stop at **Validated**.
6. Check that both reports hold the same answers; note any difference.

## Counting

| Card | T_current (s) | T_with_system (s) | Reduction |
|---|---:|---:|---:|
| EMR, road accident, 2 patients | | | |
| Flood, knee deep | | | |
| Fire, residential, 2nd alarm | | | |
| **Median** | | | |

Also report:
- step 1 and step 2 apart, so the panel sees where the time goes;
- the questions the app filled in for the responder (place, date and
  time, district, barangay, month, quarter);
- part A in `README.md`: from validated reports, the MDRRMD report for
  NDRRMC is drafted and rewritten in about 5 seconds of machine time.

## After the trial

Send the tally sheet. Trial incidents are closed as false reports, and
their crew reports stay on the hosted project as test records.
