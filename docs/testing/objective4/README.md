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
rewrite time is the server's (`report_rewrite.duration_ms`). The function in
use is `generate-report` version 19: **Groq writes first, Gemini is the
fallback**, and Gemini's embeddings pick the reference passages.

| Run | Period | Incidents | Collect and draft | Rewrite | Model that wrote it | Numbers check |
|---:|---|---:|---:|---:|---|---|
| 1 | Last 7 days | 4 | 0.3 s | 4.1 s | Groq `gpt-oss-120b` | passed |
| 2 | Last 7 days | 4 | 0.2 s | 3.1 s | Groq `gpt-oss-120b` | passed |
| 3 | Last 7 days | 4 | 0.2 s | 3.9 s | Groq `gpt-oss-120b` | passed |
| 4 | Last 30 days | 59 | 0.5 s | 4.7 s | Groq `gpt-oss-120b` | passed |
| 5 | Last 30 days | 59 | 0.2 s | 4.4 s | Groq `gpt-oss-120b` | passed |
| 6 | Last 30 days | 59 | 0.2 s | 3.9 s | Groq `gpt-oss-120b` | passed |

**Summary:** collect and draft in 0.2 to 0.5 s; rewrite median **3.9 s**
(range 3.1 to 4.7 s); **6 of 6** rewrites succeeded; **6 of 6** passed the
numbers check (every number in the new text is in the records); section 6
(Remarks, the administrator's own) was left untouched in 6 of 6. The machine
time for a full, rewritten draft is therefore **about 5 seconds**. What
remains is the administrator's reading, the remarks, and marking it final:
part B measures that.

### How it got here (all runs are in `system_runs.csv`)

| Step | Rewrite time | What changed |
|---|---:|---|
| First run | 114.7 s | Gemini first, up to 100 s before the Groq fallback; the model wrote section 6; a time came out as "36.41555 s" |
| Version 18 (six runs) | median 49.1 s | Section 6 never sent to the model; figures rounded before the prompt; Gemini limited to 30 s. Gemini still answered in none of the six runs, so Groq wrote every report after Gemini's 30 s |
| **Version 19 (six runs, live)** | **median 3.9 s** | Joshua, 2026-11-12: "if the gemini is not working then we can just use groq". Groq writes first; Gemini only if Groq fails |

## B. The timed comparison

Not run yet: see `TIMED-TRIAL.md`.
