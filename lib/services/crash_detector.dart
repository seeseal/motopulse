import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'crash_logger.dart';
import 'ride_service.dart';

/// Multi-signal crash detection state machine.
///
/// A crash is only confirmed when ALL three signals agree:
///   1. High-G impact   — net user-acceleration ≥ 3.5 g (~34 m/s²)
///   2. Pre-event speed — rider was moving > 25 km/h when impact happened
///   3. Post-impact     — speed stays below 10 km/h for 15 consecutive seconds
///                        (indicates the bike has stopped after impact)
///
/// If the rider is still moving after 15 s the event is treated as a false
/// positive (speed bump, pothole, etc.) and silently cancelled.
///
/// Cooldown behaviour:
///   • 60 s minimum between any two confirmed triggers.
///   • Cooldown is STATIC — it persists even if stopMonitoring/startMonitoring
///     is called (e.g. app restart mid-ride). This prevents a re-trigger loop
///     where an app restart during an incident clears the cooldown.
///   • Call [extendCooldown] when the SOS overlay goes active so the detector
///     stays suppressed for the full SOS handling window.
///
/// Every trigger (and high-confidence near-miss) is written locally via
/// [CrashLogger] for later threshold tuning.
class CrashDetector {
  CrashDetector._();

  // ── Tunable thresholds ─────────────────────────────────────────────────────
  /// Minimum impact magnitude (userAccelerometer, gravity removed) in m/s².
  /// 3.5 g × 9.81 ≈ 34.3 m/s²
  static const double _impactThresholdMs2 = 3.5 * 9.81;

  /// Rider must be travelling faster than this when the impact happens.
  static const double _preEventSpeedKmh = 25.0;

  /// After impact, speed must stay below this to count as immobility.
  static const double _immobilitySpeedKmh = 10.0;

  /// How many consecutive immobile seconds before we confirm a crash.
  static const int _immobilityRequiredSecs = 15;

  /// Minimum seconds between two crash triggers.
  static const int _cooldownSecs = 60;

  // ── Internal state ─────────────────────────────────────────────────────────
  static _CrashState _state = _CrashState.idle;
  static StreamSubscription<UserAccelerometerEvent>? _accelSub;
  static Timer? _immobilityTicker;
  static Timer? _safetyTimeout;
  static int _immobileCount = 0;
  static DateTime? _lastTrigger;

  /// True while a confirmed incident is being handled (SOS countdown/active).
  /// Prevents any second trigger until [clearIncident] is called.
  static bool _incidentActive = false;

  // ── Public stream ──────────────────────────────────────────────────────────
  static final _ctrl = StreamController<void>.broadcast();

  /// Listen to confirm a crash has been detected and show the alert overlay.
  static Stream<void> get onCrashDetected => _ctrl.stream;

  // ── Public API ─────────────────────────────────────────────────────────────

