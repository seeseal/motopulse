import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/group_ride_service.dart';
import '../services/route_service.dart';

class GroupRideScreen extends StatefulWidget {
  final String? initialCode;
  const GroupRideScreen({super.key, this.initialCode});

  @override
  State<GroupRideScreen> createState() => _GroupRideScreenState();
}

class _GroupRideScreenState extends State<GroupRideScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  String? _roomCode;
  LatLng _myPosition = const LatLng(0, 0);
  List<RiderPosition> _riders = [];
  List<LatLng> _myRoute = [];
  StreamSubscription<Position>? _gpsStream;
  StreamSubscription<List<RiderPosition>>? _ridersStream;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _mapReady = false;
  final TextEditingController _codeController = TextEditingController();

  // SOS alerts
  StreamSubscription<List<Map<String, dynamic>>>? _sosStream;
  List<Map<String, dynamic>> _activeSOSAlerts = [];

  @override
  void initState() {
    super.initState();
    _startGPS();
    // Reconnect to an already-active session if the service has one running
    if (GroupRideService.isActive) {
      _connectToRoom(GroupRideService.activeCode!);
    } else if (widget.initialCode != null) {
      _joinRide(widget.initialCode!);
    }
  }

  @override
  void dispose() {
    // Cancel UI streams only — the service's GPS keeps running in background
    // so the group ride stays alive while the user browses other tabs
    _gpsStream?.cancel();
    _ridersStream?.cancel();
    _sosStream?.cancel();
    _alertsStream?.cancel();
    _mapController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startGPS() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    // This stream is for the map UI only — actual Firestore updates
    // are handled by GroupRideService._startPersistentGPS()
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

      if (_mapReady && _myRoute.length <= 2) {
        try { _mapController.move(ll, 15); } catch (_) {}
      }
    });
  }

  Future<void> _createRide() async {
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

  // Quick alerts
  StreamSubscription<List<Map<String, dynamic>>>? _alertsStream;
  List<Map<String, dynamic>> _recentAlerts = [];

  void _connectToRoom(String code) {
    setState(() {
      _roomCode = code;
      _isConnected = true;
    });

    _ridersStream = GroupRideService.streamRiders(code).listen((riders) {
      if (mounted) setState(() => _riders = riders);
    });

    // Subscribe to SOS alerts
    _sosStream?.cancel();
    _sosStream = GroupRideService.streamSOS(code).listen((alerts) {
      if (!mounted) return;
      setState(() => _activeSOSAlerts = alerts);
    });

    // Subscribe to quick alerts
    _alertsStream?.cancel();
    _alertsStream = GroupRideService.streamAlerts(code).listen((alerts) {
      if (!mounted) return;
      setState(() => _recentAlerts = alerts);
      if (alerts.isNotEmpty) {
        HapticFeedback.selectionClick();
      }
    });
  }

  void _leaveRide() {
    if (_roomCode != null) {
      GroupRideService.leaveGroupRide(_roomCode!); // stops service GPS too
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Stack(
        children: [
          // Map
          _buildMap(),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  // Back button
                  _glassButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 10),
                  // Title
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
                  ]
                ],
              ),
            ),
          ),

          // Center my location button
          Positioned(
            right: 16,
            bottom: 120,
            child: _glassButton(
              onTap: () {
                if (_mapReady) {
                  _mapController.move(_myPosition, 15);
                }
              },
              child: const Icon(Icons.my_location_rounded,
                  color: Colors.white70, size: 20),
            ),
          ),

          // Bottom action area
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),

          // SOS Alert Overlay
          if (_activeSOSAlerts.isNotEmpty)
            _SOSAlertOverlay(
              alerts: _activeSOSAlerts,
              onDismiss: () => setState(() => _activeSOSAlerts = []),
              onNavigate: (lat, lng) {
                _mapController.move(LatLng(lat, lng), 16);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _myPosition.latitude != 0
            ? _myPosition
            : const LatLng(3.1390, 101.6869), // Default: KL
        initialZoom: 15,
        maxZoom: 19,
        minZoom: 3,
      ),
      children: [
        // Dark map tiles
        TileLayer(
          urlTemplate:
              'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.example.motopulse',
          maxZoom: 19,
        ),

        // Planned route (blue)
        if (RouteService.hasRoute)
          PolylineLayer(
            polylines: [
              Polyline(
                points: RouteService.activePlan!.routePoints,
                color: const Color(0xFF2979FF).withOpacity(0.7),
                strokeWidth: 4,
                borderColor: const Color(0xFF2979FF).withOpacity(0.2),
                borderStrokeWidth: 8,
                pattern: StrokePattern.dashed(segments: [12, 6]),
              ),
            ],
          ),

        // Ridden route (red)
        if (_myRoute.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _myRoute,
                color: const Color(0xFFE8003D).withOpacity(0.8),
                strokeWidth: 3.5,
                borderColor: const Color(0xFFE8003D).withOpacity(0.2),
                borderStrokeWidth: 6,
              ),
            ],
          ),

        // Planned route waypoint markers
        if (RouteService.hasRoute)
          MarkerLayer(
            markers: RouteService.activePlan!.waypoints
                .asMap()
                .entries
                .map((e) => Marker(
                      point: e.value.position,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2979FF),
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            e.key == 0
                                ? 'A'
                                : e.key ==
                                        RouteService
                                                .activePlan!
                                                .waypoints
                                                .length -
                                            1
                                    ? 'B'
                                    : '${e.key}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),

        // Other riders markers
        MarkerLayer(
          markers: [
            // Other riders
            ..._riders.map((rider) {
              if (rider.lat == 0 && rider.lng == 0) return null;
              return Marker(
                point: LatLng(rider.lat, rider.lng),
                width: 56,
                height: 70,
                child: _RiderMarker(rider: rider, isMe: false),
              );
            }).whereType<Marker>(),

            // My marker
            if (_myPosition.latitude != 0)
              Marker(
                point: _myPosition,
                width: 56,
                height: 70,
                child: const _MyMarker(),
              ),
          ],
        ),
      ],
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
                                color: const Color(0xFFE8003D)
                                    .withOpacity(0.3)),
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

            // ── Quick Alerts ──────────────────────────────────────────────
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

    // Not connected — show create/join options
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

// ── Rider marker widget ──────────────────────────────────────────────────────

class _RiderMarker extends StatelessWidget {
  final RiderPosition rider;
  final bool isMe;
  const _RiderMarker({required this.rider, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFF6B00),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B00).withOpacity(0.4),
                blurRadius: 10,
              )
            ],
          ),
          child: Center(
            child: Text(rider.emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF111111).withOpacity(0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            rider.riderName,
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _MyMarker extends StatelessWidget {
  const _MyMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF120008),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE8003D), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE8003D).withOpacity(0.5),
                blurRadius: 14,
                spreadRadius: 2,
              )
            ],
          ),
          child: const Icon(Icons.navigation_rounded,
              color: Color(0xFFE8003D), size: 22),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE8003D).withOpacity(0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('YOU',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
      ],
    );
  }
}

// ── SOS Alert Overlay ───────────────────────────────────────────────────────

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
                    const Text('🆘',
                        style: TextStyle(fontSize: 40)),
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
                              border:
                                  Border.all(color: Colors.white12),
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

// ── Join Sheet ──────────────────────────────────────────────────────────────

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
        ],
      ),
    );
  }
}

// ── Share Sheet ─────────────────────────────────────────────────────────────

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
