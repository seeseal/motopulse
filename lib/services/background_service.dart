import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android foreground service that keeps GPS alive while
/// the app is backgrounded during an active ride.
class BackgroundService {
  static bool _initialized = false;

  static void _ensureInit() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'motopulse_ride_channel',
        channelName: 'MotoPulse Ride Tracking',
        channelDescription: 'Keeps GPS active during your ride',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Call when a ride starts — shows persistent notification to prevent
  /// Android from killing the GPS stream.
  static Future<void> startRideService() async {
    _ensureInit();
    await FlutterForegroundTask.startService(
      notificationTitle: 'MotoPulse – Ride Active',
      notificationText: 'GPS tracking is running',
      callback: _backgroundCallback,
    );
  }

  /// Call when a ride ends or is cancelled.
  static Future<void> stopRideService() async {
    await FlutterForegroundTask.stopService();
  }
}

/// Top-level callback required by flutter_foreground_task.
@pragma('vm:entry-point')
void _backgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_RideTaskHandler());
}

class _RideTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive tick — actual GPS is handled by Geolocator in the main isolate.
    FlutterForegroundTask.updateService(
      notificationText: 'GPS tracking is running',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
