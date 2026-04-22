# MotoPulse — Project Summary
**Current version:** v1.4.1+7  
**Stack:** Flutter / Dart · Android (targetSdk 36) · Firebase · Google Maps SDK  
**Repo:** https://github.com/seeseal/motopulse

---

## What MotoPulse Is

A rider-safety companion app for Android. The core idea: when you're on a motorcycle the phone sits in your pocket or on a mount, and MotoPulse silently watches out for you. It tracks your ride on a live map, detects if you crash, alerts your emergency contacts, and lets your crew ride together on a shared map.

### Feature set (shipped)

| Area | What it does |
|---|---|
| **Live ride tracking** | GPS foreground service keeps running when the screen is off. Red polyline drawn on a dark Google Maps canvas. Bike icon rotates to match heading. Navigation (heading-up, 45° tilt) and north-up modes. |
| **Crash detection** | 3-signal state machine: impact ≥ 3.5 g AND pre-event speed > 25 km/h AND 15 s of post-impact immobility. If all three fire, a full-screen countdown overlay gives the rider 30 s to cancel before SOS triggers. |
| **SOS screen** | One-tap emergency call + SMS to saved contacts with last-known GPS coordinates. |
| **Route planner** | Multi-waypoint planner (up to 6 stops). Google Places Autocomplete search — live suggestions as you type. Directions API calculates route, draws it as a dashed blue polyline. Shows distance, ETA, per-segment breakdown, and destination weather. Save/load favourite routes. |
| **Group ride** | Firebase Realtime presence — create a session, share a QR code, crew joins and everyone sees each other on the same map in real time. |
| **Stats** | Past rides list with distance, duration, top speed. All data stored locally via SharedPreferences. |
| **Dashboard** | Today's weather, speed limit reminder, fuel range estimate based on profile settings. |
| **Profile** | Rider name, emergency contacts, bike details (tank size, fuel efficiency), speed limit. Photo picker. |
| **Road snapping** | Live GPS trace snapped to actual roads every 3 s via OSRM `/match` endpoint. |

---

## Session History — What Was Done

### Build & infrastructure
- Diagnosed and fixed a **truncated `pubspec.yaml`** (was cut off at `flutter_lints`) — completed the file.
- Diagnosed and fixed a **truncated `ride_service.dart`** (was cut off mid-expression in `formattedTime`) — completed the getter.
- Fixed **AndroidManifest merger conflict** caused by `flutter_background_service` re-declaring `android:exported` — added `xmlns:tools` and `tools:replace="android:exported"` to the service element.
- Fixed **GitHub push protection blocking the PAT token** that was hardcoded in `release_v140.ps1` — replaced with `$env:GITHUB_TOKEN`, deleted the old tag, amended, re-tagged, force-pushed.
- Cleaned up **clutter files** from the git repo (build scripts, temp logs, test files) and updated `.gitignore`.
- Wrote a **detailed README.md** covering all features, the crash-detection state machine, tech stack, and full changelog.

### Android 14 foreground-service crash (v1.4.0 → v1.4.1)
- **Symptom:** App crashed the instant "Start Ride" was tapped on Android 14 / targetSdk 36.
- **Root cause:** `flutter_background_service` calls `startForeground()` before the notification channel `motopulse_ride_channel` existed, throwing `CannotPostForegroundServiceNotificationException`.
- **Fix:** Created `MainActivity.kt` that natively registers the channel in `onCreate()` — this guarantees the channel exists before any Dart code runs.
- **Result:** Start Ride works cleanly. Version bumped to **v1.4.1+7**.

### Route planner search (v1.4.1, current session)
- **Symptom:** Searching "Mumbai" (or most city names) returned "No results".
- **Root cause:** `searchPlace()` was using the **Google Geocoding API** which requires very precise address input and returns nothing for bare city names.
- **Fix:** Replaced with **Google Places Autocomplete API** + **Place Details API**:
  - `searchPlace()` → `/maps/api/place/autocomplete/json` — returns instant predictions for any query ≥ 2 chars.
  - `getPlaceDetails()` → `/maps/api/place/details/json` — resolves `place_id` to lat/lng.
  - UI updated: live suggestions panel appears below the text fields as you type (400 ms debounce), spinner in the field while fetching, green ✓ when a waypoint is confirmed.
- **Result:** Build succeeded (43.3 MB APK), committed and pushed to `main`.

---

## How to Build the APK

Every build follows these steps. You run them from a `cmd` window in `C:\Users\cecil\motopulse`.

### Step 1 — Build
```cmd
cd /d C:\Users\cecil\motopulse
C:\flutter\bin\flutter.bat build apk --release > build_log.txt 2>&1
```
The APK lands at:
```
build\app\outputs\flutter-apk\app-release.apk
```
Build takes ~3 minutes the first time after a change; ~90 s for incremental.

### Step 2 — Copy APK with version name
```cmd
copy build\app\outputs\flutter-apk\app-release.apk motopulse-v1.4.1.apk
```

### Step 3 — Git commit & tag
```cmd
echo Your commit message > commitmsg.txt
git add -A
git commit -F commitmsg.txt
git tag v1.4.1
git push origin main --tags
```
> **Important:** Always write the commit message to a `.txt` file and use `git commit -F commitmsg.txt`. If you put the message directly in `-m "..."` on Windows cmd, the shell breaks on spaces and special characters.

