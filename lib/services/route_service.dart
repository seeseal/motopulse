import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class Waypoint {
  final String label;
  final LatLng position;
  const Waypoint({required this.label, required this.position});
}

class RoutePlan {
  final List<Waypoint> waypoints;
  final List<LatLng> routePoints;
  final double distanceKm;
  final int durationMinutes;

  const RoutePlan({
    required this.waypoints,
    required this.routePoints,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class RouteService {
  // Persists across screens so tracking + group ride both see the planned route
  static RoutePlan? _activePlan;

  static RoutePlan? get activePlan => _activePlan;
  static bool get hasRoute => _activePlan != null;

  static void clearRoute() => _activePlan = null;

  /// Search for places by name using Nominatim (free, no key needed)
  static Future<List<Map<String, dynamic>>> searchPlace(String query) async {
    if (query.trim().length < 3) return [];
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json&limit=5&addressdetails=1',
    );
    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'MotoPulse/1.0 (riding companion app)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        return data.map((e) {
          // Build a short readable name
          final addr = e['address'] as Map<String, dynamic>? ?? {};
          final short = [
            addr['road'] ?? addr['pedestrian'] ?? '',
            addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '',
            addr['country'] ?? '',
          ].where((s) => s.isNotEmpty).take(2).join(', ');

          return {
            'name': short.isNotEmpty ? short : (e['display_name'] as String),
            'full': e['display_name'] as String,
            'lat': double.parse(e['lat'] as String),
            'lng': double.parse(e['lon'] as String),
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Calculate a driving route via OSRM (free, open source, no key needed)
  static Future<RoutePlan?> calculateRoute(List<Waypoint> waypoints) async {
    if (waypoints.length < 2) return null;

    final coords = waypoints
        .map((w) => '${w.position.longitude},${w.position.latitude}')
        .join(';');

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coords'
      '?overview=full&geometries=geojson',
    );

    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'MotoPulse/1.0',
      }).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final route = (data['routes'] as List).first as Map<String, dynamic>;
        final geometry = route['geometry'] as Map<String, dynamic>;
        final coords = geometry['coordinates'] as List;

        final points = coords
            .map((c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList();

        final distanceM = (route['distance'] as num).toDouble();
        final durationS = (route['duration'] as num).toDouble();

        final plan = RoutePlan(
          waypoints: waypoints,
          routePoints: points,
          distanceKm: distanceM / 1000,
          durationMinutes: (durationS / 60).round(),
        );
        _activePlan = plan;
        return plan;
      }
    } catch (_) {}
    return null;
  }
}
