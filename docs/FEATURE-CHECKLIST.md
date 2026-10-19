# Feature checklist (as of 2026-10-19)

For Joshua to check by hand, one line at a time. Tick the box when you have seen
it work. The details behind each line are in `docs/PROGRESS.md`.

**How to open each app**

| App | Command (run in the folder shown) | Sign in with |
|---|---|---|
| Dashboard, real database | `apps/dashboard`: `flutter run -d chrome --release --web-port 5555 --dart-define-from-file=.env` | `admin@sagip.test` or `dispatcher@sagip.test` (your passwords), or a unit account |
| Dashboard on the internet, real database | open `https://staff.sagip.me` (also `https://sagip-dashboard-three.vercel.app`) | the same accounts |
| Resident web form on the internet, real database | open `https://sagip.me` (`www.sagip.me` and `report.sagip.me` forward to it; also `https://sagip-report.vercel.app`) | resident: `917 000 4821`, code `123456` |
| Dashboard, sample data | `apps/dashboard`: `flutter run -d chrome` | the same emails, password `sagip-demo` |
| Resident web form, sample data | `apps/dashboard`: `flutter run -d chrome -t lib/main_webform.dart` | any number, the demo code shown |
| Mobile app on your phone, real database | install `SAGIP-2026-10-19.apk` from your Desktop (it has safe places; your phone still has the build of 2026-10-16), or plug the phone in and ask me | resident: `917 000 4821`, code `123456`; responder: a unit account |
| Mobile app, sample data | `apps/mobile`: `flutter run` (phone plugged in) | "Continue as resident" or "Continue as rescue personnel" |

**The real database today:** no made-up incidents, residents, or forecast. It
holds 10 real stations as units (each with a responder account and made-up
supply levels for the demo), 897 barangays, the settings, 17 river stations, one
resident (the test number), and the incidents you made while testing (12, all
closed). Facebook posting of alerts and incidents is switched on (test Page
"Project SAGIP"), and the hotline is set to (02) 8565-4316.

Marks: **[S]** can only be seen on sample data for now (the real database has
nothing to show for it). **[P]** needs a real phone to check properly. **[W]**
built, but waits on a setting or a decision from you (part 7). **[N]** new or
changed between 2026-10-12 and 2026-10-19.

---

## 1. Built: dashboard (dispatcher and admin)

### Sign-in and shell
- [ ] D1 Staff sign in; a wrong password is explained
- [ ] **[N]** Side menu: icons only; it opens with the names while the pointer is on it; the S.A.G.I.P. mark is at its head
- [ ] **[N]** Top bar: PAGASA signal and rainfall, Live dot, clock, and the account circle (name and role inside its menu)
- [ ] Side menu hides the admin pages when you sign in as a dispatcher
- [ ] G1 Not found page (type a wrong address); G2 Session expired returns you to the same page
- [ ] D11 My account: details, theme, change password, keyboard shortcuts, sound switch

### Command Board (dispatcher)
- [ ] D2 Map view: incidents, units, unverified reports, layers, legend, zoom
- [ ] **[N]** Layers: "Safe places" (off by default) draws them as green rings with an icon (filled for an official evacuation center), and the legend gets a "Safe place" line
- [ ] **[N]** The map stays in view when there is no incident (no "nothing here" note on it)
- [ ] **[N]** The map shows streets and their names under the muted colors
- [ ] **[N]** An SOS with no unit sent yet pings on the map (rings spreading out), and stops when a unit is sent
- [ ] **[N]** "Open the map in its own window" button: the map alone for a second monitor, larger markers, a full screen button, a summary card
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
- [ ] D4 "Asked to cancel" on the queue row; "Close as cancelled" in the drawer (asks first)
- [ ] D4 The drawer says how far the resident moved since the SOS **[P]**