### Step 4 — GitHub Release (manual or scripted)
Use `release_v141.ps1` (or create one per version):
```powershell
# Set your token in the environment first — NEVER hardcode it
$env:GITHUB_TOKEN = "ghp_yourtoken"

$headers = @{ Authorization = "token $env:GITHUB_TOKEN"; "Content-Type" = "application/json" }
$body = @{ tag_name="v1.4.1"; name="MotoPulse v1.4.1"; body="Release notes here"; draft=$false; prerelease=$false } | ConvertTo-Json
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/seeseal/motopulse/releases" -Method Post -Headers $headers -Body $body

# Upload APK
$apkPath = "C:\Users\cecil\motopulse\motopulse-v1.4.1.apk"
$uploadUrl = $release.upload_url -replace '\{.*\}', ''
$uploadHeaders = @{ Authorization = "token $env:GITHUB_TOKEN"; "Content-Type" = "application/vnd.android.package-archive" }
Invoke-RestMethod -Uri "${uploadUrl}?name=motopulse-v1.4.1.apk" -Method Post -Headers $uploadHeaders -InFile $apkPath
```

---

## About the GitHub Token

Your token is a **GitHub Personal Access Token (PAT)** — it authenticates pushes and API calls (creating releases, uploading APKs).

### Where to get / create one
1. Go to https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Name it something like `motopulse-releases`
4. Select scopes: `repo` (full) — that's all you need
5. Copy the token immediately — GitHub only shows it once

### How to use it safely
- **Never hardcode it in a file** — GitHub's push protection scanner will detect and block the push.
- Set it as an environment variable each session:
  ```powershell
  $env:GITHUB_TOKEN = "ghp_yourtoken"
  ```
- Or store it in Windows Credential Manager and read it from there.
- Reference it in scripts as `$env:GITHUB_TOKEN`.

### If a token gets exposed
1. Go to https://github.com/settings/tokens and **Revoke** the exposed token immediately.
2. Generate a new one.
3. If it was committed to the repo, you must rewrite history (`git filter-repo` or amend + force push) — GitHub will keep blocking pushes until the token is gone from all commits.

---

## What's Next (Planned / Ideas)

### High priority
- **Signed APK for Play Store** — currently building a debug-signed APK. Need to create a keystore (`keytool`), configure `key.properties` in `android/`, and pass `--release` with the signing config. Required before any public distribution.
- **Places API billing check** — the switch to Places Autocomplete uses a different billing SKU than Geocoding. Verify the Google Cloud project has billing enabled and the Places API is enabled in the API console.

### Feature ideas
- **Turn-by-turn navigation** — the route is drawn but there's no step-by-step guidance. The Directions API already returns `steps[]` with maneuver instructions; just need to surface the next step in the HUD.
- **Ride history export** — export past rides as GPX files for import into Strava, Komoot, etc.
- **Speed camera alerts** — overlay known speed camera locations on the map (public datasets available for most countries).
- **iOS build** — the Dart code is platform-agnostic; the main work would be the background location service (`flutter_background_service` has iOS support) and provisioning profiles.
- **Push notifications for group ride** — currently riders have to be in-app to see each other; a Firebase Cloud Messaging integration could ping crew members when a ride starts.
- **OBD-II / Bluetooth integration** — pair with the bike's ECU via ELM327 adapter to get real RPM, throttle position, and coolant temp on the dashboard.

---

## Key Files Reference

```
motopulse/
├── lib/
│   ├── main.dart                        Entry point, background service init
│   ├── screens/
│   │   ├── home_screen.dart             Glass nav bar, tab switching
│   │   ├── ride_tracking_screen.dart    Map, live HUD, route planner sheet
│   │   ├── dashboard_screen.dart        Weather, quick stats, start-ride shortcut
│   │   ├── sos_screen.dart              Emergency call + SMS
│   │   ├── stats_screen.dart            Past rides list
│   │   ├── profile_screen.dart          Rider profile, bike settings
│   │   └── group_ride_screen.dart       Firebase group ride
│   ├── services/
│   │   ├── ride_service.dart            GPS polling, distance, speed, recording
│   │   ├── background_service.dart      flutter_background_service wrapper
│   │   ├── crash_detector.dart          3-signal impact state machine
│   │   ├── route_service.dart           Places Autocomplete, Directions, OSRM snap
│   │   ├── weather_service.dart         Open-Meteo weather fetch
│   │   └── profile_service.dart         SharedPreferences profile persistence
│   ├── models/
│   │   └── ride_model.dart              Ride data structure
│   └── widgets/
│       ├── glass_card.dart              Frosted-glass card widget
│       └── crash_alert_overlay.dart     Full-screen crash countdown
├── android/
│   ├── app/src/main/
│   │   ├── kotlin/com/example/motopulse/MainActivity.kt   Native channel creation
│   │   └── AndroidManifest.xml          Permissions, foreground service declaration
│   └── app/build.gradle                 targetSdk 36, signing config
└── pubspec.yaml                         v1.4.1+7
```

---

*Last updated: v1.4.1+7 — Places Autocomplete search, Android 14 foreground-service fix.*
