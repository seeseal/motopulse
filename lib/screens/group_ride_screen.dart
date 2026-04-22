import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/battery_guard.dart';
import '../services/group_ride_service.dart';
import '../services/route_service.dart';
import 'battery_gate_screen.dart';

// ── Dark map style ────────────────────────────────────────────────────────────

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

// ── Helper ────────────────────────────────────────────────────────────────────

gmaps.LatLng _gl(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

// ── Screen ────────────────────────────────────────────────────────────────────

class GroupRideScreen extends StatefulWidget {
  final String? initialCode;
  const GroupRideScreen({super.key, this.initialCode});

  @override
  State<GroupRideScreen> createState() => _GroupRideScreenState();
}

class _GroupRideScreenState extends State<GroupRideScreen>
    with SingleTickerProviderStateMixin {
  gmaps.GoogleMapController? _mapController;
  String? _roomCode;
  LatLng _myPosition = const LatLng(0, 0);
  List<RiderPosition> _riders = [];
  List<LatLng> _myRoute = [];
  StreamSubscription<Position>? _gpsStream;
  StreamSubscription<List<RiderPosition>>? _ridersStream;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _mapReady = false;
  bool _batteryExempted = true; // assume OK until checked
  final TextEditingController _codeController = TextEditingController();

  // SOS alerts
  StreamSubscription<List<Map<String, dynamic>>>? _sosStream;
  List<Map<String, dynamic>> _activeSOSAlerts = [];

  // Quick alerts
  StreamSubscription<List<Map<String, dynamic>>>? _alertsStream;
  List<Map<String, dynamic>> _recentAlerts = [];

  @override
  void initState() {
    super.initState();
    _checkBattery();
    _startGPS();
    if (GroupRideService.isActive) {
      _connectToRoom(GroupRideService.activeCode!);
    } else if (widget.initialCode != null) {
      _joinRide(widget.initialCode!);
    }
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _ridersStream?.cancel();
    _sosStream?.cancel();
    _alertsStream?.cancel();
    _mapController?.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkBattery() async {
    final exempted = await BatteryGuard.isExempted();
    if (mounted) setState(() => _batteryExempted = exempted);
  }

  // Gate helper — shows the blocking screen and returns true only when granted.
  Future<bool> _ensureBatteryExempted() async {
    if (_batteryExempted) return true;
    if (!mounted) return false;
    final granted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BatteryGateScreen()),
    );
    final nowExempted = granted == true;
    if (mounted) setState(() => _batteryExempted = nowExempted);
    return nowExempted;
  }

  Future<void> _startGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    _gpsStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _myPosition = ll;
        _myRoute.add(ll);
        if (_myRoute.length > 500) _myRoute.removeAt(0);
        _mapReady = true;
      });

      // Auto-centre on first GPS fix
      if (_mapReady && _myRoute.length <= 2) {
        _mapController?.animateCamera(
          gmaps.CameraUpdate.newLatLng(_gl(ll)),
        );
      }
    });
  }

  Future<void> _createRide() async {
    if (!await _ensureBatteryExempted()) return; // gate
    setState(() => _isLoading = true);
    try {
      final code = await GroupRideService.createGroupRide();
      _connectToRoom(code);
    } catch (e) {
      _showError('Could not create ride. Check Firebase setup.');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _joinRide(String code) async {
    if (!await _ensureBatteryExempted()) return; // gate
    setState(() => _isLoading = true);
    try {
      final success = await GroupRideService.joinGroupRide(code.toUpperCase());
      if (success) {
        _connectToRoom(code.toUpperCase());
      } else {
        _showError('Room not found. Check the code and try again.');
      }
    } catch (e) {
      _showError('Could not join ride. Check Firebase setup.');
    }
    setState(() => _isLoading = false);
  }

  void _connectToRoom(String code) {
    setState(() {
      _roomCode = code;
      _isConnected = true;
    });

    _ridersStream = GroupRideService.streamRiders(code).listen((riders) {
      if (mounted) setState(() => _riders = riders);
    });

    _sosStream?.cancel();
    _sosStream = GroupRideService.streamSOS(code).listen((alerts) {
      if (!mounted) return;
      setState(() => _activeSOSAlerts = alerts);
    });

    _alertsStream?.cancel();
    _alertsStream = GroupRideService.streamAlerts(code).listen((alerts) {
      if (!mounted) return;
      setState(() => _recentAlerts = alerts);
      if (alerts.isNotEmpty) HapticFeedback.selectionClick();
    });
  }

  void _leaveRide() {
    if (_roomCode != null) GroupRideService.leaveGroupRide(_roomCode!);
    _ridersStream?.cancel();
    _ridersStream = null;
    setState(() {
      _roomCode = null;
      _isConnected = false;
      _riders = [];
      _myRoute = [];
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showJoinSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _JoinSheet(
        onJoin: (code) {
          Navigator.pop(context);
          _joinRide(code);
        },
      ),
    );
  }

  void _showShareSheet() {
    if (_roomCode == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(code: _roomCode!),
    );
  }

  // ── Map polylines & markers ──────────────────────────────────────────────

  Set<gmaps.Polyline> _buildPolylines() {
    final polys = <gmaps.Polyline>{};

    // Planned route — blue dashed
    if (RouteService.hasRoute) {
      polys.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('planned'),
        points: RouteService.activePlan!.routePoints.map(_gl).toList(),
        color: const Color(0xFF2979FF).withOpacity(0.8),
        width: 5,
        patterns: [
          gmaps.PatternItem.dash(12),
          gmaps.PatternItem.gap(6),
        ],
      ));
    }

    // Ridden route — red solid
    if (_myRoute.length > 1) {
      polys.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('ridden'),
        points: _myRoute.map(_gl).toList(),
        color: const Color(0xFFE8003D).withOpacity(0.85),
        width: 4,
      ));
    }

    return polys;
  }

  Set<gmaps.Marker> _buildMarkers() {
    final markers = <gmaps.Marker>{};

    // Route waypoint markers (blue)
    if (RouteService.hasRoute) {
      final wps = RouteService.activePlan!.waypoints;
      for (var i = 0; i < wps.length; i++) {
        final label = i == 0
            ? 'A'
            : i == wps.length - 1
                ? 'B'
                : '$i';
        markers.add(gmaps.Marker(
          markerId: gmaps.MarkerId('wp_$i'),
          position: _gl(wps[i].position),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueBlue),
          infoWindow: gmaps.InfoWindow(
            title: label,
            snippet: wps[i].label,
          ),
        ));
      }
    }

    // Other riders (orange markers with name + emoji in InfoWindow)
    for (final rider in _riders) {
      if (rider.lat == 0 && rider.lng == 0) continue;
      markers.add(gmaps.Marker(
        markerId: gmaps.MarkerId('rider_${rider.riderName}'),
        position: gmaps.LatLng(rider.lat, rider.lng),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueOrange),
        infoWindow: gmaps.InfoWindow(
          title: '${rider.emoji}  ${rider.riderName}',
        ),
      ));
    }

    // My position (red marker)
    if (_myPosition.latitude != 0) {
      markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('me'),
        position: _gl(_myPosition),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRed),
        infoWindow: const gmaps.InfoWindow(title: '📍 YOU'),
      ));
    }

    return markers;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      // Persistent banner when battery optimisation is still active
      bottomNavigationBar: !_batteryExempted
          ? SafeArea(
              top: false,
              child: GestureDetector(
                onTap: _ensureBatteryExempted,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.orange.withOpacity(0.15),
                  child: Row(
                    children: [
                      const Icon(Icons.battery_alert_rounded,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tracking disabled — battery optimisation is ON. Tap to fix.',
                          style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: Stack(
        children: [
          _buildMap(),

          // Top bar
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.07)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isConnected
                                  ? const Color(0xFF00C853)
                                  : Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isConnected
                                ? 'GROUP RIDE  ·  $_roomCode'
                                : 'GROUP RIDE',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w400),
                          ),
                          if (_isConnected) ...[
                            const Spacer(),
                            Text(
                              '${_riders.length} rider${_riders.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                  if (_isConnected) ...[
                    const SizedBox(width: 10),
                    _glassButton(
                      onTap: _showShareSheet,
                      child: const Icon(Icons.share_rounded,
                          color: Colors.white70, size: 20),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // My-location button
          Positioned(
            right: 16,
            bottom: 120,
            child: _glassButton(
              onTap: () {
                if (_mapReady) {
                  _mapController?.animateCamera(
                    gmaps.CameraUpdate.newLatLngZoom(_gl(_myPosition), 15),
                  );
                }
              },
              child: const Icon(Icons.my_location_rounded,
                  color: Colors.white70, size: 20),
            ),
          ),

          // Bottom panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),

          // SOS overlay
          if (_activeSOSAlerts.isNotEmpty)
            _SOSAlertOverlay(
              alerts: _activeSOSAlerts,
              onDismiss: () => setState(() => _activeSOSAlerts = []),
              onNavigate: (lat, lng) {
                _mapController?.animateCamera(
                  gmaps.CameraUpdate.newLatLngZoom(
                      gmaps.LatLng(lat, lng), 16),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialTarget = _myPosition.latitude != 0
        ? _gl(_myPosition)
        : const gmaps.LatLng(3.1390, 101.6869); // Default: KL

    return gmaps.GoogleMap(
      onMapCreated: (controller) async {
        _mapController = controller;
        await controller.setMapStyle(_kDarkMapStyle);
        if (_myPosition.latitude != 0) {
          controller.animateCamera(
            gmaps.CameraUpdate.newLatLngZoom(_gl(_myPosition), 15),
          );
        }
      },
      initialCameraPosition: gmaps.CameraPosition(
        target: initialTarget,
        zoom: 15,
      ),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      polylines: _buildPolylines(),
      markers: _buildMarkers(),
    );
  }

  Widget _buildBottomPanel() {
    if (_isConnected) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        decoration: BoxDecoration(
          color: const Color(0xFF111111).withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.07)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('RIDERS',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 2.5)),
                const Spacer(),
                GestureDetector(
                  onTap: _leaveRide,
                  child: const Text('LEAVE RIDE',
                      style: TextStyle(
                          color: Color(0xFFE8003D),
                          fontSize: 10,
                          letterSpacing: 2)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_riders.isEmpty)
              const Text('Waiting for riders to join...',
                  style: TextStyle(color: Colors.white24, fontSize: 13))
            else
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _riders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final r = _riders[i];
                    return Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8003D).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFFE8003D).withOpacity(0.3)),
                          ),
                          child: Center(
                            child: Text(r.emoji,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.riderName.length > 8
                              ? '${r.riderName.substring(0, 7)}…'
                              : r.riderName,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // ── Quick Alerts ────────────────────────────────────────────────
            const SizedBox(height: 16),
            const Text('QUICK ALERTS',
                style: TextStyle(
                    color: Colors.white24, fontSize: 10, letterSpacing: 2.5)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GroupRideService.quickAlerts.map((a) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    GroupRideService.broadcastAlert(
                        a['message']!, a['emoji']!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${a["emoji"]} ${a["message"]} sent'),
                        backgroundColor: const Color(0xFF1A1A1A),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(a['emoji']!,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          a['message']!,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            // Latest alert feed (last 3)
            if (_recentAlerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._recentAlerts.take(3).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text(a['emoji'] ?? '🏍️',
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          a['name'] ?? 'Rider',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${a["alertEmoji"] ?? ""} ${a["message"] ?? ""}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      );
    }

    // Not connected — create / join panel
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        color: const Color(0xFF111111).withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RIDE WITH YOUR CREW',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create a room or join with a code',
            style: TextStyle(color: Colors.white30, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isLoading ? null : _createRide,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8003D), Color(0xFFFF6B00)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE8003D).withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.white))
                          : const Text('CREATE RIDE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  fontSize: 12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _isLoading ? null : _showJoinSheet,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Center(
                      child: Text('JOIN RIDE',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                              fontSize: 12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassButton({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF111111).withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── SOS Alert Overlay ────────────────────────────────────────────────────────

class _SOSAlertOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> alerts;
  final VoidCallback onDismiss;
  final void Function(double lat, double lng) onNavigate;

  const _SOSAlertOverlay({
    required this.alerts,
    required this.onDismiss,
    required this.onNavigate,
  });

  @override
  State<_SOSAlertOverlay> createState() => _SOSAlertOverlayState();
}

class _SOSAlertOverlayState extends State<_SOSAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alerts.first;
    final name = alert['name'] ?? 'Rider';
    final emoji = alert['emoji'] ?? '🆘';
    final lat = (alert['lat'] ?? 0.0) as double;
    final lng = (alert['lng'] ?? 0.0) as double;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Transform.scale(
              scale: _pulse.value,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0005),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: const Color(0xFFE8003D), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE8003D).withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🆘', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 12),
                    const Text(
                      'SOS ALERT',
                      style: TextStyle(
                        color: Color(0xFFE8003D),
                        fontSize: 13,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$emoji  $name needs help!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              widget.onNavigate(lat, lng);
                              widget.onDismiss();
                            },
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8003D),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'GO TO LOCATION',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white38, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Join Sheet ───────────────────────────────────────────────────────────────

class _JoinSheet extends StatefulWidget {
  final void Function(String code) onJoin;
  const _JoinSheet({required this.onJoin});

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('JOIN A RIDE',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300)),
          const SizedBox(height: 4),
          const Text('Enter the 6-character room code',
              style: TextStyle(color: Colors.white30, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
                letterSpacing: 8),
            maxLength: 6,
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ABC123',
              hintStyle: const TextStyle(
                  color: Colors.white12, fontSize: 28, letterSpacing: 8),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _ctrl.text.length == 6
                ? () => widget.onJoin(_ctrl.text.toUpperCase())
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _ctrl.text.length == 6
                    ? const Color(0xFFE8003D)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('JOIN',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withOpacity(0.08))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('OR',
                    style: TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        letterSpacing: 2)),
              ),
              Expanded(
                  child: Container(
                      height: 1, color: Colors.white.withOpacity(0.08))),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final code = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const _QRScanPage()),
              );
              if (code != null && code.length >= 6) {
                widget.onJoin(code.substring(0, 6).toUpperCase());
              }
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white54, size: 20),
                  SizedBox(width: 10),
                  Text('SCAN QR CODE',
                      style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Share Sheet ──────────────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String code;
  const _ShareSheet({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Text('INVITE RIDERS',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300)),
          const SizedBox(height: 4),
          const Text('Share this code or QR with your crew',
              style: TextStyle(color: Colors.white30, fontSize: 13)),
          const SizedBox(height: 28),

          // QR code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: 'motopulse://group/$code',
              version: QrVersions.auto,
              size: 160,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF080808),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF080808),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Code display
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied!')),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFE8003D).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy_rounded,
                      color: Colors.white38, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Tap to copy',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── QR Scanner Page ──────────────────────────────────────────────────────────

class _QRScanPage extends StatefulWidget {
  const _QRScanPage();

  @override
  State<_QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<_QRScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue?.trim().toUpperCase() ?? '';
    if (raw.isEmpty) return;
    final match = RegExp(r'[A-Z0-9]{6}').firstMatch(raw);
    if (match != null) {
      _scanned = true;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, match.group(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Room QR',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w300, letterSpacing: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_rounded, color: Colors.white54),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE8003D), width: 2.5),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: 230,
              height: 230,
              child: CustomPaint(painter: _CornerPainter()),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point at the host\'s QR code',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, letterSpacing: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const len = 24.0;
    const r = 18.0;
    final p = Paint()
      ..color = const Color(0xFFE8003D)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(r, 0), Offset(r + len, 0), p);
    canvas.drawLine(Offset(0, r), Offset(0, r + len), p);
    canvas.drawLine(
        Offset(size.width - r - len, 0), Offset(size.width - r, 0), p);
    canvas.drawLine(Offset(size.width, r), Offset(size.width, r + len), p);
    canvas.drawLine(Offset(r, size.height), Offset(r + len, size.height), p);
    canvas.drawLine(
        Offset(0, size.height - r - len), Offset(0, size.height - r), p);
    canvas.drawLine(Offset(size.width - r - len, size.height),
        Offset(size.width - r, size.height), p);
    canvas.drawLine(Offset(size.width, size.height - r - len),
        Offset(size.width, size.height - r), p);
  }

  @override
  bool shouldRepaint(_CornerPainter _) => false;
}
