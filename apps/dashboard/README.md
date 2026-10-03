# sagip_dashboard

The S.A.G.I.P. web dashboard for MDRRMD dispatchers and administrators (`lib/main.dart`), and the resident hazard-report web form (`lib/main_webform.dart`). How to run them is in `docs/PROGRESS.md` ("How to run").

## Hosting on Vercel

Both are static Flutter web builds, so any static host works; Vercel's free plan is enough for the capstone. Each one is its own Vercel project with its own address (for example `sagip-dashboard.vercel.app` and `sagip-report.vercel.app`).

The build runs on your computer, not on Vercel (Vercel's build machines have no Flutter). `web/vercel.json` is copied into each build: it stops other sites from framing the pages, and makes browsers check for a new version on every visit.

1. **Build** (in `apps/dashboard`, with `.env` filled in):

   ```bash
   flutter build web --release --dart-define-from-file=.env -o "$PWD/build/web-dashboard"
   flutter build web --release --dart-define-from-file=.env -t lib/main_webform.dart -o "$PWD/build/web-form"
   ```

   Each takes about two minutes. The builds hold the Supabase URL and the **publishable** key, which are meant to be public (Row Level Security protects the data). Never put the service-role key in `.env`.

2. **Deploy** (Vercel CLI, `npm i -g vercel`, then `vercel login` once):

   ```bash
   vercel deploy build/web-dashboard --prod
   vercel deploy build/web-form --prod
   ```

   The first run of each asks which Vercel account to use and what to call the project (for example `sagip-dashboard` and `sagip-report`); it remembers the answer in a `.vercel` folder inside the build folder, which is git-ignored with the rest of `build/`. Later runs update the same address; if it asks again after a rebuild, link it to the existing project.

3. **Supabase:** Authentication > URL Configuration: add the two addresses to the Redirect URLs. Sign-in works without it (it uses passwords and codes, not links), but password-reset and email links would point at localhost.

4. **After a change:** build again and deploy again. Nothing else changes.

The map tiles still come from OpenStreetMap's public server, which allows light use only. Before the pilot, self-hosted Manila tiles go behind `MAP_TILE_URL` (see `docs/PROGRESS.md`); they can also be put on Vercel or any static host as a folder of `z/x/y.png` files.
