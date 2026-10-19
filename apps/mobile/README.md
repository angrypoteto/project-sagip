# sagip_mobile

S.A.G.I.P. Android app for Manila residents and MDRRMD field rescue personnel (Android 10 and up). How to run it is in `docs/PROGRESS.md` ("How to run").

## Releasing a new build

1. **Raise the build number** in two places, which a test keeps equal: the `+N` of `version` in `pubspec.yaml` (for example `0.3.4+7` to `0.3.5+8`) and `appBuild` in `lib/src/app_version.dart`.
2. **Build** (in `apps/mobile`, with `.env` filled in):

   ```bash
   flutter build apk --release --dart-define-from-file=.env
   ```

   The APK is `build/app/outputs/flutter-apk/app-release.apk`. Never commit it.
3. **Install on a phone over USB** (optional): `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
4. **Publish:** rebuild and deploy the resident site with the APK and `latest.json` beside it (`apps/dashboard/README.md`, "Hosting on Vercel"). Phones get it from `https://sagip.me/download/sagip.apk`.

## How phones learn about a new build

- **"A newer S.A.G.I.P. is out"** (build 7 and later): the app reads `https://sagip.me/download/latest.json` when it opens, when the internet comes back, and when it returns to the front. If that names a higher build, a banner on every tab offers Update (opens the download) and Later (hidden until the app is opened again). It is hidden while the resident's SOS is open or the responder's unit has a job.
- **Required update:** set A3 "Oldest app build allowed" (`app.min_build`) to the new build once the team has it. An older app then shows "Update S.A.G.I.P." and keeps only SOS and the hotline, again never during an open SOS or a job. Apps before build 2 cannot be asked (`supabase/README.md`).
- Builds 6 and older have no banner, so anyone still on them has to update by hand once, or be required to.
