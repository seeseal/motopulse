import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'ride_service.dart';

/// Monitors the accelerometer during an active ride.
/// Fires [onCrashDetected] when a sudden high-G impact is detected.
///
/// Detection logic:
///   - Uses userAccelerometer (gravity removed) so we measure pure impact force.
///   - Threshold: 20 m/s² (~2g) of net acceleration while moving >10 km/h.
///   - 45-second cooldown after each trigger to prevent duplicate alerts.
class CrashDetector {
  CrashDetector._();

  // Tune these if you get false positives / missed detections
  static const double _impactThreshold = 20.0; // m/s²
  static const double _minSpeedKmh    = 10.0;  // only detect while moving
  static const int    _cooldownSecs   = 45;

  static StreamSubscription<UserAccelerometerEvent>? _sub;
  static DateTime? _lastTrigger;

  static final StreamController<void> _ctrl =
      StreamController<void>.broadcast();

  /// Listen to this stream to show the crash-alert overlay.
  static Stream<void> get onCrashDetected => _ctrl.stream;

  // ── Public API ────────────────────────────────────────────────────────────

  static void startMonitoring() {
    _sub?.cancel();
    _sub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccel, onError: (_) {});
  }

  static void stopMonitoring() {
    _sub?.cancel();
    _sub = null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static void _onAccel(UserAccelerometerEvent e) {
    // Only fire during an active ride at meaningful speed
    if (!RideService.isRiding) return;
    if (RideService.speedKmh < _minSpeedKmh) return;

    // Check cooldown
    if (_lastTrigger != null &&
        DateTime.now().difference(_lastTrigger!).inSeconds < _cooldownSecs) {
      return;
    }

    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (magnitude >= _impactThreshold) {
      _lastTrigger = DateTime.now();
      if (!_ctrl.isClosed) _ctrl.add(null);
    }
  }
}
