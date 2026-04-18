import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMapsKey = 'AIzaSyDOqKLFQxLlVmYlGjHMT2XY7Y5o0vkg1x4';

class Waypoint {
  final String label;
  final LatLng position;
  const Waypoint({required this.label, required this.position});

  Map<String, dynamic> toJson() => {
        'label': label,
        'lat': position.latitude,
        'lng': position.longitude,
      };

  factory Waypoint.fromJson(Map<String, dynamic> j) => Waypoint(
        label: j['label'] as String,
        position: LatLng(j['lat'] as double, j['lng'] as double),
      );
}

class SegmentInfo {
  final String fromLabel;
  final String toLabel;
  final double distanceKm;
  final int durationMinutes;

  const SegmentInfo({
    required this.fromLabel,
    required this.toLabel,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class RoutePlan {
  final List<Waypoint> waypoints;
  final List<LatLng> routePoints;
  final double distanceKm;
  final int durationMinutes;
  final List<SegmentInfo> segments;

  const RoutePlan({
    required this.waypoints,
    required this.routePoints,
    required this.distanceKm,
    required this.durationMinutes,
    required this.segments,
  });
}

class SavedRoute {
  final String id;
  final String name;
  final List<Waypoint> waypoints;
  final double distanceKm;
  final int durationMinutes;
  final DateTime savedAt;

  const SavedRoute({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distanceKm,
    required this.durationMinutes,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedRoute.fromJson(Map<String, dynamic> j) => SavedRoute(
        id: j['id'] as String,
        name: j['name'] as String,
        waypoints: (j['waypoints'] as List)
            .map((w) => Waypoint.fromJson(w as Map<String, dynamic>))
            .toList(),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        durationMinutes: j['durationMinutes'] as int,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
}

class RouteService {
  static RoutePlan? _activePlan;
  static RoutePlan? get activePlan => _activePlan;
  static bool get hasRoute => _activePlan != null;
  static void clearRoute() => _activePlan = null;

  // ── Geocoding (Nominatim — free, no key) ─────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchPlace(String query) async {
    if (query.trim().length < 3) return [];
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json&limit=6&addressdetails=1',
    );
    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'MotoPulse/1.1 (riding companion app)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List;
        return data.map((e) {
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

  // ── Routing (Google Directions API) ──────────────────────────────────────

  static Future<RoutePlan?> calculateRoute(
    List<Waypoint> waypoints, {
    bool avoidTolls = false,
    bool avoidHighways = false,
  }) async {
    if (waypoints.length < 2) return null;

    final origin =
        '${waypoints.first.position.latitude},${waypoints.first.position.longitude}';
    final destination =
        '${waypoints.last.position.latitude},${waypoints.last.position.longitude}';

    final avoidParams = <String>[];
    if (avoidTolls) avoidParams.add('tolls');
    if (avoidHighways) avoidParams.add('highways');

    final waypointStr = waypoints.length > 2
        ? waypoints
            .sublist(1, waypoints.length - 1)
            .map((w) => '${w.position.latitude},${w.position.longitude}')
            .join('|')
        : null;

    final params = {
      'origin': origin,
      'destination': destination,
      'key': _kMapsKey,
      'units': 'metric',
      if (waypointStr != null) 'waypoints': waypointStr,
      if (avoidParams.isNotEmpty) 'avoid': avoidParams.join('|'),
    };

    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      params,
    );

    try {
      final res =
          await http.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      if ((data['status'] as String) != 'OK') return null;

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final legs = (route['legs'] as List).cast<Map<String, dynamic>>();

      // Decode the overview polyline
      final encoded =
          (route['overview_polyline'] as Map<String, dynamic>)['points'] as String;
      final routePoints = _decodePolyline(encoded);

      // Build segment info from legs
      final segments = <SegmentInfo>[];
      double totalDist = 0;
      int totalDur = 0;

      for (var i = 0; i < legs.length; i++) {
        final leg = legs[i];
        final distM = ((leg['distance'] as Map)['value'] as num).toDouble();
        final durS = ((leg['duration'] as Map)['value'] as num).toInt();
        final distKm = distM / 1000;
        final durMin = (durS / 60).round();
        totalDist += distKm;
        totalDur += durMin;

        segments.add(SegmentInfo(
          fromLabel: waypoints[i].label,
          toLabel: waypoints[i + 1].label,
          distanceKm: distKm,
          durationMinutes: durMin,
        ));
      }

      final plan = RoutePlan(
        waypoints: waypoints,
        routePoints: routePoints,
        distanceKm: totalDist,
        durationMinutes: totalDur,
        segments: segments,
      );
      _activePlan = plan;
      return plan;
    } catch (_) {}
    return null;
  }

  // ── Polyline decoder ──────────────────────────────────────────────────────

  static List<LatLng> _decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += dlng;
      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  // ── Saved routes ──────────────────────────────────────────────────────────

  static const _kSavedKey = 'saved_routes_v1';

  static Future<List<SavedRoute>> loadSavedRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSavedKey);
    if (raw == null) return [];
    try {
      final list = json.decode(raw) as List;
      return list
          .map((e) => SavedRoute.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRoute(SavedRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSavedRoutes();
    existing.removeWhere((r) => r.id == route.id);
    existing.insert(0, route);
    await prefs.setString(
        _kSavedKey, json.encode(existing.map((r) => r.toJson()).toList()));
  }

  static Future<void> deleteSavedRoute(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSavedRoutes();
    existing.removeWhere((r) => r.id == id);
    await prefs.setString(
        _kSavedKey, json.encode(existing.map((r) => r.toJson()).toList()));
  }
}
