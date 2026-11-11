# Objective 4 testing: report preparation time (RAG)

*Objective 4: to decrease the administrative processing time required to
formulate official post-disaster assessments by at least 30% by utilizing
Retrieval-Augmented Generation (RAG) AI for automated NDRRMC PDF report
generation.*

**Reduction = (T_by_hand − T_with_system) / T_by_hand × 100**, for the same
period, by the same kind of person (an MDRRMD administrator).

There are two parts:

| Part | What it measures | Status |
|---|---|---|
| **A. The system's own time** (this page) | How long the system takes to collect the figures, draft the report, and rewrite it with the language model, on the live project | **Done 2026-11-12**: results below |
| **B. The timed comparison** (`TIMED-TRIAL.md`) | An administrator preparing the same report by hand and with the system, each timed from start to a finished report | **Not run yet**: needs an MDRRMD administrator (or a team member acting as one) |

Chapter 4 needs B for the 30% figure. A shows what the system adds to the
administrator's time, and that it works reliably.

## Files

| File | What it holds |
|---|---|
| `system_runs.csv` | One row per timed run: period, incidents, drafting time, rewrite time, model, numbers check |
| `TIMED-TRIAL.md` | The steps for part B |
| `timed_trial_tally.csv` | The sheet for part B |

## A. The system's own time (live project, 2026-11-12)

Six runs on staff.sagip.me, signed in as an administrator, through the real
A6 page: *New report → period → Collect records → Rewrite with the language
model*. Nothing was saved. The drafting time is the page's own timer; the
rewrite time is the server's (`report_rewrite.duration_ms`).

| Run | Period | Incidents | Collect and draft | Rewrite | Model that wrote it | Numbers check |
|---:|---|---:|---:|---:|---|---|
| 1 | Last 7 days | 4 | 0.2 s | 54.1 s | Groq `gpt-oss-120b` | passed |
| 2 | Last 7 days | 4 | 0.4 s | 36.2 s | Groq `gpt-oss-120b` | passed |
| 3 | Last 7 days | 4 | 0.2 s | 54.2 s | Groq `gpt-oss-120b` | passed |
| 4 | Last 30 days | 59 | 0.2 s | 35.4 s | Groq `gpt-oss-120b` | passed |
| 5 | Last 30 days | 59 | 0.2 s | 57.7 s | Groq `gpt-oss-120b` | passed |
| 6 | Last 30 days | 59 | 0.4 s | 44.1 s | Groq `gpt-oss-120b` | passed |

**Summary:** collect and draft in 0.2 to 0.4 s; rewrite median **49.1 s**
(mean 47.0 s, range 35.4 to 57.7 s); **6 of 6** rewrites succeeded; **6 of 6**
passed the numbers check (every number in the new text is in the records);
section 6 (Remarks, the administrator's own) was left untouched in 6 of 6.
The machine time for a full draft is therefore **under one minute**. What
remains is the administrator's reading, the remarks, and marking it final:
part B measures that.

### Found and fixed during the test (before runs 1 to 6)

A first run (not counted) took **114.7 s** and showed three problems, fixed in
`generate-report` version 18 (tests: 15 of 15):

| Problem | Fix |
|---|---|
| The model wrote the administrator's section 6 ("Remarks and recommendations are not available") | Section 6 is never sent to the model and never replaced |
| A median time came out as "36.41555 s" | The model gets the figures rounded as a report states them (times to whole seconds) |
| A slow Gemini held the administrator for up to 100 s before the Groq fallback | Gemini gets 25 s per key and 30 s in all, then Groq (45 s per key) |

**Open:** Gemini (`gemini-3.8-flash`) did not answer within its 30 s in any of
the six runs, so every report was written by the Groq fallback. The fallback
is why the rewrites still succeeded; the primary model's speed (or a smaller
Gemini model) is worth checking before the defense.

## B. The timed comparison

Not run yet: see `TIMED-TRIAL.md`.
