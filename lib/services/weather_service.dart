import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final double tempC;
  final int weatherCode;
  final double windSpeedKmh;

  const WeatherData({
    required this.tempC,
    required this.weatherCode,
    required this.windSpeedKmh,
  });

  String get condition {
    if (weatherCode == 0) return 'Clear sky';
    if (weatherCode <= 2) return 'Partly cloudy';
    if (weatherCode == 3) return 'Overcast';
    if (weatherCode <= 48) return 'Foggy';
    if (weatherCode <= 57) return 'Drizzle';
    if (weatherCode <= 67) return 'Rain';
    if (weatherCode <= 77) return 'Snow';
    if (weatherCode <= 82) return 'Rain showers';
    if (weatherCode <= 86) return 'Snow showers';
    if (weatherCode <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  String get emoji {
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '⛅';
    if (weatherCode == 3) return '☁️';
    if (weatherCode <= 48) return '🌫️';
    if (weatherCode <= 57) return '🌦️';
    if (weatherCode <= 67) return '🌧️';
    if (weatherCode <= 77) return '❄️';
    if (weatherCode <= 82) return '🌧️';
    if (weatherCode <= 86) return '🌨️';
    if (weatherCode <= 99) return '⛈️';
    return '🌡️';
  }

  /// Short riding advice string.
  String get ridingCondition {
    if (weatherCode == 0 && windSpeedKmh < 40) return 'Perfect for riding';
    if (weatherCode <= 2 && windSpeedKmh < 40) return 'Good for riding';
    if (weatherCode <= 3 && windSpeedKmh < 60) return 'Ride with caution';
    if (weatherCode <= 3) return 'Very windy — be careful';
    if (weatherCode <= 48) return 'Foggy — low visibility';
    if (weatherCode <= 67) return 'Rain — not advised';
    if (weatherCode <= 77) return 'Snow — avoid riding';
    if (weatherCode <= 82) return 'Rain showers — caution';
    if (weatherCode <= 99) return 'Storm — stay home';
    return 'Conditions unclear';
  }

  bool get isGoodForRiding => weatherCode <= 3 && windSpeedKmh < 50;

  /// Badge label shown next to conditions.
  String get badge {
    if (weatherCode == 0 && windSpeedKmh < 40) return 'CLEAR';
    if (weatherCode <= 2 && windSpeedKmh < 40) return 'GOOD';
    if (weatherCode <= 3) return 'FAIR';
    if (weatherCode <= 48) return 'FOGGY';
    if (weatherCode <= 67) return 'RAIN';
    if (weatherCode <= 77) return 'SNOW';
    if (weatherCode <= 99) return 'STORM';
    return 'N/A';
  }
}

class WeatherService {
  static WeatherData? _cached;
  static DateTime? _lastFetch;
  static double? _lastLat;
  static double? _lastLng;

  /// Fetch weather for [lat]/[lng]. Returns cached value if < 15 min old
  /// and position hasn't shifted significantly.
  static Future<WeatherData?> fetchWeather(double lat, double lng) async {
    final now = DateTime.now();
    if (_cached != null &&
        _lastFetch != null &&
        now.difference(_lastFetch!).inMinutes < 15 &&
        _lastLat != null &&
        (_lastLat! - lat).abs() < 0.05 &&
        (_lastLng! - lng).abs() < 0.05) {
      return _cached;
    }

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(4)}'
        '&longitude=${lng.toStringAsFixed(4)}'
        '&current=temperature_2m,weathercode,windspeed_10m'
        '&timezone=auto',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'MotoPulse/1.0'})
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>;
        _cached = WeatherData(
          tempC: (current['temperature_2m'] as num).toDouble(),
          weatherCode: (current['weathercode'] as num).toInt(),
          windSpeedKmh: (current['windspeed_10m'] as num).toDouble(),
        );
        _lastFetch = now;
        _lastLat = lat;
        _lastLng = lng;
        return _cached;
      }
    } catch (_) {}
    return _cached; // Return stale cache rather than nothing
  }

  static WeatherData? get cached => _cached;
}
