import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/ride_model.dart';
import 'background_service.dart';
import 'crash_detector.dart';

/// Singleton that owns the GPS subscription and ride timer.
/// Lives outside the widget tree so the ride survives app-switching,
/// navigation, or screen-off without being cancelled.
class RideService {
  RideService._();

  // ── State ──────────────────────────────────────────────────────────────────
  static bool isRiding = false;
  static bool isSaving = false;
  static double speedKmh = 0;
  static double distanceKm = 0;
  static double maxSpeedKmh = 0;
  static double totalSpeedSum = 0;
  static int speedReadings = 0;
  static int elapsedSeconds = 0;
  static DateTime? startTime;
  static List<LatLng> routePoints = [];
  static Position? lastPosition;

  // ── Stream ─────────────────────────────────────────────────────────────────
  static final StreamController<void> _ctrl =
      StreamController<void>.broadcast();
  static Stream<void> get onChange => _ctrl.stream;

  // ── Internal subscriptions ────────────────────────────────────────────────
  static StreamSubscription<Position>? _gpsSub;
  static Timer? _timer;

  // ── Public API ─────────────────────────────────────────────────────────────

  static void startRide({LatLng? initialPos}) {
    isRiding = true;
    isSaving = false;
    speedKmh = 0;
    distanceKm = 0;
    maxSpeedKmh = 0;
    totalSpeedSum = 0;
    speedReadings = 0;
    elapsedSeconds = 0;
    lastPosition = null;
    startTime = DateTime.now();
    routePoints = initialPos != null ? [initialPos] : [];

    BackgroundService.startRideService();
    _startGPS();
    _startTimer();
    CrashDetector.startMonitoring();
    _notify();
  }

  /// Returns saved RideModel on success, null on too-short ride.
  static Future<RideModel?> stopRide() async {
    isSaving = true;
    _notify();

    _gpsSub?.cancel();
    _gpsSub = null;
    _timer?.cancel();
    _timer = null;
    CrashDetector.stopMonitoring();
    BackgroundService.stopRideService();

    // Discard ghost / test rides
    if (elapsedSeconds < 5 || distanceKm < 0.05) {
      _reset();
      return null;
    }

    // Downsample route to ≤200 points
    List<List<double>> savedRoute = [];
    final pts = routePoints;
    if (pts.isNotEmpty) {
      if (pts.length <= 200) {
        savedRoute = pts.map((p) => [p.latitude, p.longitude]).toList();
      } else {
        final step = pts.length / 200.0;
        for (int i = 0; i < 200; i++) {
          final idx = (i * step).round().clamp(0, pts.length - 1);
          savedRoute.add([pts[idx].latitude, pts[idx].longitude]);
        }
      }
    }

    final avgSpeed =
        speedReadings > 0 ? totalSpeedSum / speedReadings : 0.0;
    final ride = RideModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: RideModel.generateTitle(startTime ?? DateTime.now()),
      distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
      durationSeconds: elapsedSeconds,
      maxSpeedKmh: double.parse(maxSpeedKmh.toStringAsFixed(1)),
      avgSpeedKmh: double.parse(avgSpeed.toStringAsFixed(1)),
      startTime: startTime ?? DateTime.now(),
      routePoints: savedRoute,
    );

    await RideStorage.saveRide(ride);
    _reset();
    return ride;
  }

  static void cancelRide() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _timer?.cancel();
    _timer = null;
    CrashDetector.stopMonitoring();
    BackgroundService.stopRideService();
    _reset();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static void _startGPS() {
    _gpsSub?.cancel();

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 1),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      );
    }

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      // Discard noisy / inaccurate fixes (main cause of path hallucination)
      if (pos.accuracy > 20.0) return;

      final spd = (pos.speed * 3.6).clamp(0.0, 300.0);
      speedKmh = spd;
      if (spd > maxSpeedKmh) maxSpeedKmh = spd;
      if (spd > 0) {
        totalSpeedSum += spd;
        speedReadings++;
      }

      if (lastPosition != null) {
        final d = Geolocator.distanceBetween(
              lastPosition!.latitude,
              lastPosition!.longitude,
              pos.latitude,
              pos.longitude,
            ) /
            1000;
        // Reject teleport jumps (GPS glitch > 500 m in one reading)
        if (d < 0.5) distanceKm += d;
      }
      lastPosition = pos;

      final ll = LatLng(pos.latitude, pos.longitude);
      routePoints.add(ll);
      if (routePoints.length > 1000) routePoints.removeAt(0);

      _notify();
    });
  }

  static void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isRiding) {
        elapsedSeconds++;
        _notify();
      }
    });
  }

  static void _reset() {
    isRiding = false;
    isSaving = false;
    speedKmh = 0;
    distanceKm = 0;
    maxSpeedKmh = 0;
    totalSpeedSum = 0;
    speedReadings = 0;
    elapsedSeconds = 0;
    lastPosition = null;
    startTime = null;
    routePoints = [];
    _notify();
  }

  static void _notify() {
    if (!_ctrl.isClosed) _ctrl.add(null);
  }

  // ── Formatted helpers ─────────────────────────────────────────────────────
  static String get formattedTime {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