### Units on the map **[N]**
- [ ] A free unit is drawn at its station
- [ ] A unit on a job is drawn where its crew's phone is; its station is a faint outline (a house icon) joined by a dotted line
- [ ] While any incident is open, a free unit whose phone reported in the last 10 minutes also shows a faint marker where its crew is (a person icon)
- [ ] With no incident open, free crews are not shown: stations only
- [ ] Hovering a faint marker says which unit it is and what it is ("its station" or "where its crew is now")
- [ ] **[N]** The legend explains both faint markers: "Station of a unit that is out" (house) and "Where a free crew is" (person) (2026-10-19)
- [ ] A moving unit's marker follows the streets between two reported positions, not a straight line through the blocks **[P]** (walk or drive with the responder phone)
- [ ] Suggested units start from the crew's position when it is recent, otherwise from the station

### Other dispatcher pages
- [ ] D6 Crowd reports: confirmed clusters with a 50 m ring and a count; single reports stay unverified
- [ ] D6 Barangay boundaries layer
- [ ] D7 Units table: status counts, stale-GPS flag
- [ ] **[N]** D7 "Whose" column (MDRRMD, BFP, EMS) and fire trucks as a unit type
- [ ] **[N]** D7 Supplies column: "Low: ...", "Out: ...", "All enough", or "Not reported"; a "N low on supplies" count at the top (the demo levels make it 4)
- [ ] **[N]** D7 Click a unit's supplies: every level with a bar, who reported it and when; nothing can be changed here
- [ ] D8 72-hour forecast: ranked list, barangay panel **[S]**
- [ ] **[N]** D8 The map is color-coded by barangay (a real heat map); click a barangay to open its panel **[S]**
- [ ] D9 Vulnerable Resident Priority List; numbers masked; revealing one is written to the audit log
- [ ] D10 Weather readings marked Warning or Critical against the thresholds
- [ ] D10 "Alerts sent" list with each channel's result
- [ ] D10 Issue an advisory (pick barangays by number, name, or district) and End it
- [ ] D10 Feeds card: last read and last success for PAGASA and PHIVOLCS
- [ ] D10 PHIVOLCS earthquakes near Manila with "Relay as advisory"
- [ ] D10 "River water levels": 17 stations with their levels, raised ones first, "Relay as advisory"

### Admin pages
- [ ] A1 Accounts: create staff (temporary password shown once), edit, reset password, deactivate, reactivate
- [ ] A1 Suspend a resident and lift it
- [ ] A2 Resources: add, edit, retire, restore a unit; put a responder on a unit
- [ ] **[N]** A2 "Station position" in the unit dialog (latitude, longitude); a wrong entry is explained
- [ ] A3 Priority weights with the live ranking preview
- [ ] A3 Alert thresholds, channel switches, hotline and gateway number, crowd report limit
- [ ] **[N]** A3 "Post alerts on the MDRRMD Facebook Page" is on; a real (not simulated) alert appears on the test Page "Project SAGIP" and its delivery line says sent (a test alert went through on 2026-10-13). While the Meta app is unpublished, the post is probably seen only by you
- [ ] **[N]** A3 "Confirmed incidents on the Facebook Page". With it on, one post per flood, fire, or structural incident, edited as it goes: assign a unit to an unverified SOS and "Unverified report: possible ... in <district>" appears; verify it and the same post turns into "Confirmed ..."; mark a false report (or the responder answers No on scene) and it becomes "False alarm ..."; resolve a confirmed one and an "Update ..." line is added ("the person who asked for help is safe" when the resident cancelled it); an unverified one the resident cancels becomes "Update: report withdrawn". Not posted: medical, simulated incidents, the barangay or address, who reported it (first seen working on INC-0165, 2026-10-16)
- [ ] **[N]** The hotline (02) 8565-4316 shows in the mobile app and on the web form
- [ ] **[N]** The map credit is smaller on every map (dashboard, web form, mobile after its next install)
- [ ] A3 "Data retention": 6 to 60 months, saved and in the audit log
- [ ] **[N]** A3 "Unit supplies": the percent at which a supply counts as low (30 by default)
- [ ] A3 Simulation mode: Typhoon, Heavy rain, Calm readings
- [ ] A3 Simulated incidents: an SOS, an SOS with a senior citizen, three crowd reports
- [ ] A4 Analytics: KPI tiles, incidents per day, tables by type, barangay, unit
- [ ] A4 "SOS delivery (Objective 3)" table
- [ ] A5 Reports list; A6 report editor: pick a period, review, edit, save draft, mark final
- [ ] A6 Download PDF (the stored copy once the report is final)
- [ ] A6 "Rewrite with the language model" (the keys are in place; never tried from the page)
- [ ] A7 Audit log shows every action above with who did it
- [ ] **[N]** Incident history (dispatchers and admins): closed incidents by period (today, 7 days, 30 days, chosen dates), filtered by type and how it ended, searched by ID or barangay; a row opens its details (timeline, completion report, Facebook status); Export CSV downloads the filtered list without personal data
- [ ] **[N]** Safe places (admins, 2026-10-19): the list of 750 places from OpenStreetMap; search by name or barangay, pick a kind, "Show hidden places"; hide a wrong place and show it again; "Add place" for MDRRMD's own evacuation center (needs a name; a place outside Manila is refused; marked Official); each change in the audit log
- [ ] **[N]** Incident panel: "Photos (N)" with the photos residents added to the SOS or to the crowd reports in its cluster; a click opens one large
- [ ] **[N]** Incident panel: a line under the type says where its Facebook post stands, and why it is not posted (for example "not posted until the incident type is confirmed")

