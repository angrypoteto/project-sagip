# Writing the team's labelled reports (FR12)

The incident type classifier reads a crowd report's description and
suggests flood, fire, medical, or structural for the dispatcher to confirm
(FR12). It should learn from MDRRMD's own report descriptions (data request
letter, item B). Until those arrive, the plan's fallback (section 10.4) is a
set the team writes and labels itself, disclosed as such in Chapter 3.

Meanwhile the hosted project runs the **sample model** (`v1-sample`, trained
on 1,200 made-up descriptions). The Command Board marks its guesses as
"suggested by the sample model".

## What to write

Copy `data/team_reports_template.csv` to `data/team_reports.csv` and add one
report per row:

| Column | What goes in it |
|---|---|
| `description` | What a resident would type in the app or web form, in their own words |
| `label` | `flood`, `fire`, `medical`, or `structural` (exactly these words) |
| `language` | `fil`, `en`, or `taglish` |
| `writer` | Your initials, so each person's share can be checked |

**How many:** aim for **300 per type (1,200 in all)**. The training script
refuses fewer than 100 per type. Split the writing among the three of you.

**Mix:** about 40% Filipino, 30% English, 30% Taglish in each type.

## How to make them useful

- Write like a worried resident, not like a report: short and long, all
  capitals, no punctuation, typos, "po", SMS shortcuts ("pls", "d2", "asap").
- Vary the details: street, barangay number, how many people, how deep the
  water, what is burning, who is hurt and how.
- Include hard cases on purpose: a fire during a flood, someone injured by a
  collapsed wall (structural, not medical, if the collapse is the emergency),
  "walang sunog, baha lang" (flood).
- One emergency per row. If you cannot decide the type, leave the row out.

## Privacy and fairness

- **Never** use a real person's name, phone number, or exact house address.
  Barangay numbers and street names are fine.
- Do not copy posts from Facebook or the news word for word; write your own.
- Do not write the same sentence twice with one word changed: the script
  counts exact repeats and refuses them.

## When it is done

Give `data/team_reports.csv` to Joshua. Claude then runs:

```
.venv/Scripts/python.exe ml/classifier/train_classifier.py --team
```

That checks the file (types, empty rows, repeats, at least 100 per type),
trains `v2-team` with the thesis parameters (TF-IDF on words and word pairs,
four labels), writes `metrics_team.json` (accuracy on a held-out fifth and on
`data/handwritten_check.csv`), and `build/classifier_model_team.sql`, which
makes `v2-team` the active model on the hosted project. The board then shows
plain "(suggested)" again.

For Chapter 3: "The classifier was trained on N descriptions written and
labelled by the proponents in English, Filipino, and Taglish, in place of
MDRRMD's historical descriptions, which were not available within the study
period."
