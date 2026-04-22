# MotoPulse — Implementation Plan (v2)
**Target:** Reliable, real-time group ride coordination + safety system  
**Constraints:** Existing Flutter stack · Firebase (current usage only) · No paid APIs · No new backend  
**Version:** v1.4.1+7 → next  
**Last updated:** 2026-04-22

---

## Guiding Principle

> Move from "works in testing" to "works reliably on real devices, real roads, real conditions."

Every change below is zero-budget and implementable with the current stack. The scope is deliberately narrow: tracking reliability, group awareness, SOS. Do not expand into navigation, analytics, or UI polish until these are solid.

---

## New Dependencies (free, open-source only)

| Package | Version | Why |
|---|---|---|
| `permission_handler` | `^11.0.0` | Battery optimisation check + request |
| `connectivity_plus` | `^5.0.0` | Offline SOS fallback detection |
| `device_info_plus` | `^9.0.0` | OEM detection for battery guidance |

Add to `pubspec.yaml`. Everything else uses existing plugins.

---

## Priority 1 — Must Ship Before Anything Else

### P1-A · Battery Optimisation Enforcement *(blocking gate)*

**Problem:** On MIUI, OneUI, Realme UI and others, Android will kill a foreground service regardless of the notification. Battery optimisation is the single biggest cause of tracking silently dropping in real-world use.

**Behaviour:** Battery optimisation check is a hard gate — ride start is blocked until it passes. This is not a dismissible warning.

**File: `lib/services/battery_guard.dart`** *(new)*

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class BatteryGuard {
  /// Returns true if the app is already exempted from battery optimisation.
  static Future<bool> isExempted() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  /// Opens the system dialog asking the user to grant exemption.
  static Future<bool> requestExemption() async {
    final result = await Permission.ignoreBatteryOptimizations.request();
    return result.isGranted;
  }

  /// Returns a human-readable OEM-specific instruction string.
  static Future<String> oemGuidance() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final brand = info.manufacturer.toLowerCase();
    if (['xiaomi', 'redmi', 'poco'].any(brand.contains)) {
      return 'On MIUI: Settings → Battery & performance → Power saver → Choose app → No restriction';
    } else if (brand == 'samsung') {
      return 'On Samsung: Settings → Battery → Background usage limits → Never sleeping apps → add MotoPulse';
    } else if (['realme', 'oppo'].any(brand.contains)) {
      return 'On Realme/Oppo: Settings → Battery → Power Saving → Custom → MotoPulse → No restriction';
    }
    return 'Settings → Battery → Battery Optimisation → All apps → MotoPulse → Don\'t optimise';
  }
}
```

**File: `lib/screens/battery_gate_screen.dart`** *(new)*

Full-screen blocking prompt shown when `BatteryGuard.isExempted()` returns false:
- Title: "Live tracking requires a system permission"
- Body: OEM-specific instruction text from `BatteryGuard.oemGuidance()`
- Primary button: "Open Settings" → calls `BatteryGuard.requestExemption()` → if granted, pops screen
- No secondary dismiss button — this cannot be skipped

**File: `lib/screens/session/session_start_screen.dart`** (or wherever "Start Ride" / "Start Session" lives)

```dart
Future<void> _onStartRideTapped() async {
  final exempted = await BatteryGuard.isExempted();
  if (!exempted) {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => BatteryGateScreen(),
    ));
    // Re-check after user returns from settings
    if (!await BatteryGuard.isExempted()) return; // still not granted, abort
  }
  // proceed with ride start
}
```

---

### P1-B · Separate GPS Frequency from Firebase Push Frequency

**Problem:** GPS must be sampled frequently for crash detection accuracy and smooth local map rendering. Firebase must NOT be written on every GPS fix — this drains battery and adds cost.

**Rule:** GPS runs at its own cadence (1–5 s depending on speed, per Phase 1 adaptive logic). Firebase is written only when a meaningful change has occurred.

**File: `lib/services/group_ride_service.dart`** — add a write gate inside `updatePosition()`:

```dart
// State held per-session:
LatLng? _lastPushedPosition;
DateTime? _lastPushTime;

