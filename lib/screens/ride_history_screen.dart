import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../models/ride_model.dart';

// ── Dark map style (shared with other map screens) ────────────────────────────

const _kDarkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0a0a0a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0a0a0a"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#111111"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#0a0a0a"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#1e1e1e"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#212121"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#2d2d2d"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}
]''';

// ── Zoom helper ───────────────────────────────────────────────────────────────

double _zoomForPoints(List<gmaps.LatLng> points) {
  if (points.length < 2) return 14;
  double minLat = points.first.latitude;
  double maxLat = points.first.latitude;
  double minLng = points.first.longitude;
  double maxLng = points.first.longitude;
  for (final p in points) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  final span = math.max(maxLat - minLat, maxLng - minLng);
  if (span < 0.002) return 16;
  if (span < 0.008) return 15;
  if (span < 0.02)  return 14;
  if (span < 0.06)  return 13;
  if (span < 0.15)  return 12;
  if (span < 0.5)   return 11;
  if (span < 1.5)   return 10;
  return 9;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<RideModel> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rides = await RideStorage.loadRides();
    if (mounted) {
      setState(() {
        _rides = rides;
        _loading = false;
      });
    }
  }

  Future<void> _deleteRide(String id) async {
    HapticFeedback.mediumImpact();
    await RideStorage.deleteRide(id);
    await _load();
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear all rides?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w400)),
        content: const Text(
          'This will permanently delete all saved rides. This cannot be undone.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all',
                style: TextStyle(color: Color(0xFFE8003D))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await RideStorage.clearAll();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white54, size: 18),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'RIDE HISTORY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const Spacer(),
                  if (_rides.isNotEmpty)
                    GestureDetector(
                      onTap: _confirmClearAll,
                      child: const Text(
                        'Clear all',
                        style: TextStyle(color: Color(0xFFE8003D), fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFE8003D), strokeWidth: 1.5))
                  : _rides.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: const Color(0xFFE8003D),
                          backgroundColor: const Color(0xFF1A1A1A),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            itemCount: _rides.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => Dismissible(
                              key: Key(_rides[i].id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _deleteRide(_rides[i].id),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8003D).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.delete_outline,
                                    color: Color(0xFFE8003D), size: 22),
                              ),
                              child: _RideCard(ride: _rides[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.motorcycle_rounded, color: Colors.white12, size: 56),
          SizedBox(height: 16),
          Text('No rides yet',
              style: TextStyle(color: Colors.white38, fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Start a ride to build your history',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Ride Card ─────────────────────────────────────────────────────────────────

class _RideCard extends StatelessWidget {
  final RideModel ride;
  const _RideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(ride.startTime);
    final hasRoute = ride.routePoints.length >= 2;

    // Convert stored [lat, lng] pairs → gmaps.LatLng for the mini-map
    final gmPoints = ride.routePoints
        .map((p) => gmaps.LatLng(p[0], p[1]))
        .toList();

    // Centre of the route for the initial camera position
    final center = hasRoute
        ? gmaps.LatLng(
            gmPoints.map((p) => p.latitude).reduce((a, b) => a + b) /
                gmPoints.length,
            gmPoints.map((p) => p.longitude).reduce((a, b) => a + b) /
                gmPoints.length,
          )
        : const gmaps.LatLng(3.1390, 101.6869); // fallback: KL

    final zoom = hasRoute ? _zoomForPoints(gmPoints) : 14.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mini-map (Google Maps lite mode) ──────────────────────────────
          if (hasRoute)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 130,
                child: gmaps.GoogleMap(
                  key: Key('minimap_${ride.id}'),
                  liteModeEnabled: true,
                  initialCameraPosition: gmaps.CameraPosition(
                    target: center,
                    zoom: zoom,
                  ),
                  onMapCreated: (controller) {
                    // Apply dark style; fire-and-forget (lite mode, no state needed)
                    controller.setMapStyle(_kDarkMapStyle);
                  },
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  polylines: {
                    gmaps.Polyline(
                      polylineId: const gmaps.PolylineId('route'),
                      points: gmPoints,
                      color: const Color(0xFFE8003D),
                      width: 3,
                    ),
                  },
                  markers: {
                    // Start marker — white
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('start'),
                      position: gmPoints.first,
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                          gmaps.BitmapDescriptor.hueAzure),
                    ),
                    // End marker — red
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('end'),
                      position: gmPoints.last,
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                          gmaps.BitmapDescriptor.hueRed),
                    ),
                  },
                ),
              ),
            ),

          // ── Stats panel ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + date row
                Row(
                  children: [
                    if (!hasRoute) ...[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8003D).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFE8003D).withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.motorcycle_rounded,
                            color: Color(0xFFE8003D), size: 16),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(date,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    // Distance badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8003D).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFE8003D).withOpacity(0.2)),
                      ),
                      child: Text(
                        '${ride.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                            color: Color(0xFFE8003D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Stats row
                Row(
                  children: [
                    _statChip(Icons.timer_outlined, ride.formattedDuration),
                    const SizedBox(width: 8),
                    _statChip(Icons.speed_rounded,
                        '${ride.avgSpeedKmh.toStringAsFixed(0)} avg'),
                    const SizedBox(width: 8),
                    _statChip(Icons.arrow_upward_rounded,
                        '${ride.maxSpeedKmh.toStringAsFixed(0)} max'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38, size: 12),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  ·  $h12:$m $ampm';
  }
}
