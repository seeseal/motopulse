# MotoPulse

A dark, full-featured riding companion app for motorcyclists. Built with Flutter — tracks rides, connects groups in real time, detects crashes, stores documents, and handles emergencies.

## Download

**[MotoPulse-v1.1.0.apk](https://github.com/seeseal/motopulse/releases/download/v1.1.0/MotoPulse-v1.1.0.apk)** — sideload directly on any Android device (arm64).

---

## Features

### HUD Speedometer
- 3-panel automotive HUD layout — large analogue dial on the right, mini arc dial on the left, stats grid in the center
- Live LED bar (22 bars, green → amber → red) beside the main dial
- Speed limit badge that flashes red when exceeded
- Fuel range estimator with live progress bar
- Real-time weather strip and clock
- Works live during a ride or as a standalone speedometer

### Ride Tracking
- Real-time GPS with live speed, distance, and duration
- Ridden route drawn live on a dark Google Map
- Speed alert — configurable threshold, flashes red banner + haptic
- Ride saved automatically on stop with full stats (avg speed, max speed, distance, time)
- Anti-ghost filter — discards rides under 5 seconds or 50 m
- Background GPS tracking — ride continues with screen off or app minimised

### Crash Detection
- Accelerometer-based crash detection during active rides
- Auto-triggers SOS alert if a sudden impact is detected

### Ride History
- Every completed ride stored locally with full route replay on a dark Google Map mini-map
- Stats per ride: duration, avg speed, max speed, distance
- Swipe to delete individual rides or clear all

### Document Vault
- Store insurance, registration, license, PUC, fitness certificate, and custom docs
- Photo capture or gallery import per document
- Expiry tracking with colour-coded badges (green / amber / red)
- Dashboard alert badge when documents need attention
- Filter by document type, long-press to delete

### Route Planner
- Search any address and add multiple waypoints
- Route calculated and drawn on a dark Google Map
- Add / remove / reorder stops

### Group Ride
- Create or join a session with a 6-character room code
- See all riders' live positions on a dark Google Map in real time (Firebase Firestore)
- Quick alerts — ⛽ Need fuel, 🐢 Slowing down, 🅿️ Pull over ahead, ✅ All good, ⚠️ Hazard, 🚔 Police ahead
- Live alert feed shows who sent what and when

### SOS
- One-tap SOS with pulsing red animation
- Broadcasts exact GPS coordinates to every rider in the group instantly
- Other riders see a full-screen red overlay with your location and a Go to Location button
- Emergency QR code — blood type, allergies, emergency contact, bike details — for first responders

### Maintenance Tracker
- Log service entries (oil change, tyre, brakes, chain, etc.)
- Odometer-based reminders
- Full service history per bike

### Profile
- Rider name, avatar, blood type, allergies
- Emergency contact name and phone
- Bike name, fuel tank size, efficiency (km/L)
- Speed alert threshold
- Live QR emergency card preview

### Stats & Achievements
- Total distance, ride time, top speed across all rides
- Weekly distance bar chart
- Achievements — First Ride, Road Warrior, Speed Demon, and more

### Dashboard
- Live weather (temperature, wind, riding advice) via Open-Meteo
- Quick stats — total km, this week, total rides
- Document expiry alert tile
- Recent ride summary

---

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart) |
| Maps | Google Maps SDK for Android (`google_maps_flutter`) |
| Routing | OSRM (open source) |
| Geocoding | Nominatim (OpenStreetMap) |
| Weather | Open-Meteo (no API key required) |
| Backend | Firebase Firestore |
| Auth | Firebase Anonymous Auth |
| Local storage | SharedPreferences |
| Background GPS | flutter_foreground_task |
| Crash detection | sensors_plus |
| QR | qr_flutter |

---

## Build from Source

### Prerequisites
- Flutter SDK 3.x
- Android Studio or VS Code with Flutter plugin
- A Firebase project (free Spark plan works)
- A Google Maps API key with **Maps SDK for Android** enabled

### Setup

```bash
git clone https://github.com/seeseal/motopulse.git
cd motopulse
flutter pub get
```

**Firebase** — place your `google-services.json` in `android/app/` and update `lib/firebase_options.dart` with your project values (Firestore + Anonymous Auth enabled).

**Google Maps** — add your API key to `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_API_KEY_HERE"/>
```

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

### v1.1.0 — Google Maps Edition
- Migrated all maps from flutter_map (OpenStreetMap) to Google Maps SDK
- Dark map style applied across ride tracking, route planner, group ride, and ride history mini-maps
- Ride history cards now show a live Google Maps mini-map of each route
- ARM64-only release build (smaller APK, no x86_64 bloat)

### v1.0.0 — Initial Release
- Full feature set: HUD speedometer, ride tracking, crash detection, group ride, SOS, document vault, maintenance tracker

---

## License

MIT
