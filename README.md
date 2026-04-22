# MotoPulse

A dark, full-featured riding companion app for motorcyclists. Built with Flutter — tracks rides with navigation-grade accuracy, connects groups in real time via Firebase, detects crashes using a multi-signal state machine, stores your documents, and handles emergencies.

## Download

**[MotoPulse-v1.4.0.apk](https://github.com/seeseal/motopulse/releases/download/v1.4.0/MotoPulse-v1.4.0.apk)** — sideload directly on any Android device (arm64).

---

## Features

### Dashboard

The home screen gives you everything at a glance before you ride.

- **Live weather strip** — current temperature, wind speed, and a riding condition advisory (e.g. "Good riding conditions" / "Wet roads — ride cautiously") pulled from Open-Meteo, no API key required
- **Quick stats** — total lifetime kilometres, distance this week, and total number of rides
- **ONGOING RIDE button** — the Start Ride button is reactive. When a ride is already active (even if you navigated away), it turns dark with a red glow and shows a live elapsed timer and current distance. Tap it to return to the tracking screen
- **Document expiry alert** — a tile appears if any stored document is expired or expiring within 30 days, with a count badge
- **Recent ride card** — shows the last completed ride with distance, duration, and date

---

### Ride Tracking

The core of the app. A full-screen Google Map with a live stats panel below.

**GPS & accuracy**
- GPS polled every 5 seconds using Android's fused location provider at `LocationAccuracy.high` with a 10 m distance filter — tuned for battery life without sacrificing accuracy
- GPS fixes with accuracy worse than 25 m are silently discarded, eliminating phantom jumps that make paths appear to cut through buildings
- Teleport filter rejects any single reading that moves more than 500 m from the last point, catching GPS glitches
- Background GPS runs via a persistent foreground service (`flutter_background_service`) that survives screen-off, app-switching, and Android battery optimisation — the ride never drops in the background

**Navigation-grade map behaviour**
- **Road snapping** — raw GPS coordinates are sent to the OSRM `/match` endpoint every 3 seconds and snapped to the nearest road. The displayed red polyline follows actual road geometry, not raw GPS scatter
- **Heading-up camera** — the map rotates to keep your current direction of travel pointing upward, like Google Maps navigation. Camera tilts to 45° for a perspective view of the road ahead
- **North-up toggle** — tap the compass button to switch between heading-up (navigation mode) and north-up (overview mode). Switching to north-up resets tilt to flat
- **Speed-adaptive zoom** — zoom adjusts automatically based on speed: zoomed in tight at walking pace (zoom 17.5), zooms out progressively up to zoom 15 at highway speeds so you always see enough road ahead
- **Smooth marker movement** — the bike icon interpolates toward the latest GPS fix at 20 fps using a lerp filter, so it glides smoothly instead of jumping between updates
- **Bike icon marker** — a red motorcycle icon replaces the plain pin while riding. It rotates to face your current direction of travel based on GPS heading. A separate red start pin marks where the ride began
- **Traffic layer toggle** — shows or hides live Google Maps traffic conditions. The button turns red when traffic is active
- **Re-centre button** — snaps the camera back to your current position instantly

**Stats panel**
- Large live speed readout in km/h
- Distance and duration tiles update every second
- Max speed for the current ride
- Estimated fuel range based on tank size and efficiency from your profile, with a colour-coded progress bar (green → yellow as fuel depletes)

**Speed alert**
- Configurable speed threshold set in your profile
- Flashes a red banner across the top of the screen with heavy haptic feedback when you exceed the limit
- Resets automatically when you drop back below the threshold

**Ride saving**
- Ride is saved automatically when you tap Stop. Rides under 5 seconds or 50 m are silently discarded as ghost rides
- Saved data: title (auto-generated from time of day), distance, duration, avg speed, max speed, start timestamp, and route polyline (downsampled to 200 points for storage efficiency)

---

### Crash Detection

A multi-signal state machine monitors for genuine crashes and filters out false positives from potholes, bumps, and phone drops.

**Detection logic — all three conditions must be met in sequence:**
1. **Pre-event speed check** — rider must be moving above 25 km/h when the impact occurs. Stationary drops and low-speed bumps are ignored entirely
2. **Impact threshold** — accelerometer detects a force greater than 3.5 g
3. **Post-impact immobility** — device must remain stationary for 15 seconds after the impact. A rider who gets up and walks around will not trigger SOS

**Response:**
- A full-screen audible alert overlay appears immediately after impact is confirmed
- A 15-second countdown gives you time to dismiss it if you're fine
- If not dismissed, SOS fires automatically — broadcasting your coordinates to your group and displaying the emergency QR code

This design eliminates false alarms from aggressive riding over rough roads while still catching a genuine crash within seconds.

---

### Ride History

Every completed ride is stored locally and accessible from the History tab.

- Full list of rides sorted by most recent, each showing title, date, distance, duration, avg speed, and max speed
- Tap any ride to see a dark Google Maps mini-map with the full route replayed as a red polyline
- Swipe left to delete individual rides
- Clear all button to wipe the entire history
- All data stored locally via SharedPreferences — no account required

---

### Route Planner

Plan a multi-stop route before you ride, or mid-ride to set a destination.

- Search any address using Google Geocoding API for fast, accurate results worldwide
- Multiple search results shown in a picker sheet when a query is ambiguous
- Add up to 6 waypoints — Start, up to 4 intermediate stops, and End
- Drag handles to reorder waypoints
- Route calculated via OSRM open-source routing — returns distance (km), estimated duration, and a turn-by-turn road polyline
- Per-segment breakdown showing distance and time between each stop
- Avoid tolls and avoid highways toggles
- Destination weather — fetches live weather for the end waypoint so you know what conditions to expect on arrival
- Save routes — give a route a name and save it for later. Swipe to delete saved routes
- Planned route shown as a dashed blue overlay on the ride tracking map

---

### Group Ride

Ride with your crew and see everyone on a shared live map.

- **Create or join** a session using a 6-character alphanumeric room code — share it with your group via any messaging app
- **Live map** — every rider's position updates in real time on a dark Google Map via Firebase Firestore. Each rider appears as a labelled marker with their name, emoji, and current speed
- **Quick alerts** — send a one-tap status broadcast to everyone in the session:
  - ⛽ Need fuel
  - 🐢 Slowing down
  - 🅿️ Pull over ahead
  - ✅ All good
  - ⚠️ Road hazard
  - 🚔 Police ahead
- **Alert feed** — a live scrolling log shows who sent what and when, so no one misses a heads-up
- **SOS integration** — if any rider triggers SOS, all group members see a full-screen red overlay with the rider's name, emoji, and GPS coordinates, plus a Go to Location button that opens navigation

---

### SOS

One-tap emergency system designed to work fast.

- Large pulsing red SOS button — hard to miss, impossible to accidentally trigger
- Instantly broadcasts your exact GPS coordinates to every rider in your active group session via Firestore
- Other riders receive a full-screen red alert overlay that locks their screen until dismissed, showing your name, location, and a direct navigation link
- **Emergency QR code** — generates a QR code containing your blood type, allergies, emergency contact name and phone number, and bike details. First responders can scan it if you're unconscious
- Works even if you're alone — the QR code is always available offline

---

### Document Vault

Store all your vehicle and personal documents in one place.

- **Document types** — Insurance, Registration Certificate (RC), Driving Licence, PUC (Pollution Certificate), Fitness Certificate, and a free-form Custom type
- **Photo capture** — take a photo in-app or import from your gallery for each document
- **Expiry tracking** — set an expiry date per document. Colour-coded badges show:
  - 🟢 Green — valid, more than 30 days remaining
  - 🟡 Amber — expiring within 30 days
  - 🔴 Red — expired
- **Dashboard alert** — when any document is amber or red, the dashboard shows a warning tile with a count
- **Filter** — tap a document type chip to filter the list
- Long-press to delete a document

---

### Maintenance Tracker

Keep a full service log for your bike.

- Log service entries by type: Oil Change, Tyre, Brakes, Chain, Air Filter, Spark Plug, Coolant, Battery, General Service, and Custom
- Record the odometer reading, date, cost, and free-text notes per entry
- Set an odometer-based reminder — the app alerts you when the next service is due based on current distance
- Full chronological service history per entry type
- Overdue count shown on the dashboard maintenance tile

---

### Profile

Your rider identity and bike configuration, used across the whole app.

- **Rider info** — name, avatar photo (camera or gallery), blood type, known allergies
- **Emergency contact** — name and phone number, dialled directly from the SOS QR card
- **Bike details** — bike name, fuel tank capacity (litres), fuel efficiency (km/L) — drives the live range estimator on the tracking screen
- **Speed alert threshold** — set the km/h value that triggers the ride tracking speed alert
- **Live QR preview** — the emergency QR card updates in real time as you fill in your details

---

### Stats & Achievements

A lifetime summary of your riding.

- **Totals** — total distance ridden, total ride time, all-time top speed
- **Weekly chart** — bar chart of distance per day for the current week
- **Achievements** — unlocked automatically based on riding milestones:
  - First Ride — complete your first ride
  - Road Warrior — ride more than 100 km total
  - Speed Demon — hit a top speed above a threshold

---

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart) |
| Maps | Google Maps SDK for Android (`google_maps_flutter`) |
| Routing & road snapping | OSRM (open source, `/route` + `/match` endpoints) |
| Geocoding | Google Geocoding API |
| Weather | Open-Meteo (no API key required) |
| Real-time backend | Firebase Firestore |
| Auth | Firebase Anonymous Auth |
| Local storage | SharedPreferences |
| Background GPS | `flutter_background_service` (persistent foreground service) |
| Crash detection | `sensors_plus` (accelerometer — multi-signal state machine) |
| QR generation | `qr_flutter` |
| QR scanning | `mobile_scanner` |
| Image handling | `image_picker` |