static const _minDistanceMetres = 12.0;
static const _maxSilenceSeconds = 3;

Future<void> updatePosition(String code, double lat, double lng, double speedKmh) async {
  final now = DateTime.now();
  final newPos = LatLng(lat, lng);

  final distanceMoved = _lastPushedPosition == null
      ? double.infinity
      : Geolocator.distanceBetween(
          _lastPushedPosition!.latitude, _lastPushedPosition!.longitude,
          lat, lng);

  final elapsed = _lastPushTime == null
      ? double.infinity
      : now.difference(_lastPushTime!).inSeconds.toDouble();

  // Only push if moved enough OR enough time passed
  if (distanceMoved < _minDistanceMetres && elapsed < _maxSilenceSeconds) return;

  _lastPushedPosition = newPos;
  _lastPushTime = now;

  await _db.doc('group_rides/$code/riders/$_riderId').set({
    'lat': lat, 'lng': lng, 'speed': speedKmh,
    'state': _computeRiderState(speedKmh).name,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
```

Reset `_lastPushedPosition` and `_lastPushTime` to null when leaving a session, so the first fix after rejoining always pushes immediately.

---

### P1-C · Offline SOS Fallback *(critical safety fix)*

**Problem:** Crashes often happen in tunnels, rural roads, or dead zones. The current SOS silently fails if Firebase is unreachable — the group never gets alerted and the contacts never get messaged.

**File: `lib/services/sos_service.dart`** — check connectivity before deciding the alert path:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

Future<void> _dispatchAlerts(double lat, double lng) async {
  final connectivity = await Connectivity().checkConnectivity();
  final hasNetwork = connectivity != ConnectivityResult.none;

  if (hasNetwork) {
    // Normal path: group first, then SMS after countdown
    await GroupRideService.triggerSOS(lat, lng);
    // SMS/call dispatched after escalation delay (see P3 flow)
  } else {
    // Offline path: skip Firebase entirely, go direct to contacts NOW
    await _sendSMSToContacts(lat, lng);
    await _attemptEmergencyCall();
    // Persist locally for later sync
    await _saveSOSLocally(lat, lng);
  }
}

Future<void> _saveSOSLocally(double lat, double lng) async {
  final prefs = await SharedPreferences.getInstance();
  final pending = prefs.getStringList('pending_sos') ?? [];
  pending.add(jsonEncode({
    'lat': lat, 'lng': lng,
    'ts': DateTime.now().toIso8601String(),
  }));
  await prefs.setStringList('pending_sos', pending);
}
```

**On reconnection**, flush pending SOS records to Firebase. Add a connectivity listener in `GroupRideService.init()`:

```dart
Connectivity().onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) _flushPendingSOSAlerts();
});
```

---

## Priority 2 — Core Reliability

### P2-A · Session Recovery After App Restart

**Problem:** If Android kills the app mid-ride (OEM battery management, low RAM), the rider silently drops out of the group. They have to manually find the session code and rejoin — which they won't remember under pressure.

**File: `lib/services/group_ride_service.dart`** — persist active session on join/create, clear on leave:

```dart
// On createGroupRide() or joinGroupRide():
final prefs = await SharedPreferences.getInstance();
await prefs.setString('active_session_code', code);
await prefs.setString('active_session_joined_at', DateTime.now().toIso8601String());

// On leaveGroupRide():
await prefs.remove('active_session_code');
await prefs.remove('active_session_joined_at');
```

**File: `lib/main.dart`** — after app init, check for a stale session:

```dart
Future<void> _checkSessionRecovery() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString('active_session_code');
  if (code == null) return;

  // Only recover if session was active within the last 4 hours
  final joinedAt = prefs.getString('active_session_joined_at');
  if (joinedAt != null) {
    final age = DateTime.now().difference(DateTime.parse(joinedAt));
    if (age.inHours > 4) {
      await prefs.remove('active_session_code');
      return;
    }
  }

  // Verify session still exists in Firebase before rejoining
  final exists = await GroupRideService.sessionExists(code);
  if (exists) {
    await GroupRideService.joinGroupRide(code);
    // Navigate to group ride screen with the recovered session
    _navigateToGroupRide(code);
  } else {
    await prefs.remove('active_session_code');
  }
}
```

Add `sessionExists(code)` to `GroupRideService` — a single Firestore `get()` on `group_rides/{code}`, returns `false` if missing or `active == false`.

Also save the last known GPS position on every Firebase push so the rider appears at their last position immediately on rejoin, before the next GPS fix arrives:

```dart
// In updatePosition(), after successful Firebase write:
await prefs.setDouble('last_lat', lat);
await prefs.setDouble('last_lng', lng);
```

---

### P2-B · Rider State — Add Time Buffers

**Problem:** State transitions like "separated" and "stopped" fire immediately when the condition is first met. This causes false alerts during normal riding (traffic lights, brief GPS drift, overtaking gaps).

**File: `lib/services/group_ride_service.dart`** — debounce state transitions with per-rider timers:

```dart
// Per-rider debounce state:
final Map<String, DateTime> _stateEnteredAt = {};
final Map<String, RiderState> _pendingState = {};

RiderState _computeRiderState(String riderId, double speedKmh, double distanceFromNearestM) {
  RiderState candidate;

  if (speedKmh < 5) {
    candidate = RiderState.stopped;
  } else if (distanceFromNearestM > 500) {
    candidate = RiderState.separated;
  } else {
    candidate = RiderState.moving;
  }

  final now = DateTime.now();

  if (_pendingState[riderId] != candidate) {
    // State changed — start the debounce clock
    _pendingState[riderId] = candidate;
    _stateEnteredAt[riderId] = now;
    // Return the PREVIOUS confirmed state while waiting
    return _confirmedState[riderId] ?? RiderState.moving;
  }

  // State has been consistent — check if held long enough
  final heldFor = now.difference(_stateEnteredAt[riderId]!);
  final required = _debounceFor(candidate);

  if (heldFor >= required) {
    _confirmedState[riderId] = candidate;
    return candidate;
  }

  return _confirmedState[riderId] ?? RiderState.moving;
}

Duration _debounceFor(RiderState state) {
  switch (state) {
    case RiderState.separated: return const Duration(seconds: 20);
    case RiderState.stopped:   return const Duration(seconds: 10);
    case RiderState.disconnected: return const Duration(seconds: 45);
    default: return Duration.zero;
  }
}
```

---

## Priority 3 — Group SOS System

*(Full escalation flow — unchanged from v1 plan, reproduced here for completeness with offline path added above in P1-C)*

### P3-A · SOS Escalation State Machine

**New file: `lib/services/sos_service.dart`**

States: `idle → detecting → countdown → groupAlert → escalating → active → resolved`

```
1. DETECTING   — triggered by CrashDetector OR manual tap
   └─ 15 s countdown overlay
   └─ rider can cancel → idle

2. GROUP_ALERT  — countdown expires (network path)
   └─ GroupRideService.triggerSOS(lat, lng)
   └─ Highlight nearest 2 riders on their maps

   OR (offline path — from P1-C):
   └─ sendSMS() + attemptCall() immediately

3. ESCALATING  — 10 s after group alert
   └─ SMS to emergency contacts
   └─ Call attempt to primary contact
   └─ Retry once after 30 s if call fails

4. ACTIVE
   └─ Push location to Firebase every 2 s (bump GPS write frequency just for SOS)
   └─ Alert persists until resolved

5. RESOLVED
   └─ Rider taps "I'm OK" OR group member taps "Rider reached"
   └─ GroupRideService.cancelSOS()
   └─ Location push returns to normal cadence
```

### P3-B · Countdown Overlay

**File: `lib/widgets/crash_alert_overlay.dart`**

- Countdown: 30 s → **15 s**
- Show "Nearest rider: [Name] — X km away" from group snapshot
- Show network status: "📡 Group will be alerted" or "📵 Offline — SMS will be sent"
- Large CANCEL button (glove-friendly)

### P3-C · SOS Alert Persistence & Acknowledgement

**Firestore schema addition** (no new collections — extend existing `sos/` sub-document):

```
sos/{riderId}:
  + acknowledgedBy: [riderId, ...]
  + resolvedAt: Timestamp?
  + resolvedBy: String?
```

**File: `lib/screens/group_ride_screen.dart`** — SOS modal:
- "I'm on my way" → writes rider ID to `acknowledgedBy`
- Shows: "🏍️ Marco is on the way"
- Non-dismissible until `resolvedAt` is set

---

## Priority 4 — Crash Detection

### P4-A · Confidence-Score Model

**File: `lib/services/crash_detector.dart`** — replace boolean state machine with weighted signals:

```dart
// Signal weights
const _wImpact       = 0.35;
const _wSpeedDrop    = 0.25;
const _wOrientation  = 0.20;
const _wImmobility   = 0.15;
const _wDisplacement = 0.05;

// Trigger at:
const _triggerThreshold = 0.65;

double _confidenceScore = 0.0;

void _addSignal(SignalType type, double strength) {
  final weight = _weightFor(type);
  _confidenceScore = (_confidenceScore + weight * strength).clamp(0.0, 1.0);
  if (_confidenceScore >= _triggerThreshold) _onCrashConfident();
}

// Decay score over time
Timer.periodic(Duration(seconds: 1), (_) {
  _confidenceScore = (_confidenceScore - 0.05).clamp(0.0, 1.0);
});
```

### P4-B · Add Gyroscope Signal

`sensors_plus` (already in `pubspec.yaml`) includes gyroscope — no new dependency.

```dart
_gyroSub = gyroscopeEvents.listen((event) {
  final magnitude = sqrt(event.x*event.x + event.y*event.y + event.z*event.z);
  if (magnitude > 3.0) { // rad/s threshold
    _addSignal(SignalType.orientation, (magnitude / 6.0).clamp(0.0, 1.0));
  }
});
```

### P4-C · Low-Speed Crash Support

Remove the hard `> 25 km/h` gate. Scale speed contribution instead:

```dart
// Speed signal scales smoothly from 0 km/h to 60 km/h
final speedContribution = (preEventSpeedKmh / 60.0).clamp(0.0, 1.0);
_addSignal(SignalType.speedDrop, speedContribution);
```

A 15 km/h tip-over still triggers if impact + orientation + immobility are strong.

### P4-D · Noise Filtering

Require sustained impact (≥ 3 consecutive accelerometer samples ≥ threshold at ~100 Hz) before counting it as a real signal:

```dart
final List<double> _recentImpacts = [];
const _sustainedSamples = 3;

void _onAccel(AccelerometerEvent e) {
  final magnitude = sqrt(e.x*e.x + e.y*e.y + e.z*e.z) - 9.81;
  _recentImpacts.add(magnitude);
  if (_recentImpacts.length > 5) _recentImpacts.removeAt(0);

  if (_recentImpacts.length >= _sustainedSamples &&
      _recentImpacts.every((g) => g >= _impactThresholdMs2)) {
    _addSignal(SignalType.impact, 1.0);
    _recentImpacts.clear();
  }
}
```

### P4-E · Crash Event Logging *(local only, no backend)*

**File: `lib/services/crash_logger.dart`** *(new)*

Every time the confidence score reaches the trigger threshold (or manually via test mode), write a log entry to SharedPreferences:

```dart
class CrashLogger {
  static const _key = 'crash_log_v1';

  static Future<void> logEvent({
    required double impactScore,
    required double speedKmh,
    required double orientationScore,
    required double confidenceScore,
    required bool triggered,   // true = escalated to SOS, false = scored but did not trigger
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_key) ?? [];
    log.add(jsonEncode({
      'ts': DateTime.now().toIso8601String(),
      'impact': impactScore,
      'speed': speedKmh,
      'orientation': orientationScore,
      'confidence': confidenceScore,
      'triggered': triggered,
    }));
    // Keep last 50 events only
    if (log.length > 50) log.removeAt(0);
    await prefs.setStringList(_key, log);
  }

  static Future<List<Map<String, dynamic>>> getLog() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
  }
}
```

Call `CrashLogger.logEvent()` every time the confidence model fires (both triggered and non-triggered events). This gives you real-world calibration data for tuning the thresholds later.

**File: `lib/screens/profile_screen.dart`** — add a "Crash log" entry in the debug section that shows the last 10 entries with their signal values and whether they escalated.

### P4-F · Test Mode

**File: `lib/services/crash_detector.dart`**:

```dart
static Future<void> simulateCrash() async {
  _addSignal(SignalType.impact, 1.0);
  _addSignal(SignalType.speedDrop, 1.0);
  _addSignal(SignalType.orientation, 1.0);
  await Future.delayed(Duration(milliseconds: 500));
  _addSignal(SignalType.immobility, 1.0);
}
```

In Profile screen: "Test crash detection" button → calls `simulateCrash()` → full SOS flow fires → rider can cancel at countdown.

---

## Priority 5 — Group Awareness & UI

### P5-A · Minimal Group Coordination Actions

Add two quick actions to the group ride screen. These write a single flag to Firebase — no new collections, no new backend logic.

**File: `lib/services/group_ride_service.dart`** — add to rider document:

```dart
// Write flag:
Future<void> broadcastQuickState(String code, String state) async {
  await _db.doc('group_rides/$code/riders/$_riderId').update({
    'quickState': state,          // 'waiting' | 'stopping' | null
    'quickStateAt': FieldValue.serverTimestamp(),
  });
  // Auto-clear after 5 minutes
  Future.delayed(Duration(minutes: 5), () => clearQuickState(code));
}

Future<void> clearQuickState(String code) async {
  await _db.doc('group_rides/$code/riders/$_riderId').update({
    'quickState': FieldValue.delete(),
    'quickStateAt': FieldValue.delete(),
  });
}
```

**File: `lib/screens/group_ride_screen.dart`** — add two buttons to the bottom panel:

- **"Wait for group"** → `broadcastQuickState(code, 'waiting')` → shows 🕐 badge on your marker
- **"I'm stopping"** → `broadcastQuickState(code, 'stopping')` → shows 🅿️ badge on your marker

Other riders see these badges on the map and in the rider list. Auto-clears after 5 minutes or when speed > 20 km/h.

This replaces the need to use WhatsApp for basic coordination without adding any backend complexity.

### P5-B · UI Noise Reduction While Riding

**Problem:** Displaying all alerts and panels while the rider is moving is a distraction hazard.

**File: `lib/screens/group_ride_screen.dart`** — implement a `_isMoving` boolean (true when speed > 10 km/h, debounced 5 s):

```dart
bool _isMoving = false;

// In GPS handler:
if (speed > 10 && !_isMoving) {
  Future.delayed(Duration(seconds: 5), () {
    if (mounted) setState(() => _isMoving = true);
  });
} else if (speed <= 10) {
  setState(() => _isMoving = false);
}
```

When `_isMoving == true`:
- **Show:** SOS alerts, disconnection alerts, separated-rider warnings, status bar
- **Hide:** Quick alert history feed, rider avatar panel, all non-critical UI
- **Reduce:** Map controls to essential only (no route planner sheet, no camera controls)

When `_isMoving == false` (stopped or slow):
- Restore full UI

This uses only speed data already computed from GPS — no extra work.

### P5-C · Live Status Bar

**File: `lib/screens/group_ride_screen.dart`** — persistent strip at top of map:

```
[ 🟢 LIVE  ·  4 riders  ·  2s ago ]
[ 🟡 DELAYED  ·  4 riders  ·  9s ago ]
[ 🔴 CONNECTION LOST  ·  last seen 22s ago ]
[ 🟡 GPS WEAK  ·  accuracy 48 m ]
```

Implementation:
- `Timer.periodic(Duration(seconds: 1))` updates a `_lastUpdateAge` integer
- Colour thresholds: green < 5 s, yellow 5–15 s, red > 15 s
- GPS quality from `Position.accuracy` field (already available in geolocator)
- No extra packages or connections needed

### P5-D · Deprioritised Features — Disable Cleanly

**File: `lib/screens/dashboard_screen.dart`**

Comment out weather and fuel widgets. Replace with a group ride quick-join card:

```dart
// These stay in code but are not rendered — easy to re-enable later
// WeatherWidget(),
// FuelRangeWidget(),

GroupQuickJoinCard(), // new: text field + "Join" button, or "Start new session"
```

**File: `lib/screens/stats_screen.dart`**

Remove the weekly bar chart (decorative, not core). Keep the rides list — it is useful. Add a simple summary row: `X rides · Y km · Z hours total`.

---

## Background Service — LocationHub

*(Unchanged from v1 plan — included here for completeness)*

**New file: `lib/services/location_hub.dart`**

Single GPS stream shared by both `RideService` and `GroupRideService`. Eliminates duplicate battery drain from two simultaneous GPS subscriptions.

```
LocationHub (singleton)
  ├── _positionStream  — one Geolocator stream
  ├── positionBroadcast  — StreamController.broadcast()
  ├── start(speed) → applies adaptive settings
  ├── stop()
  └── currentPosition → Position?
```

**Adaptive tiers:**

| Speed | Interval | Distance filter |
|---|---|---|
| > 60 km/h | 1 s | 5 m |
| 25–60 km/h | 2 s | 8 m |
| < 25 km/h | 5 s | 10 m |
| Stationary < 5 km/h (30 s) | 10 s | 15 m |

**Watchdog:** `Timer.periodic(30 s)` checks `FlutterBackgroundService().isRunning()` and restarts if dead.

---

## Implementation Order

| # | What | Key Files | Gate |
|---|---|---|---|
| 1 | Battery gate | `battery_guard.dart`, `battery_gate_screen.dart`, session start | **Required before ride start works** |
| 2 | Firebase write throttle | `group_ride_service.dart` → `updatePosition()` | Required before any group testing |
| 3 | Offline SOS fallback | `sos_service.dart` | Required before field use |
| 4 | Session recovery | `group_ride_service.dart`, `main.dart` | Required before field use |
| 5 | Rider state time buffers | `group_ride_service.dart` → `_computeRiderState()` | Before enabling group awareness UI |
| 6 | Crash logging | `crash_logger.dart`, `crash_detector.dart` | Before any real-world crash testing |
| 7 | UI noise reduction | `group_ride_screen.dart` | Before field rides |
| 8 | Quick group actions | `group_ride_service.dart`, `group_ride_screen.dart` | After P2 is stable |
| 9 | Confidence-score crash detection | `crash_detector.dart` | After logging is wired up |
| 10 | LocationHub + adaptive GPS | `location_hub.dart` | Alongside or after P1-B |

---

## What Is Out of Scope (Do Not Build)

- Turn-by-turn navigation
- Complex ride analytics or charts
- Weather or fuel features (re-enable later if needed)
- Advanced UI polish or animations
- Any paid API or new backend service
- iOS build (defer until Android is solid)

---

## Firebase Schema — Final State

```
group_rides/{code}
  ├── createdAt, createdBy, active, leaderId
  └── riders/{riderId}
      ├── name, emoji, lat, lng, speed
      ├── state: "moving" | "stopped" | "separated" | "disconnected"
      ├── quickState?: "waiting" | "stopping"   ← NEW
      ├── quickStateAt?: Timestamp               ← NEW
      └── updatedAt: Timestamp
  ├── sos/{riderId}
      ├── name, emoji, lat, lng, active
      ├── triggeredAt, acknowledgedBy[], resolvedAt?, resolvedBy?
  └── alerts/{docId}
      ├── riderId, name, emoji, alertEmoji, message, sentAt
```

---

## Local Storage — SharedPreferences Keys

| Key | Type | Purpose |
|---|---|---|
| `active_session_code` | String | Session recovery |
| `active_session_joined_at` | String (ISO) | Session recovery age check |
| `last_lat` / `last_lng` | double | Last known position on rejoin |
| `battery_prompt_shown` | bool | OEM guidance shown once |
| `crash_log_v1` | List\<String\> | JSON crash event log (last 50) |
| `pending_sos` | List\<String\> | Offline SOS queue for sync on reconnect |

---

*v2 — Revised 2026-04-22 to incorporate zero-budget practical constraints.*  
*Scope: tracking reliability, group awareness, SOS. Nothing else.*