---

## 2. Built: a responder on the web **[N]**

Sign in on the dashboard with a unit account (for example `bfp.pandacan@sagip.test`).

- [ ] The same frame as the other pages: side menu (only "My unit") and top bar
- [ ] "My unit": the unit's call sign, type, whose it is, station, and status
- [ ] Fuel and tank water: move the slider, Report; the level and "Low" or "Enough" change
- [ ] Stocks (drinking water, medical kits, life vests, rescue gear): on board and a full load; wrong numbers are explained
- [ ] After a report, the dispatcher's Units page shows the new level without a refresh
- [ ] The panel's example: BFP-PANDACAN shows "Low: Tank water" (20%); report 90% and it clears
- [ ] Any other address sends a responder back to "My unit"; My account still opens
- [ ] Each report is in the audit log (sign in as admin, A7)

---

## 3. Built: resident web form

- [ ] W1 Sign in with number and code; create an account (name, barangay, terms)
- [ ] W2 Crowd report: description, type, location, the hourly limit explained
- [ ] W3 Confirmation
- [ ] **[N]** W2: "Add a photo (optional)" on the web form; it goes after the report
- [ ] There is no SOS button on the web form (SOS is app only)
- [ ] **[N]** Both sites open from the internet (the two addresses at the top) and sign-in works there (I checked that they load; sign-in there is yours to check)

---

## 4. Built: mobile app, resident

