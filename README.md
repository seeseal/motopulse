# MotoPulse

A dark, minimal riding companion app for motorcyclists. Built with Flutter and Firebase — tracks rides, connects groups in real time, and handles emergencies.

---

## Features

### Dashboard
- Live weather conditions via Open-Meteo (temperature, wind, riding advice)
- Quick stats — total km, this week, total rides
- Recent ride history with "View all" history screen
- One-tap START RIDE button

### Ride Tracking
- Real-time GPS tracking with live speed, distance, and duration
- Ridden route drawn on a dark map (no Google Maps — no API key required)
- Speed alert — configurable threshold, flashes a red banner + haptic when exceeded
- Fuel range estimator — live progress bar based on tank size and efficiency you set
- Route planner — search any address, add multiple stops, calculate and display route on map
- Ride saved automatically on stop with full stats

### Group Ride
- Create or join a session with a 6-character room code
- See all riders' live positions on the map in real time (Firebase Firestore)
- Group persists when switching tabs — only ends when you tap Leave
- Quick alerts — one tap to broadcast ⛽ Need fuel, 🐢 Slowing down, 🅿️ Pull over ahead, ✅ All good, ⚠️ Hazard, 🚔 Police ahead
- Live alert feed shows who sent what

### SOS
- One-tap SOS button with pulsing animation
- If in a group ride, broadcasts your exact GPS to every rider instantly
- Other riders see a full-screen red overlay with your location and a Go to Location button
- Emergency QR code — contains your blood type, allergies, emergency contact, bike — for first responders to scan

### Profile
- Rider name, avatar, blood type, allergies
- Emergency contact name and phone
- Bike name
- Fuel tank size and efficiency (km/L) — feeds the ride tracker
- Speed alert threshold — feeds the tracking screen
- Live QR code preview updates as you type

### Stats
- Total distance, ride time, top speed
- Weekly distance bar chart
- Achievements (First Ride, Road Warrior, Speed Demon, etc.)

---

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Flutter (Dart) | Cross-platform, single codebase |
| Maps | flutter_map + CartoDB dark tiles | No API key, no billing |
| Routing | OSRM (router.project-osrm.org) | Free, open source |
| Geocoding | Nominatim (OpenStreetMap) | Free, no key required |
| Weather | Open-Meteo | Free, no key required |
| Backend | Firebase Firestore | Real-time group ride sync |
| Auth | Firebase Anonymous Auth | No sign-up friction |
| Local storage | SharedPreferences | Profile, ride history |
| QR | qr_flutter | Helmet emergency card |

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Android Studio or VS Code with Flutter plugin
- A Firebase project (free Spark plan works)

### Setup

1. Clone the repo
   ```bash
   git clone https://github.com/seeseal/motopulse.git
   cd motopulse
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Firebase — the project uses `lib/firebase_options.dart` for config. To connect your own Firebase project:
   - Create a project at console.firebase.google.com
   - Enable Firestore and Anonymous Authentication
   - Download `google-services.json` and place it in `android/app/`
   - Update `lib/firebase_options.dart` with your project values

4. Run
   ```bash
   flutter run
   ```

### Build APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Firestore Structure

```
group_rides/
  {roomCode}/
    riders/
      {riderId} → name, emoji, lat, lng, speed, updatedAt
    sos/
      {riderId} → name, emoji, lat, lng, active, triggeredAt
    alerts/
      {alertId} → name, emoji, alertEmoji, message, sentAt
```

---

## Roadmap

- [ ] SMS/call emergency contacts on SOS trigger
- [ ] Offline map tile caching
- [ ] Ride route replay on history screen
- [ ] Push notifications for group alerts
- [ ] iOS build and testing
- [ ] Play Store release

---

## License

MIT
