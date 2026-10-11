# Feature checklist (as of 2026-10-11, evening)

For Joshua to check by hand, one line at a time. Tick the box when you have seen
it work. The details behind each line are in `docs/PROGRESS.md`.

**How to open each app**

| App | Command (run in the folder shown) | Sign in with |
|---|---|---|
| Dashboard, sample data | `apps/dashboard`: `flutter run -d chrome` | the demo account buttons |
| Dashboard, real database | `apps/dashboard`: `flutter run -d chrome --dart-define-from-file=.env` | your admin account |
| Resident web form, sample data | `apps/dashboard`: `flutter run -d chrome -t lib/main_webform.dart` | any number, the demo code shown |
| Mobile app, sample data | `flutter emulators --launch sagip_pixel`, then `apps/mobile`: `flutter run` | the demo account buttons |

Marks: **[S]** works on sample data only for now. **[P]** needs a real phone to
check properly. **[W]** built, but waits on a setting or a decision from you
before it works for real (listed in part 6).

---

## 1. Built: dashboard (dispatcher and admin)

### Sign-in and shell
- [ ] D1 Staff sign in; a wrong password is explained
- [ ] Top bar: PAGASA summary, live/offline dot, clock, user menu, theme switch
- [ ] Side menu hides the admin pages when you sign in as a dispatcher
- [ ] G1 Not found page (type a wrong address); G2 Session expired returns you to the same page
- [ ] D11 My account: details, theme, change password, keyboard shortcuts, sound switch

### Command Board (dispatcher)
- [ ] D2 Map view: incidents, units, unverified reports, layers, legend, zoom
- [ ] D3 List view (table) of the same queue, ranked by priority
- [ ] A new SOS shows at once as Pending Verification, with a toast and two short tones
- [ ] Enter opens the first incident; arrow keys move; Esc closes
- [ ] D4 Incident drawer: status, rank, wait timer, timeline
- [ ] D4 Verification: call resident, SMS check, mark verified, mark false report
- [ ] D4 Confirm or change the incident type
- [ ] D4 Resident and vulnerable household shown; the phone number is masked until revealed
- [ ] D4 Priority breakdown (why this incident ranks where it does)
- [ ] D4 Suggested units ranked by road travel time; Assign; the route is drawn
- [ ] D4 Suggestions go around confirmed floods; the drawer says how many floods count
- [ ] D5 Override dialog (a reason is required) and "Choose another unit"
- [ ] D4 Reassign and Mark resolved
- [ ] D4 "What the resident was told": each rescue update with its text and push result
- [ ] D4 Simulated incidents carry a "Simulated" mark

### Other dispatcher pages
- [ ] D6 Crowd reports: confirmed clusters with a 50 m ring and a count; single reports stay unverified
- [ ] D6 Barangay boundaries layer
- [ ] D7 Units table: status counts, stale-GPS flag
- [ ] D8 72-hour forecast: flood, fire, storm surge; ranked list, map shading, barangay panel **[S]**
- [ ] D9 Vulnerable Resident Priority List; numbers masked; revealing one is written to the audit log
- [ ] D10 Weather readings marked Warning or Critical against the thresholds
- [ ] D10 "Alerts sent" list with each channel's result
- [ ] D10 Issue an advisory (pick barangays by number, name, or district) and End it
- [ ] D10 Feeds card: last read and last success for PAGASA and PHIVOLCS (real database)
- [ ] D10 PHIVOLCS earthquakes near Manila with "Relay as advisory"

### Admin pages
- [ ] A1 Accounts: create staff (temporary password shown once), edit, reset password, deactivate, reactivate
- [ ] A1 Suspend a resident and lift it
- [ ] A2 Resources: add, edit, retire, restore a unit; put a responder on a unit
- [ ] A3 Priority weights with the live ranking preview
- [ ] A3 Alert thresholds, channel switches, hotline and gateway number, crowd report limit
- [ ] A3 Simulation mode: Typhoon, Heavy rain, Calm readings
- [ ] A3 Simulated incidents: an SOS, an SOS with a senior citizen, three crowd reports
- [ ] A4 Analytics: KPI tiles, incidents per day, tables by type, barangay, unit
- [ ] A4 "SOS delivery (Objective 3)" table
- [ ] A5 Reports list; A6 report editor: pick a period, review, edit, save draft, mark final
- [ ] A6 Download PDF (the stored copy once the report is final)
- [ ] A7 Audit log shows every action above with who did it

---

## 2. Built: resident web form

- [ ] W1 Sign in with number and code; create an account (name, barangay, terms)
- [ ] W2 Crowd report: description, type, location, the hourly limit explained
- [ ] W3 Confirmation
- [ ] There is no SOS button on the web form (SOS is app only)

---

## 3. Built: mobile app, resident

- [ ] S1 Splash, then the right screens for the role
- [ ] S2 Welcome and permissions: each one says why before asking
- [ ] S3 Sign in by mobile number; S4 Register; S5 Code **[S]** (real texted codes: **[W]**)
- [ ] R1 Home: greeting, PAGASA strip, SOS button, GPS-off warning
- [ ] R1 Send an SOS; R2 SOS status with the timeline and elapsed time
- [ ] R2 Add details (type, people, extra help, note)
- [ ] R3 Track responder on the map, with ETA
- [ ] R4 Report a hazard; outside Manila refused; 5 an hour
- [ ] R5 Location picker: move the pin, Use my GPS, barangay search
- [ ] R6 My activity: SOS and Reports tabs
- [ ] R7 Alerts list with unread count; Forecast tab for my barangay **[S]**
- [ ] R8 Alert detail; opening it marks it read
- [ ] "About your SOS" notices on the Alerts tab (unit on the way, arrived, closed)
- [ ] R9 Vulnerability profile; R10 Consent; R11 Household member; withdraw consent
- [ ] S7 Me: details, theme, test notification, privacy notice, request deletion, sign out
- [ ] Offline banner on every screen (turn on airplane mode)
- [ ] S6 Offline queue sheet: saved records, Try sending now
- [ ] An SOS sent offline is delivered when you come back online, with its original time
- [ ] S6 "Text it myself" opens the messages app with the SOS text ready **[P]**
- [ ] SOS by SMS when there is signal but no data **[P] [W]**
- [ ] SOS relayed by a nearby phone over Bluetooth, also in the background **[P]**
- [ ] Push notifications arrive (works on the emulator; real phone still to check **[P]**)