---

## Build from Source

### Prerequisites

- Flutter SDK 3.x
- Android Studio or VS Code with Flutter plugin
- A Firebase project (free Spark plan works)
- A Google Maps API key with **Maps SDK for Android** and **Geocoding API** enabled in Google Cloud Console

### Steps

```bash
git clone https://github.com/seeseal/motopulse.git
cd motopulse
flutter pub get
```

**Firebase** — place your `google-services.json` in `android/app/` and update `lib/firebase_options.dart` with your project values. Enable Firestore and Anonymous Authentication in the Firebase console.

**Google Maps & Geocoding** — add your API key to `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE"/>
```

Ensure both **Maps SDK for Android** and **Geocoding API** are enabled for the key in Google Cloud Console. The Firebase-auto-created Android key does not include them by default.

```bash
flutter build apk --release --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Firestore Structure

```
group_rides/
  {roomCode}/
    riders/   → name, emoji, lat, lng, speed, updatedAt
    sos/      → name, emoji, lat, lng, active, triggeredAt
    alerts/   → name, emoji, alertEmoji, message, sentAt
```

---

## Changelog

### v1.4.0 — Crash Detection & Background GPS
- **Crash detection rewritten** as a multi-signal state machine: requires impact > 3.5 g + pre-event speed > 25 km/h + 15 seconds of post-impact immobility before triggering — eliminates false positives from potholes and rough roads
- **Emergency countdown reduced** from 30 seconds to 15 seconds
- **Background GPS rewritten** using `flutter_background_service` replacing `flutter_foreground_task` — more reliable on modern Android, survives aggressive battery management
- **GPS settings tuned** — `LocationAccuracy.high`, 5-second interval, 10 m distance filter for improved battery life
- **Google Geocoding API** replaces Nominatim in the route planner for faster, more accurate place search globally

### v1.3.0 — Navigation Mode
- **OSRM road snapping** — GPS trace corrected to actual roads every 3 seconds via `/match` endpoint, eliminating path drift through fields and buildings
- **Bearing-based marker rotation** — bike icon rotates to face current direction of travel using GPS heading
- **Heading-up navigation camera** — map rotates to keep your direction forward with a 45° perspective tilt, like Google Maps navigation. Toggle button switches between heading-up and north-up flat view
- **Speed-adaptive zoom** — camera zoom adjusts from 17.5 at low speed down to 15 at highway speed automatically
- **Smooth marker interpolation** — bike icon glides between GPS updates at 20 fps using lerp instead of jumping

### v1.2.1 — Ride Tracking Improvements
- Traffic layer toggle button on the ride map
- Moving marker replaced with a bike icon; red start pin marks the ride origin
- GPS accuracy filter — fixes worse than 20 m discarded to prevent path hallucination
- Background GPS hardened with `AndroidSettings` and explicit 1-second interval
- Battery optimisation exemption requested automatically on ride start

### v1.2.0 — Cleanup & Ride Awareness
- Dashboard Start Ride button now shows live ONGOING RIDE state (timer + distance) when a ride is active
- Speedometer screen removed
- Cleaned up unused repository files

### v1.1.0 — Google Maps Edition
- Migrated all maps from flutter_map (OpenStreetMap) to Google Maps SDK
- Dark map style applied across ride tracking, route planner, group ride, and ride history
- Ride history cards show a Google Maps mini-map of the route
- ARM64-only release build

### v1.0.0 — Initial Release
- Full feature set: ride tracking, crash detection, group ride, SOS, document vault, maintenance tracker, profile, stats

---

## License

MIT