- [ ] S1 Splash, then the right screens for the role
- [ ] S2 Welcome and permissions: each one says why before asking (a second tap on Allow no longer causes an error)
- [ ] S3 Sign in by mobile number; S4 Create an account; S5 Code (real database: the test number only **[W]**)
- [ ] R1 Home: greeting, PAGASA strip, SOS button, GPS-off warning
- [ ] R1 Send an SOS; it appears on the dashboard's Command Board (seen working on 2026-10-12)
- [ ] R2 SOS status with the timeline and elapsed time
- [ ] R2 Add details (type, people, extra help, note)
- [ ] R2 "Cancel SOS": choose a reason; "I still need help" takes it back; "SOS cancelled" after the dispatcher closes it
- [ ] R3 Track responder on the map, with ETA
- [ ] R4 Report a hazard; outside Manila refused; 5 an hour
- [ ] R5 Location picker: move the pin, Use my GPS, barangay search
- [ ] R6 My activity: SOS and Reports tabs
- [ ] R7 Alerts list with unread count; Forecast tab for my barangay **[S]**
- [ ] R8 Alert detail; opening it marks it read
- [ ] "About your SOS" notices on the Alerts tab (unit on the way, arrived, closed)
- [ ] R9 Vulnerability profile; R10 Consent; R11 Household member; withdraw consent
- [ ] S7 Me: details, theme, language (English or Filipino), test notification, privacy notice, request deletion, sign out
- [ ] Offline banner on every screen (turn on airplane mode)
- [ ] **[N]** After holding SOS, "What is happening?" comes up once with four big buttons and Skip; one tap sets the type (the SOS is already sent). Add details starts with the same big buttons
- [ ] **[N]** R2 "Safe places near you" (right under Track responder): the advice (help is coming to where you are; move only if staying is unsafe), the nearest place once you tapped what is happening, and "See safe places"
- [ ] **[N]** Safe places screen: tap Flood, Fire, Collapse or damage, or Medical; the advice for it; the three nearest on a map (a fire's are at least 300 m away; a flood's are schools, halls, covered courts; medical gives hospitals); tap one to see the way on foot and the minutes. Works offline (airplane mode) from the list saved in the app
- [ ] **[N]** R8 Alert detail: "Safe places near you" (a weather alert opens it on Flood)
- [ ] **[N]** Photos (2026-10-19): after an SOS is sent, "Add a photo" (Take a photo / Choose from gallery), up to 3; "1 of 3 photos added. They are sent after your SOS". In airplane mode the photo waits and goes after the SOS once online
- [ ] **[N]** R4 Report a hazard: "Add a photo (optional)", a preview with a remove button; the photo goes after the report
- [ ] S6 Offline queue sheet: saved records, Try sending now
- [ ] An SOS sent offline is delivered when you come back online, with its original time
- [ ] **[N]** The app no longer flips to offline on one slow answer; it needs two failed checks in a row, and once offline it checks every 5 seconds, so a saved SOS goes within seconds of the connection returning (fixed 2026-10-16)
- [ ] S6 "Text it myself" opens the messages app with the SOS text ready **[P]**
- [ ] SOS by SMS when there is signal but no data **[P] [W]**
- [ ] **[N]** Sending steps (2026-10-19): with no internet, an SOS is tried over data for 20 seconds, then texted, and right after the text (sent or not) passed to nearby phones by Bluetooth, while data keeps reconnecting (no 2-minute wait since build 5). A "Sending your SOS" notification changes at each step ("No internet. Trying again over data" → "SOS sent by SMS to MDRRMD" or "The SMS could not be sent" → "Asking nearby phones to pass on your SOS" → "Your SOS reached MDRRMD"), and R2 shows "How your SOS is being sent" with Data / SMS / Nearby phones. Try it: mobile data off with the SIM in (it should still text), then airplane mode with Bluetooth on (SMS fails, Bluetooth at once) **[P]**
- [ ] SOS relayed by a nearby phone over Bluetooth, also in the background **[P]**
- [ ] **[N]** The gateway's reply (2026-10-19): when the gateway texts back "S.A.G.I.P.: Your SOS was received (INC-…, ref …)", the phone shows "MDRRMD received your SOS by SMS", R2 shows the SOS as received with its incident number, and nearby phones stop being asked; the full record still goes over data later. Only a text from the gateway number with this SOS's code counts. Needs the gateway phone and a number on A3 **[P] [W]**
- [ ] **[N]** The relay notice says only what is true: "Ready to pass on SOS from nearby phones. None waiting" until a nearby phone's SOS is heard, then "Passing on 1 SOS…", then "Sent 1 SOS… to MDRRMD" (2026-10-19; the old one said "listening for SOS nearby" all the time)
- [ ] **[N]** A relayed SOS shows its real sender on the dashboard, with "Relayed by nearby phones (Bluetooth). The sender's phone proved itself with its own key"; the phone that carried it never sees who it is **[P]** (two phones with build 2: one in airplane mode sends, the other online relays)
- [ ] **[N]** Too old an app: "Update S.A.G.I.P." with "Download the update", SOS (residents) and Call MDRRMD still there; never while your SOS is open. Try it: set A3 "Oldest app build allowed" to 3 and open the app (then set it back to 2)
- [ ] **[N]** Your location is a blue dot with an arrow that turns where the phone faces (Track responder, Safe places, the location picker) **[P]**
- [ ] Push notifications arrive **[P]** (your phone is registered as of 2026-10-13, and the test alert’s push was marked sent; you have not said whether it showed on the phone)

