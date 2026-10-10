# Brief template for ChatGPT (Codex)

Claude writes one brief per task and Joshua pastes it to ChatGPT. Keep each brief
small: one task, few files. A small brief is what stops ChatGPT drifting from the
plan. Start every brief with the line below, then fill the sections.

---

```
You are the builder for Project S.A.G.I.P. Read AGENTS.md first and follow it
exactly. Do only this task. Do not change the plan, the style, or any file
outside the list.

TASK: <short name>   BRANCH: gpt/<short-name>

GOAL
<one paragraph: what should work when you are done, and for whom>

REQUIREMENT IDS: <FR/NFR numbers from the plan, if any>

FILES YOU MAY CHANGE OR CREATE
- <path>: <what changes>

FILES YOU MUST NOT TOUCH
- everything else, especially docs/, CLAUDE.md, AGENTS.md, supabase/migrations/
  (unless listed above), pubspec files

COPY THIS PATTERN
- <path and name of an existing, similar piece of code>

DETAILS
- <exact behaviour, field names, strings (keys for the ARB file), edge cases>
- <four states to handle: loading, empty, error, offline>

DO NOT
- add packages, rename things, reformat other code, or add features not listed
- <task-specific traps>

ACCEPTANCE (all must pass; paste the output)
- flutter analyze            (zero issues, in each package you touched)
- flutter test               (in each package you touched)
- <the specific new tests, and what each must check>
- <for database work: the RLS test lines to add and that they pass>

REPLY WITH
Files changed / Commands run (with results) / Not done or unsure.
```

---

## How Claude reviews the result

1. Joshua pastes ChatGPT's reply, or says the branch name.
2. Claude reads the diff (`git diff main...gpt/<name>`) and checks it against the
   plan, `CLAUDE.md`, and `docs/CONVENTIONS.md`: scope, style, tests, security
   rules, domain vocabulary, no stray files.
3. Claude runs `flutter analyze` and the tests itself. ChatGPT's "passed" is not
   taken on trust.
4. Claude either merges (and updates `docs/PROGRESS.md` and the plan) or writes a
   fix brief that lists exactly what to change.

## Rules for the pair

- One brief at a time per area of the code. Never give two briefs that touch the
  same file at once.
- Claude alone edits the plan, `docs/PROGRESS.md`, `CLAUDE.md`, and `AGENTS.md`.
- Anything needing a Supabase dashboard setting, a deploy, a secret, or a push
  stays with Joshua (and Claude where Claude has the connector).
- If ChatGPT says the brief is unclear or conflicts with the code, that goes back
  to Claude to fix the brief. ChatGPT does not decide.
- Briefs that suit ChatGPT well: one screen, one repository implementation, one
  Edge Function with its Node tests, one set of unit tests. Keep design decisions,
  schema design, algorithms with thesis parameters, and anything touching RLS or
  patient/resident privacy with Claude.
