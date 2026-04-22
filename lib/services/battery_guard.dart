import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks and requests the Android battery-optimisation exemption that keeps
/// the foreground GPS service alive on all OEM ROMs.
///
/// On iOS this always returns [isExempted] = true (not relevant there).
class BatteryGuard {
  BatteryGuard._();

  /// Returns true if MotoPulse is already exempted from battery optimisation.
  static Future<bool> isExempted() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  /// Opens the system dialog for the user to grant the exemption.
  /// Returns true when granted.
  static Future<bool> requestExemption() async {
    if (!Platform.isAndroid) return true;
    final result = await Permission.ignoreBatteryOptimizations.request();
    return result.isGranted;
  }

  /// Returns a short, OEM-specific instruction for the battery settings path.
  /// Used in the blocking gate screen so the user knows exactly where to go
  /// if the system dialog doesn't appear or doesn't cover their ROM variant.
  static Future<String> oemGuidance() async {
    if (!Platform.isAndroid) return '';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.manufacturer.toLowerCase();

      if (['xiaomi', 'redmi', 'poco'].any(brand.contains)) {
        return 'Settings → Battery & performance → Power saver → Choose apps → MotoPulse → No restrictions';
      } else if (brand == 'samsung') {
        return 'Settings → Battery → Background usage limits → Never sleeping apps → add MotoPulse';
      } else if (['realme', 'oppo'].any(brand.contains)) {
        return 'Settings → Battery → Power saving → Custom → MotoPulse → No restrictions';
      } else if (['huawei', 'honor'].any(brand.contains)) {
        return 'Settings → Battery → App launch → MotoPulse → Manage manually → enable all toggles';
      } else if (brand.contains('oneplus')) {
        return 'Settings → Battery → Battery optimization → All apps → MotoPulse → Don\'t optimize';
      }
    } catch (_) {}

    // Generic fallback
    return 'Settings → Apps → MotoPulse → Battery → Unrestricted';
  }
}