## 5. Built: mobile app, responder

- [ ] **[N]** Both sites show the S.A.G.I.P. beacon (the red SOS circle) in the browser tab and as the icon when added to a phone's home screen
- [ ] **[N]** R3 Track responder: the line from the unit to you follows the streets (solid). A dashed straight line only when no road route can be worked out
- [ ] **[N]** S3 Sign in: the logo and heading are centred and the MDRRMD hotline card sits at the bottom of the screen (sign out to see it)
- [ ] F1 Home: unit, status control, location sharing line, weather strip
- [ ] F1 "Keep S.A.G.I.P. running" battery prompt
- [ ] F2 Incoming assignment: full screen, the app's own tone, vibration, Accept **[P]** for the sound
- [ ] F3 Assignment detail: map, where to go, what was reported, vulnerable types
- [ ] F3 shows "The resident asked to cancel" and goes to the resident's newest position
- [ ] F4 Navigation: road route, next turn, ETA, re-routes when you leave the route
- [ ] **[N]** F4 goes around confirmed floods and fires that are not the unit's own job: each is a shaded circle on the map (blue flood, red fire), and the card says "The route goes around N confirmed floods and fires when it can." To see it: confirm a flood or fire on the dashboard between a unit and its job; within half a minute the phone's route bends
- [ ] F4 Spoken directions and the mute button **[P]**
- [ ] F4 "You're at the scene" and Arrived within 50 m
- [ ] F5 On scene: real-emergency check (No needs a reason), people found
- [ ] F6 Completion report: outcome, persons assisted, damage, notes; saved offline, sent later
- [ ] F7 Assignment history
- [ ] The map around a job is saved for offline use
- [ ] **[N]** The phone shares its position every 5 seconds (was 15), also with the screen off **[P]**

---

## 6. Built: behind the scenes (nothing to click; I can show you each)

- [ ] Row Level Security on every table; 495 written checks. On the real data on 2026-10-19: 495 of 495, rolled back (the full file from GitHub at `92831bc`; 30 new checks for safe places)
- [ ] Every dispatch action, status change, and verification is written to the audit log
- [ ] DBSCAN groups crowd reports (50 m, 3 reports, 60 minutes); one report is never auto-confirmed
- [ ] Dijkstra on the road graph, timed and logged for Chapter 4
- [ ] **[N]** Roads near a confirmed open flood count as 4 times slower (150 m); near a confirmed open fire 20 times (100 m), so they are used only when there is no other way. Dashboard: shaded circles on the map, a legend line, and a line under the suggested units. Both numbers are provisional
- [ ] The priority score, from the A3 weights
- [ ] The threshold engine raises alerts from weather readings
- [ ] PAGASA feed read every 10 minutes; PHIVOLCS every 15 minutes; river levels from PAGASA's Pasig-Marikina-Tullahan feed
- [ ] Data retention: closed incidents lose their link to the resident after the set months, every night
- [ ] The classifier (TF-IDF) and the LSTM and KDE: built and tested on sample data only (see part 8)

---

## 7. Built, but waiting on you **[W]**

