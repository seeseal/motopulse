import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RideModel {
  final String id;
  final String title;
  final double distanceKm;
  final int durationSeconds;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final DateTime startTime;

  RideModel({
    required this.id,
    required this.title,
    required this.distanceKm,
    required this.durationSeconds,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.startTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'distanceKm': distanceKm,
        'durationSeconds': durationSeconds,
        'maxSpeedKmh': maxSpeedKmh,
        'avgSpeedKmh': avgSpeedKmh,
        'startTime': startTime.toIso8601String(),
      };

  factory RideModel.fromJson(Map<String, dynamic> json) => RideModel(
        id: json['id'],
        title: json['title'],
        distanceKm: (json['distanceKm'] as num).toDouble(),
        durationSeconds: json['durationSeconds'],
        maxSpeedKmh: (json['maxSpeedKmh'] as num).toDouble(),
        avgSpeedKmh: (json['avgSpeedKmh'] as num).toDouble(),
        startTime: DateTime.parse(json['startTime']),
      );

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    return '${m}min';
  }

  String get relativeDate {
    final now = DateTime.now();
    final diff = now.difference(startTime);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  static String generateTitle(DateTime time) {
    final hour = time.hour;
    if (hour < 6) return 'Night Ride';
    if (hour < 12) return 'Morning Ride';
    if (hour < 17) return 'Afternoon Ride';
    if (hour < 20) return 'Evening Ride';
    return 'Night Ride';
  }
}

class RideStorage {
  static const _key = 'saved_rides';

  static Future<List<RideModel>> loadRides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final List<dynamic> list = jsonDecode(raw);
      final rides = list.map((e) => RideModel.fromJson(e)).toList();
      rides.sort((a, b) => b.startTime.compareTo(a.startTime));
      return rides;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRide(RideModel ride) async {
    final prefs = await SharedPreferences.getInstance();
    final rides = await loadRides();
    rides.add(ride);
    final encoded = jsonEncode(rides.map((r) => r.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<Map<String, dynamic>> getStats() async {
    final rides = await loadRides();
    if (rides.isEmpty) {
      return {
        'totalKm': 0.0,
        'totalRides': 0,
        'thisWeekKm': 0.0,
        'topSpeedKmh': 0.0,
        'totalHours': 0.0,
        'weeklyData': List.filled(7, 0.0),
      };
    }

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weeklyKm = List.filled(7, 0.0);

    double totalKm = 0;
    double thisWeekKm = 0;
    double topSpeed = 0;
    int totalSeconds = 0;

    for (final ride in rides) {
      totalKm += ride.distanceKm;
      totalSeconds += ride.durationSeconds;
      if (ride.maxSpeedKmh > topSpeed) topSpeed = ride.maxSpeedKmh;
      if (ride.startTime.isAfter(weekStart)) {
        thisWeekKm += ride.distanceKm;
        final dayIndex = ride.startTime.weekday - 1;
        weeklyKm[dayIndex] += ride.distanceKm;
      }
    }

    final maxDay = weeklyKm.reduce((a, b) => a > b ? a : b);
    final normalizedWeekly = maxDay > 0
        ? weeklyKm.map((d) => d / maxDay).toList()
        : List.filled(7, 0.0);

    return {
      'totalKm': totalKm,
      'totalRides': rides.length,
      'thisWeekKm': thisWeekKm,
      'topSpeedKmh': topSpeed,
      'totalHours': totalSeconds / 3600,
      'weeklyData': normalizedWeekly,
    };
  }
}
