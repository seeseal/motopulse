import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local crash-event log stored in SharedPreferences.
///
/// Records both confirmed triggers (triggered = true) and high-confidence
/// near-misses (triggered = false, score > 0.4). This gives real-world data
/// for tuning detection thresholds without any backend required.
///
/// Capped at 50 entries (oldest dropped first).
class CrashLogger {
  CrashLogger._();

  static const _key = 'crash_log_v1';
  static const _maxEntries = 50;

  /// Log a detection event.
  ///
  /// [impactScore]       — normalised impact signal (0.0–1.0)
  /// [speedKmh]          — rider speed at the moment of detection
  /// [orientationScore]  — normalised gyro/orientation signal (0.0–1.0, 0 if not yet wired)
  /// [confidenceScore]   — composite score that drove the decision
  /// [triggered]         — true if this event escalated to the SOS countdown
  static Future<void> logEvent({
    required double impactScore,
    required double speedKmh,
    required double orientationScore,
    required double confidenceScore,
    required bool triggered,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final log = prefs.getStringList(_key) ?? [];

      log.add(jsonEncode({
        'ts': DateTime.now().toIso8601String(),
        'impact': _round(impactScore),
        'speed': _round(speedKmh),
        'orientation': _round(orientationScore),
        'confidence': _round(confidenceScore),
        'triggered': triggered,
      }));

      // Keep only the most recent entries
      if (log.length > _maxEntries) {
        log.removeRange(0, log.length - _maxEntries);
      }

      await prefs.setStringList(_key, log);
    } catch (_) {
      // Never let logging crash the crash detector
    }
  }

  /// Returns the stored log entries, newest first.
  static Future<List<Map<String, dynamic>>> getLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? [];
      return raw
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Clears all stored entries (useful for testing).
  static Future<void> clearLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static double _round(double v) =>
      double.parse(v.toStringAsFixed(3));
}
