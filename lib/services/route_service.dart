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

  // ── Place Search (Google Places Autocomplete + Details) ──────────────────

  /// Returns autocomplete predictions with [place_id] but no lat/lng yet.
  /// Call [getPlaceDetails] to resolve coordinates from a prediction.
  static Future<List<Map<String, dynamic>>> searchPlace(String query) async {
    if (query.trim().length < 2) return [];
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query.trim(),
        'key': _kMapsKey,
        'types': 'geocode|establishment',
        'language': 'en',
      },
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['status'] != 'OK') return [];
        final predictions =
            (data['predictions'] as List).cast<Map<String, dynamic>>();
        return predictions.take(6).map((p) {
          final desc = p['description'] as String;
          return {
            'name': desc.split(',').first.trim(),
            'full': desc,
            'place_id': p['place_id'] as String,
            'lat': null,
            'lng': null,
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Resolves a [placeId] from [searchPlace] into full details with lat/lng.
  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'geometry,name,formatted_address',
        'key': _kMapsKey,
      },
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['status'] != 'OK') return null;
        final result = data['result'] as Map<String, dynamic>;
        final loc = (result['geometry'] as Map<String, dynamic>)['location']
            as Map<String, dynamic>;
        final addr = result['formatted_address'] as String? ??
            result['name'] as String? ??
            placeId;
        return {
          'name': addr.split(',').first.trim(),
          'full': addr,
          'lat': (loc['lat'] as num).toDouble(),
          'lng': (loc['lng'] as num).toDouble(),
        };
      }
    } catch (_) {}
    return null;
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

  // ── OSRM Map Matching (road snapping) ────────────────────────────────────

  /// Snap a list of raw GPS points to actual roads using OSRM /match.
  /// Returns snapped coordinates, or the original list on any error.
  static Future<List<LatLng>> matchGpsTrace(List<LatLng> points) async {
    if (points.length < 2) return points;

    // Build coordinate string: lng,lat pairs separated by ;
    final coords =
        points.map((p) => '${p.longitude},${p.latitude}').join(';');
    // 25 m snap radius per point — tight enough to follow roads
    final radii = List.filled(points.length, '25').join(';');
    final uri = Uri.parse(
      'https://router.project-osrm.org/match/v1/driving/$coords'
      '?overview=full&geometries=geojson&radiuses=$radii&gaps=ignore',
    );

    try {
      final res = await http
          .get(uri, headers: {'User-Agent': 'MotoPulse/1.2'})
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return points;

      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return points;

      final matchings = data['matchings'] as List?;
      if (matchings == null || matchings.isEmpty) return points;

      final geometry =
          matchings.first['geometry'] as Map<String, dynamic>;
      final coordList = geometry['coordinates'] as List;
      return coordList
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return points; // fall back to raw GPS on error / timeout
    }
  }
}
