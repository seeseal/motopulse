import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../models/ride_model.dart';

/// Full-screen map showing the GPS route for a single past ride.
///
/// Route points are drawn as a red polyline. Green marker = start,
/// red marker = end. Camera auto-fits to show the entire route.
/// A bottom panel shows the ride's key stats.
class RideDetailScreen extends StatefulWidget {
  final RideModel ride;

  const RideDetailScreen({super.key, required this.ride});

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  final Completer<gmaps.GoogleMapController> _mapCompleter = Completer();
  Set<gmaps.Polyline> _polylines = {};
  Set<gmaps.Marker> _markers = {};
  gmaps.CameraPosition _initialCamera = const gmaps.CameraPosition(
    target: gmaps.LatLng(20.5937, 78.9629), // India centre fallback
    zoom: 5,
  );
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _buildRouteOverlays();
  }

  void _buildRouteOverlays() {
    final points = widget.ride.routePoints;
    if (points.isEmpty) return;

    // Convert stored [lat, lng] pairs to LatLng
    final latLngs = points
        .map((p) => gmaps.LatLng(p[0], p[1]))
        .toList();

    // Polyline — red to match the live ride tracking style
    _polylines = {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route'),
        points: latLngs,
        color: const Color(0xFFE8003D),
        width: 4,
        jointType: gmaps.JointType.round,
        endCap: gmaps.Cap.roundCap,
        startCap: gmaps.Cap.roundCap,
      ),
    };

    // Start marker — green dot
    _markers = {
      gmaps.Marker(
        markerId: const gmaps.MarkerId('start'),
        position: latLngs.first,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueGreen),
        infoWindow: const gmaps.InfoWindow(title: 'Start'),
      ),
      gmaps.Marker(
        markerId: const gmaps.MarkerId('end'),
        position: latLngs.last,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRed),
        infoWindow: const gmaps.InfoWindow(title: 'End'),
      ),
    };

    // Compute bounds from all points to auto-fit the camera
    double minLat = latLngs.first.latitude;
    double maxLat = latLngs.first.latitude;
    double minLng = latLngs.first.longitude;
    double maxLng = latLngs.first.longitude;
    for (final p in latLngs) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Use centre of bounds as initial camera position
    _initialCamera = gmaps.CameraPosition(
      target: gmaps.LatLng(
        (minLat + maxLat) / 2,
        (minLng + maxLng) / 2,
      ),
      zoom: 13,
    );

    setState(() => _mapReady = true);
  }

  /// Animates camera to fit all route points with padding.
  Future<void> _fitRoute() async {
    final points = widget.ride.routePoints;
    if (points.isEmpty) return;

    final controller = await _mapCompleter.future;
    final latLngs = points.map((p) => gmaps.LatLng(p[0], p[1])).toList();

    double minLat = latLngs.first.latitude;
    double maxLat = latLngs.first.latitude;
    double minLng = latLngs.first.longitude;
    double maxLng = latLngs.first.longitude;
    for (final p in latLngs) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add a small delta so single-point routes aren't zoomed to infinity
    final latPad = ((maxLat - minLat) * 0.15).clamp(0.002, 10.0);
    final lngPad = ((maxLng - minLng) * 0.15).clamp(0.002, 10.0);

    controller.animateCamera(
      gmaps.CameraUpdate.newLatLngBounds(
        gmaps.LatLngBounds(
          southwest: gmaps.LatLng(minLat - latPad, minLng - lngPad),
          northeast: gmaps.LatLng(maxLat + latPad, maxLng + lngPad),
        ),
        60, // padding in pixels
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final hasRoute = ride.routePoints.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          if (hasRoute)
            gmaps.GoogleMap(
              initialCameraPosition: _initialCamera,
              mapType: gmaps.MapType.normal,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              polylines: _polylines,
              markers: _markers,
              style: _kDarkMapStyle,
              onMapCreated: (controller) {
                if (!_mapCompleter.isCompleted) {
                  _mapCompleter.complete(controller);
                }
                // Fit route after map is ready
                Future.delayed(const Duration(milliseconds: 300), _fitRoute);
              },
            )
          else
            // No route data — show placeholder
            Container(
              color: const Color(0xFF0A0A0A),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, color: Colors.white12, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No route data saved\nfor this ride',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white24, fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top bar ────────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _glassButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ride.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${ride.relativeDate}  ·  ${_formatDate(ride.startTime)}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom stats panel ─────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E0E),
                border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary stat: distance
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            ride.distanceKm.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w200,
                              height: 1,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6, left: 6),
                            child: Text('km',
                                style: TextStyle(
                                    color: Colors.white30, fontSize: 16)),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                ride.formattedDuration,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w300),
                              ),
                              const Text('duration',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 16),

                      // Secondary stats row
                      Row(
                        children: [
                          _statCell(
                            '${ride.maxSpeedKmh.toStringAsFixed(0)}',
                            'top speed',
                            'km/h',
                          ),
                          _vDivider(),
                          _statCell(
                            '${ride.avgSpeedKmh.toStringAsFixed(0)}',
                            'avg speed',
                            'km/h',
                          ),
                          _vDivider(),
                          _statCell(
                            _formatTime(ride.startTime),
                            'started at',
                            '',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassButton({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF111111).withOpacity(0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _statCell(String value, String label, String unit) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w300)),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 3),
                  child: Text(unit,
                      style: const TextStyle(
                          color: Colors.white30, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 32,
        color: Colors.white.withOpacity(0.06),
      );

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Dark map style (matches live ride tracking screen) ────────────────────────

const String _kDarkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#141414"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#141414"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#111111"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#1e1e1e"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#212121"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]}
]''';
