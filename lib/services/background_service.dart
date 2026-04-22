import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

/// Top-level background entry point — runs in a separate isolate.
/// GPS streaming is handled in the main isolate by RideService; this service
/// just keeps a foreground notification alive so Android won't kill the app
/// (and the GPS stream) while the screen is off.
@pragma('vm:entry-point')
void _onBackgroundStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();

  // Allow the main isolate to update the notification text while riding
  service.on('updateNotification').listen((data) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'MotoPulse – Ride Active',
        content: data?['text'] as String? ?? 'GPS tracking is running',
      );
    }
  });

  // Stop signal from the main isolate
  service.on('stop').listen((_) => service.stopSelf());
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Manages the background foreground-service that keeps GPS alive while the
/// screen is off during an active ride.
class BackgroundService {
  static final _svc = FlutterBackgroundService();
  static bool _configured = false;

  /// Call once at app startup (from main.dart) to register the service config.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> configure() async {
    if (_configured) return;
    _configured = true;

    await _svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'motopulse_ride_channel',
        initialNotificationTitle: 'MotoPulse – Ride Active',
        initialNotificationContent: 'GPS tracking is running',
        foregroundServiceNotificationId: 101,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onBackgroundStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Call when a ride starts — shows the persistent notification that
  /// prevents Android from killing the GPS stream on screen-off.
  static Future<void> startRideService() async {
    await configure(); // idempotent
    await _svc.startService();
  }

  /// Call when a ride ends or is cancelled.
  static Future<void> stopRideService() async {
    _svc.invoke('stop');
    // Small delay to let the background isolate handle the stop event
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Optionally push a live status string to the notification while riding.
  static void updateNotificationText(String text) {
    _svc.invoke('updateNotification', {'text': text});
  }
}
