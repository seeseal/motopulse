import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
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
/// A 60-second cooldown prevents duplicate events from the same incident.
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

  // ── Public stream ──────────────────────────────────────────────────────────
  static final _ctrl = StreamController<void>.broadcast();

  /// Listen to confirm a crash has been detected and show the alert overlay.
  static Stream<void> get onCrashDetected => _ctrl.stream;

  // ── Public API ─────────────────────────────────────────────────────────────

  static void startMonitoring() {
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
  }

  // ── Private ────────────────────────────────────────────────────────────────

  static void _onAccel(UserAccelerometerEvent e) {
    if (!RideService.isRiding) return;

    // Only check for new impacts when idle
    if (_state != _CrashState.idle) return;

    // Cooldown guard
    if (_lastTrigger != null &&
        DateTime.now().difference(_lastTrigger!).inSeconds < _cooldownSecs) {
      return;
    }

    // Signal 1: High-G impact
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (mag < _impactThresholdMs2) return;

    // Signal 2: Pre-event speed — was the rider actually moving?
    if (RideService.speedKmh < _preEventSpeedKmh) return;

    // Impact + speed confirmed — move to immobility check
    _state = _CrashState.immobilityCheck;
    _startImmobilityCheck();
  }

  static void _startImmobilityCheck() {
    _immobileCount = 0;

    // Tick every second and count how long speed stays below threshold
    _immobilityTicker?.cancel();
    _immobilityTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!RideService.isRiding) {
        t.cancel();
        _resetToIdle();
        return;
      }

      if (RideService.speedKmh < _immobilitySpeedKmh) {
        _immobileCount++;
      } else {
        // Rider is moving again — false positive, reset quietly
        t.cancel();
        _resetToIdle();
        return;
      }

      if (_immobileCount >= _immobilityRequiredSecs) {
        // Signal 3 confirmed — all three signals met
        t.cancel();
        _confirmCrash();
      }
    });

    // Safety: if somehow the check hangs, reset after 2× the window
    _safetyTimeout?.cancel();
    _safetyTimeout = Timer(
      Duration(seconds: _immobilityRequiredSecs * 2),
      () {
        if (_state == _CrashState.immobilityCheck) _resetToIdle();
      },
    );
  }

  static void _confirmCrash() {
    _cancelImmobilityCheck();
    _lastTrigger = DateTime.now();
    _state = _CrashState.idle;
    if (!_ctrl.isClosed) _ctrl.add(null);
  }

  static void _cancelImmobilityCheck() {
    _immobilityTicker?.cancel();
    _immobilityTicker = null;
    _safetyTimeout?.cancel();
    _safetyTimeout = null;
  }

  static void _resetToIdle() {
    _cancelImmobilityCheck();
    _state = _CrashState.idle;
    _immobileCount = 0;
  }
}

enum _CrashState { idle, immobilityCheck }