| Feature | What it waits for |
|---|---|
| Residents signing in with any real number | Phone sign-in is on, but only the test number works. Real numbers need the Send SMS hook (`supabase/README.md`, "Turning on resident sign-in by SMS code") |
| All outgoing SMS (alerts, rescue texts, SMS check, codes) | The spare phone as the gateway and its three secrets, or a Semaphore account |
| SOS by SMS coming in, and the YES/NO reply to an SMS check | The same gateway phone, plus `SMS_INTAKE_SECRET` and its webhook |
| The test post "System test: please disregard" on the Facebook Page | The alert itself was ended on 2026-10-16 (no longer in the resident app). Remove its post from the Page if you do not want it there |
| The second hotline number (0932-662-2322) | The setting holds one number, so only the landline shows. Say so if you want the mobile number instead, or both (a small database change) |
| The Meta app "SAGIP Alerts" and the test Page | Yours to remove after the defense, as you planned (that also ends the tokens) |
| Leftovers of the first relay tag (2026-10-19) | `drop function public.my_relay_tag(); drop function private.relay_sender(uuid); alter table public.manila_resident drop column relay_tag;` in the SQL editor. Nothing uses them; nobody can call them |
| Make the newest build required | After the team installs build 6 (`https://sagip.me/download/sagip.apk`), set A3 "Oldest app build allowed" to 6. APKs before build 2 cannot be asked (they have no check) |
| Removing expired photo files | Retention hides photos from everyone, but the files stay in the bucket until a small cleanup function (Storage API) is written |
| One leftover database function that does nothing | `drop function private.unit_returns_home();` in the SQL editor. Nobody can run it any more (2026-10-13); dropping it is only tidying |

---

## 8. Not done yet (as of 2026-10-19)

The data request letter to MDRRMD (TO Director Angeles, THRU Mr. Verano) is
ready on Joshua's Desktop, `SAGIP-MDRRMD-Data-Request-Letter.docx` (2026-10-19).
Its items A to H are what 8b waits for. MDRRMD's files never go into the
public GitHub repo (the letter promises it); only the trained models do.

### 8a. Can be done now, without waiting on anyone

| What | Where it stands |
|---|---|
| The simulated forecast feed (what the thesis promises: "trained, simulated live feed") | Built, not switched on. Its migration (`forecast_live`) needs a one-line fix that needs your explicit "yes, rewrite it", or you paste it yourself. Then D8 and the resident's Forecast tab show risk levels instead of an empty page |
| Typhoon signal and storm surge days, 2021 to now, from public records | The forecast's two missing columns (`ml/forecast/data/manila_signals.csv`). 23 signal days gathered so far from news; PAGASA's tropical cyclone reports and the news can fill the rest. Claude can do this; MDRRMD's situational reports (letter item G) would check it |
| A team-labelled set of incident descriptions | The plan's fallback for the classifier (plan 10.4): the team writes and labels a few hundred flood, fire, medical, and structural reports per type in English, Filipino, and Taglish, disclosed as such in the thesis. Claude retrains and loads it, so crowd reports get a type before MDRRMD's data arrives |
| The ping on the full screen map | You reported it does not ping there. The code is the same as the board's; closing that window and reopening it was the suggested fix, and you have not said whether it worked |
| A Storage bucket for final NDRRMC reports | The PDF is made in the browser and downloaded; the plan says "to Storage". Only if you or MDRRMD want the files kept on the server |
| Filipino for the dashboard and the web form | Not asked for; the mobile app has it |
| A supplies screen in the mobile app | Not built: you asked for web only |
| Widget gallery (a page showing every shared widget) | Plan item for the design review; low value now |

### 8b. Waits on MDRRMD (the letter)