  static void startMonitoring() {
    // NOTE: _lastTrigger is intentionally NOT reset here so the cooldown
    // survives a monitoring restart (e.g. app killed and relaunched mid-ride).
    _state = _CrashState.idle;
    _immobileCount = 0;
    _accelSub?.cancel();
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccel, onError: (_) {});
  }

  static void stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _cancelImmobilityCheck();
    _state = _CrashState.idle;
    _immobileCount = 0;
    // _lastTrigger intentionally kept — cooldown should persist across restarts
  }

  /// Extend the cooldown window by [extraSeconds] from now.
  ///
  /// Call this when the SOS overlay goes active so a post-crash restart
  /// or secondary impact does not fire a second alert while the rider
  /// (or first responders) are still handling the incident.
  static void extendCooldown({int extraSeconds = 120}) {
    final extended = DateTime.now().add(Duration(seconds: extraSeconds));
    // Only extend — never shorten an existing cooldown
    if (_lastTrigger == null ||
        extended.isAfter(_lastTrigger!.add(Duration(seconds: _cooldownSecs)))) {
      _lastTrigger = extended.subtract(Duration(seconds: _cooldownSecs));
    }
  }

  /// Call when the SOS has been fully resolved (rider marked safe or group
  /// acknowledged). Clears the incident lock so detection can resume normally.
  static void clearIncident() {
    _incidentActive = false;
    // Also clear the cooldown — the incident is over, future events should
    // be treated fresh.
    _lastTrigger = null;
  }

  /// Call when the user manually CANCELS the SOS countdown (pre-escalation).
  /// Cancellation means the rider is conscious and safe — reset the cooldown
  /// so a new real crash can trigger the detector again immediately.
  static void resetCooldown() {
    _lastTrigger = null;
    _incidentActive = false;
  }

  /// Injects all signals at full strength to simulate a crash.
  /// Use for testing the full SOS escalation flow on real devices.
  static void simulateCrash() {
    if (!RideService.isRiding) return;
    // Bypass cooldown, incident lock, and speed check for simulation only
    _state = _CrashState.immobilityCheck;
    _startImmobilityCheck(simulated: true);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  // Captured at impact time — used for logging after confirmation
  static double _capturedImpactMag = 0.0;
  static double _capturedSpeedKmh = 0.0;

  static void _onAccel(UserAccelerometerEvent e) {
    if (!RideService.isRiding) return;

    // Only check for new impacts when idle
    if (_state != _CrashState.idle) return;

    // Incident lock — a confirmed crash is already being handled
    if (_incidentActive) return;

    // Cooldown guard — uses the STATIC _lastTrigger so it survives restarts
    if (_lastTrigger != null &&
        DateTime.now().difference(_lastTrigger!).inSeconds < _cooldownSecs) {
      return;
    }

    // Signal 1: High-G impact
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag < _impactThresholdMs2) return;

    final normImpact = (mag / _impactThresholdMs2).clamp(0.0, 1.0);
    final currentSpeed = RideService.speedKmh;

    // Signal 2: Pre-event speed — was the rider actually moving?
    if (currentSpeed < _preEventSpeedKmh) {
      // Near-miss: impact fired but speed gate failed — log for tuning
      CrashLogger.logEvent(
        impactScore: normImpact,
        speedKmh: currentSpeed,
        orientationScore: 0.0,
        confidenceScore: normImpact * 0.35, // impact weight only
        triggered: false,
      );
      return;
    }

    // Capture values for the log (written on confirmation or near-miss)
    _capturedImpactMag = normImpact;
    _capturedSpeedKmh = currentSpeed;

    // Impact + speed confirmed — move to immobility check
    _state = _CrashState.immobilityCheck;
    _startImmobilityCheck();
  }

  static void _startImmobilityCheck({bool simulated = false}) {
    _immobileCount = 0;

    // Tick every second and count how long speed stays below threshold
    _immobilityTicker?.cancel();
    _immobilityTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      // In simulation mode skip the ride-active and speed checks
      if (!simulated) {
        if (!RideService.isRiding) {
          t.cancel();
          _resetToIdle();
          return;
        }

        if (RideService.speedKmh < _immobilitySpeedKmh) {
          _immobileCount++;
        } else {
          // Rider is moving again — false positive, cancel and log near-miss
          t.cancel();
          _resetToIdle(wasImmobilityCheck: true);
          return;
        }
      } else {
        // Simulation: immediately count up to required seconds
        _immobileCount++;
      }

      if (_immobileCount >= _immobilityRequiredSecs) {
        // Signal 3 confirmed — all three signals met
        t.cancel();
        _confirmCrash(simulated: simulated);
      }
    });

    // Safety: if the check hangs, reset after 2× the window
    _safetyTimeout?.cancel();
    _safetyTimeout = Timer(
      Duration(seconds: _immobilityRequiredSecs * 2),
      () {
        if (_state == _CrashState.immobilityCheck) _resetToIdle();
      },
    );
  }

  static void _confirmCrash({bool simulated = false}) {
    _cancelImmobilityCheck();
    _lastTrigger = DateTime.now();
    _incidentActive = true; // lock — cleared only by clearIncident() or resetCooldown()
    _state = _CrashState.idle;

    // Log the event — never await; fire-and-forget so we don't block the stream
    CrashLogger.logEvent(
      impactScore: simulated ? 1.0 : _capturedImpactMag,
      speedKmh: simulated ? 0.0 : _capturedSpeedKmh,
      orientationScore: 0.0, // gyro not yet wired — placeholder
      confidenceScore: 1.0,  // state machine is binary: if we reach here, it's 1.0
      triggered: true,
    );

    if (!_ctrl.isClosed) _ctrl.add(null);
  }

  static void _cancelImmobilityCheck() {
    _immobilityTicker?.cancel();
    _immobilityTicker = null;
    _safetyTimeout?.cancel();
    _safetyTimeout = null;
  }

  static void _resetToIdle({bool wasImmobilityCheck = false}) {
    _cancelImmobilityCheck();
    if (wasImmobilityCheck && _capturedImpactMag > 0) {
      // Near-miss: impact + speed fired but immobility didn't confirm —
      // log as a false positive so thresholds can be tuned later.
      CrashLogger.logEvent(
        impactScore: _capturedImpactMag,
        speedKmh: _capturedSpeedKmh,
        orientationScore: 0.0,
        confidenceScore: _capturedImpactMag * 0.35 + 0.25, // impact + speed weights
        triggered: false,
      );
    }
    _state = _CrashState.idle;
    _immobileCount = 0;
    _capturedImpactMag = 0.0;
    _capturedSpeedKmh = 0.0;
  }
}

enum _CrashState { idle, immobilityCheck }
