# Fitness Command Web Demo

Independent Flutter Web demonstration of Fitness Command. The original Android
project was read only; only its Dart source, tests and dependency configuration
were reused. No Android or iOS project, SDK copy, personal database, GPS capture,
or original app configuration is included or modified.

The original package name `fitness_command` is retained for source/test imports.
This folder is a separate project with an isolated browser database.

## Included

- Original dark green/black screens and navigation.
- Six compact workouts: Tuesday A/B, Thursday A/B, Saturday A/B, with the
  original exercise definitions and relevant workout/logging logic.
- Exercise and target editing, actual set logging, workout completion,
  custom workouts, History, Progress and Personal Bests.
- Three fictional strength sessions with increasing sample loads, plus one
  fictional cycling session. Sample history is seeded once, atomically.
- Simulated cycling start/pause/resume/finish/save/discard and a synthetic GPS
  route on a grid, using the original map viewport and statistics screens.

All historical sample records are fictional. Template prescriptions are copied
from source definitions; they are not training advice. No private app data was
copied. The demo never asks for location permission or fetches map tiles.
Audio announcements and background GPS recording are not implemented in the demo;
cycling settings only demonstrate the original controls.

## Run locally

Use the existing Flutter SDK on PATH (development SDK: Flutter 3.47.7 / Dart
3.13.5). Commands must run in this folder, with normal SDK cache write access.

```powershell
flutter pub get
flutter run -d edge
# Alternatively:
flutter run -d chrome
```

The pinned sql.js 1.13.0 JavaScript runtime loads from jsDelivr. Initial loading
requires internet access to that CDN; no workout data is sent there. This small
demo deliberately uses Drift's legacy sql.js adapter so static hosting needs no
worker configuration or special cross-origin headers. Its dependency is pinned
by the lockfile; it is not a recommendation for the native application's storage.
Do not use this demo for real fitness data.

Edits and strength sessions persist in IndexedDB in this browser. Clear site
storage to restore the sample dataset. Browser private mode, storage restrictions
and eviction may prevent or remove persistence. Use one tab at a time. Simulated
ride capture lives in memory until mirrored into the demo database; reload ends
the active simulation. Saved rides remain in History. Timers can be throttled in
background tabs; this is an interactive simulation, not a real recorder.

## Checks and Pages build

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --base-href /fitness-command-demo/
```

Output is `build/web`. Hash routing is retained, so navigation and reloads work
on static GitHub Pages without a custom 404 router. For a local production preview:

```powershell
New-Item -ItemType Directory -Force build/preview/fitness-command-demo
Copy-Item build/web/* build/preview/fitness-command-demo -Recurse -Force
python -m http.server 8080 --directory build/preview
```

Visit `http://localhost:8080/fitness-command-demo/` in Edge and Chrome. For iPhone
Safari, serve the preview on your LAN and open the computer's LAN address on the
phone (or later use the HTTPS Pages URL). No location permissions are needed.
This is a JavaScript Flutter build, not a Wasm-only build, for browser compatibility.

## Manual acceptance checklist

Run in Edge, Chrome and iPhone Safari, including a narrow portrait viewport:

1. Confirm the demo notice, dark theme and all six workouts on Home/Workout.
2. Open a workout, edit a target, start it, edit an actual set, log a set,
   pause/resume, and finish. Confirm History and Progress update.
3. Edit an exercise in Exercises. Create a custom workout, add exercises, save,
   reopen and log it. Reload and confirm browser-local changes persist.
4. Inspect fictional History and Personal Bests; open session details.
5. Start Cycling, wait for route/stat updates, pause (route stops), resume,
   finish, save and inspect the saved ride. Also try discard.
6. Navigate back, reload a hash route, rotate the phone, and open an editor with
   the onscreen keyboard. Check scrolling, dialogs and navigation controls.
7. Clear this site's storage, reload and verify samples return once.

## Deployment preparation (nothing published yet)

`.github/workflows/pages.yml` validates and uploads a Pages artifact for pull
requests or manual runs. Publishing is disabled by default. After future approval,
create the `fitness-command-demo` repository, push this project, select GitHub
Actions as its Pages source, and manually run the workflow with `publish` checked.
The deployment job requires that explicit checkbox. Expected URL:
`https://<owner>.github.io/fitness-command-demo/`.

## Verification in the creation session

- Temporary file creation/read/removal succeeded in this folder.
- Direct installed-Dart analysis: passed with no issues. Formatting passed.
- Flutter analysis, test and release web build attempts all exited before running,
  blocked by the managed session denying
  writes to the existing SDK cache (`bin/cache/lockfile` and
  `bin/cache/libimobiledevice.stamp`). No SDK was copied or modified to work
  around this restriction. Run the commands above from a terminal with SDK cache
  write access, or reopen Codex with access to that existing SDK.
- Edge, Chrome and physical iPhone Safari acceptance remains to be performed
  after a successful web build. Compatibility is a target, not a claimed test pass.