## 4. Built: mobile app, responder

- [ ] F1 Home: unit, status control, location sharing line, weather strip
- [ ] F1 "Keep S.A.G.I.P. running" battery prompt
- [ ] F2 Incoming assignment: full screen, the app's own tone, vibration, Accept **[P]** for the sound
- [ ] F3 Assignment detail: map, where to go, what was reported, vulnerable types
- [ ] F4 Navigation: road route, next turn, ETA, re-routes when you leave the route
- [ ] F4 Spoken directions and the mute button **[P]**
- [ ] F4 "You're at the scene" and Arrived within 50 m
- [ ] F5 On scene: real-emergency check (No needs a reason), people found
- [ ] F6 Completion report: outcome, persons assisted, damage, notes; saved offline, sent later
- [ ] F7 Assignment history
- [ ] The map around a job is saved for offline use
- [ ] Location keeps being shared with the screen off **[P]**

---

## 5. Built: behind the scenes (nothing to click; I can show you each)

- [ ] Row Level Security on every table, with 371 written checks
- [ ] Every dispatch action, status change, and verification is written to the audit log
- [ ] DBSCAN groups crowd reports (50 m, 3 reports, 60 minutes); one report is never auto-confirmed
- [ ] The classifier tags each new crowd report with a type (sample model)
- [ ] Dijkstra on the road graph, timed and logged for Chapter 4
- [ ] The priority score, from the A3 weights
- [ ] The threshold engine raises alerts from weather readings
- [ ] PAGASA feed read every 10 minutes; PHIVOLCS every 15 minutes
- [ ] The LSTM and KDE trained on sample data (`ml/`)

---

## 6. Built, but waiting on you **[W]**

| Feature | What it waits for |
|---|---|
| Texted sign-in codes for residents on the real database | Turn on Phone sign-in and the Send SMS hook in Supabase |
| All outgoing SMS (alerts, rescue texts, SMS check, codes) | Set up the spare phone as the gateway and add its three secrets |
| SOS by SMS coming in, and the YES/NO reply to an SMS check | The same gateway phone, plus `SMS_INTAKE_SECRET` and its webhook |
| Live forecast feed (a new forecast every 6 hours) | Paste `20261003130000_forecast_live.sql` in the SQL editor |
| Posting alerts to the Facebook Page | A Page token |
| Data retention on the real database | Paste `20261011030000_data_retention.sql` in the SQL editor |
| The language model for A6 | Add the secrets `GEMINI_API_KEYS` and `GROQ_API_KEYS` in the Supabase dashboard |
| Dashboard and web form on the internet | Your yes to deploying on Vercel |
| New sample data (alerts, forecasts, past rescues) on the real database | Run `select public.reset_demo_data();` |
| Hotline number in the apps | MDRRMD gives the number; you enter it on A3 |

---

## 7. Built on 2026-10-11

These work on sample data, and on the real database too, except: "Data
retention" needs the one migration you paste (`supabase/README.md`, "The
migrations of 2026-10-11"), and the language model needs its keys as secrets.

- [ ] D10 "River water levels": stations with their levels, raised ones first, "Relay as advisory" (live on the real database: 17 stations)
- [ ] R2 "Cancel SOS": choose a reason; the card says the SOS is still open; "I still need help" takes it back
- [ ] D4 "Asked to cancel" on the queue row; "Close as cancelled" in the drawer (asks first)
- [ ] R2 shows "SOS cancelled" after the dispatcher closes it
- [ ] The resident's newest position: move the emulator's location while an SOS is open; the drawer says how far the resident moved **[P]**
- [ ] F3 shows "The resident asked to cancel" and goes to the resident's newest position
- [ ] A3 "Data retention": 6 to 60 months, saved and in the audit log
- [ ] A6 "Rewrite with the language model": without keys it says it is not set up **[W]** (add `GEMINI_API_KEYS` and `GROQ_API_KEYS` as secrets)
- [ ] Me, Language, Filipino: the whole mobile app reads in Filipino (read it with the team)
- [ ] D3 List view: with the drawer open the table ends where the drawer starts

## 8. Not built yet

| Feature | Why not |
|---|---|
| Self-hosted Manila map tiles | Needs a host; the app uses public OpenStreetMap tiles for now |
| Classifier and forecast trained on real MDRRMD records | Waits for the MDRRMD data |
| Forecast accuracy figures and a run selector on D8 | Waits for the real model |
| Risk level rule for the forecast (final) | Open questions Q21, Q22; a provisional rule is in use |
| Declining an assignment (responder) | Open question Q10, second half |
| Filipino for the dashboard and the web form | Not asked for; the dashboard is for staff |

## 9. Dropped (Joshua, 2026-10-11)

- Nearest evacuation center on R7 (Q38). The thesis still promises it to
  residents, so the Docs role removes that line from the thesis.
- A separate pin for a household member who lives elsewhere. Household members
  use the resident's home address.

## 10. Never tested on a real phone

Everything marked **[P]** above, plus: the Bluetooth relay between three phones,
the SMS fallback end to end, and the Objective 3 trial.