| What | Letter item | Where it stands |
|---|---|---|
| **The 72-hour forecast on real data** (LSTM and KDE) | A, G | The page is empty. Gathered so far from public news: 131 fires, 17 flood days, 23 signal days, real weather from 2012. A first training on that was too weak to show (flood F1 0.24, fire 0.31, storm surge not trainable) |
| Forecast accuracy figures and a run selector on D8 | A | After the real model |
| The classifier on real descriptions | B | Until then crowd reports get no type; an SOS gets one from the resident's tap or the dispatcher |
| The dispatch-time baseline (before and after) | C | Our side is built (A4 Analytics measures our times); MDRRMD's current times are the "before" |
| Real call signs, unit types, and crew sizes | D | The ten units are real stations from OpenStreetMap; their call signs were assigned by us and their supply levels are made up for the demo |
| Final priority weights on the Triage Queue | E | The A3 weights are provisional until the SOP |
| NDRRMC report sections (A5, A6) | F | Six provisional sections; the real template replaces them. Also tuning Dijkstra's road speeds with their records |
| Posting on the real MDRRMD Facebook Page | H | Works on the test Page; the real Page needs written approval |
| Alert thresholds and texts, and the retention period | H | Provisional values in A3 (retention 12 months) |

### 8c. Waits on you (accounts, keys, hardware)

| What | What it waits for |
|---|---|
| Traffic in the routes (Google Maps, as the panel was told) | Not built. Your Google Cloud billing account and the key saved as `GOOGLE_MAPS_API_KEY`. Then Google says which stretches are jammed, and our Dijkstra goes around them. Known catches: a card is required, Google's terms may not allow its data with an OpenStreetMap map, and it works only online |
| Real resident sign-in, all outgoing SMS, SOS by SMS | The spare phone as the SMS gateway, with a SIM (part 7) |
| CI on GitHub (analyze, tests, key scan on every push) | **It has never run**: every run is refused before it starts because "your account is locked due to a billing issue" (all 22 recent runs, up to 2026-10-16). Fix it in GitHub's billing settings; the tests pass on this PC |
| Leaked-password protection, and the project under a team account on a paid plan | Supabase's Pro plan; before a pilot, not needed for the defense |
| Self-hosted Manila map tiles | Decided: public OpenStreetMap tiles for the defense; self-hosted before a pilot (needs a host) |
| Decisions: plan Q44 (which delivery window counts as a delivered SOS for Objective 3; A4 shows 1, 5, and 15 minutes) and Q21/Q22 (how the forecast becomes a risk level) | Your answer |

### 8d. The team (not code)

| What | Where it stands |
|---|---|
| UAT on 2026-11-23 to 27 (3 admins, 16 field personnel, 31 residents) and the ISO/IEC 25010 questionnaire validated by 2026-10-30 | Not started as far as this file knows |
| Hallway test, the Objective 3 trial (SOS delivery offline), the Objective 4 trial (report time), the Bluetooth relay with three phones, everything marked **[P]** | Not started; needs phones and people |
| Read the mobile app's Filipino text (privacy notice and consent first) | Not done |
| Thesis updates | Chapter 1 scope (unit supplies, other agencies' stations); Chapter 3 (river levels from PAGASA, Gemini, Cancel SOS, live location, Open-Meteo weather if the forecast uses it, safe places instead of the nearest evacuation center, incident posts on Facebook, incident history) |

## 9. Dropped (Joshua, 2026-10-11)

- ~~Nearest evacuation center on R7 (Q38)~~: back on 2026-10-19 as safe places
  (parts 1 and 4). The thesis keeps the line, reworded.
- A separate pin for a household member who lives elsewhere. Household members
  use the resident's home address.
- A responder declining an assignment: the dispatcher is only offered
  available units, and reassigns if a unit cannot go.

## 10. Never tested on a real phone

Everything marked **[P]** above, plus: the Bluetooth relay between three phones,
the SMS fallback end to end, and the Objective 3 trial. Seen on your phone on
2026-10-12: sign-in with the test number, an SOS reaching the Command Board, a
rescue from assignment to resolved, and the unit's position on the map.
