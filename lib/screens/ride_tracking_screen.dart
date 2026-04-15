import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride_model.dart';
import '../services/route_service.dart';
import '../services/profile_service.dart';
import '../services/weather_service.dart';
import '../services/background_service.dart';
import 'group_ride_screen.dart';
import 'speedometer_screen.dart';

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({super.key});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen>
    with SingleTickerProviderStateMixin {
  bool _isRiding = false;
  bool _isSaving = false;

  // Live stats
  double _speedKmh = 0;
  double _distanceKm = 0;
  double _maxSpeedKmh = 0;
  double _totalSpeedSum = 0;
  int _speedReadings = 0;
  int _elapsedSeconds = 0;

  // GPS & Map
  StreamSubscription<Position>? _positionStream;
  Position? _lastPosition;
  DateTime? _rideStartTime;
  LatLng _currentLatLng = const LatLng(3.1390, 101.6869); // default: KL
  List<LatLng> _routePoints = [];
  bool _locationReady = false;
  final MapController _mapController = MapController();

  // Timer
  Timer? _timer;

  // Profile-driven settings
  double _speedLimitKmh = 100.0;
  double _fuelTankL = 15.0;
  double _fuelEfficiencyKmL = 30.0;
  bool _speedAlertActive = false;
  bool _speedAlertShownOnce = false;

  // Pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Load profile settings
    ProfileService.load().then((p) {
      if (mounted) setState(() {
        _speedLimitKmh = p.speedLimitKmh;
        _fuelTankL = p.fuelTankL;
        _fuelEfficiencyKmL = p.fuelEfficiencyKmL;
      });
    });
    // Delay init until after first frame so MapController is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initLocation();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionStream?.cancel();
    _timer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    try {
      // Timeout after 8 seconds so emulators don't hang
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentLatLng = ll;
          _locationReady = true;
        });
        // Safe to move — widget is already built by this point
        try {
          _mapController.move(ll, 15);
        } catch (_) {}
      }
    } catch (_) {
      // Location unavailable or timed out — use default KL coords
      if (mounted) setState(() => _locationReady = true);
    }
  }

  void _startRide() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Please enable location services.');
      return;
    }

    setState(() {
      _isRiding = true;
      _speedKmh = 0;
      _distanceKm = 0;
      _maxSpeedKmh = 0;
      _totalSpeedSum = 0;
      _speedReadings = 0;
      _elapsedSeconds = 0;
      _lastPosition = null;
      _routePoints = _locationReady ? [_currentLatLng] : [];
      _rideStartTime = DateTime.now();
    });

    // Start foreground service to prevent Android killing GPS in background
    BackgroundService.startRideService();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      if (!mounted) return;

      final speedMs = pos.speed < 0 ? 0.0 : pos.speed;
      final speedKmh = speedMs * 3.6;
      final ll = LatLng(pos.latitude, pos.longitude);

      double added = 0;
      if (_lastPosition != null) {
        added = Geolocator.distanceBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              pos.latitude,
              pos.longitude,
            ) /
            1000;
        if (added < 0.5) _distanceKm += added;
      }

      if (speedKmh > 0) {
        _totalSpeedSum += speedKmh;
        _speedReadings++;
      }
      if (speedKmh > _maxSpeedKmh) _maxSpeedKmh = speedKmh;

      // Speed alert
      final overLimit = speedKmh > _speedLimitKmh;
      if (overLimit && !_speedAlertShownOnce) {
        HapticFeedback.heavyImpact();
        _speedAlertShownOnce = true;
      }
      if (!overLimit) _speedAlertShownOnce = false;

      setState(() {
        _speedKmh = speedKmh;
        _speedAlertActive = overLimit;
        _currentLatLng = ll;
        _routePoints.add(ll);
        if (_routePoints.length > 1000) _routePoints.removeAt(0);
        _lastPosition = pos;
      });

      // Keep map centred while riding
      _mapController.move(ll, _mapController.camera.zoom);
    });
  }

  Future<void> _stopRide() async {
    // Discard rides under 5 seconds or under 0.05 km (emulator taps, false starts)
    if (_elapsedSeconds < 5 || _distanceKm < 0.05) {
      _cancelRide();
      if (mounted && _distanceKm < 0.05 && _elapsedSeconds >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride too short to save'),
            backgroundColor: Color(0xFF1A1A1A),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    _timer?.cancel();
    _positionStream?.cancel();
    BackgroundService.stopRideService();

    final avgSpeed =
        _speedReadings > 0 ? _totalSpeedSum / _speedReadings : 0.0;

    // Downsample route to ≤200 points for compact storage
    List<List<double>> savedRoute = [];
    if (_routePoints.isNotEmpty) {
      final pts = _routePoints;
      if (pts.length <= 200) {
        savedRoute = pts.map((p) => [p.latitude, p.longitude]).toList();
      } else {
        final step = pts.length / 200.0;
        for (int i = 0; i < 200; i++) {
          final idx = (i * step).round().clamp(0, pts.length - 1);
          savedRoute.add([pts[idx].latitude, pts[idx].longitude]);
        }
      }
    }

    final ride = RideModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: RideModel.generateTitle(_rideStartTime ?? DateTime.now()),
      distanceKm: double.parse(_distanceKm.toStringAsFixed(2)),
      durationSeconds: _elapsedSeconds,
      maxSpeedKmh: double.parse(_maxSpeedKmh.toStringAsFixed(1)),
      avgSpeedKmh: double.parse(avgSpeed.toStringAsFixed(1)),
      startTime: _rideStartTime ?? DateTime.now(),
      routePoints: savedRoute,
    );

    await RideStorage.saveRide(ride);
    setState(() {
      _isRiding = false;
      _isSaving = false;
      _speedKmh = 0;
    });

    if (mounted) _showRideSummary(ride);
  }

  void _cancelRide() {
    _timer?.cancel();
    _positionStream?.cancel();
    BackgroundService.stopRideService();
    setState(() {
      _isRiding = false;
      _speedKmh = 0;
      _distanceKm = 0;
      _elapsedSeconds = 0;
      _routePoints = [];
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showRoutePlanner() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoutePlannerSheet(
        onRouteSet: () => setState(() {}),
      ),
    );
  }

  void _showRideSummary(RideModel ride) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
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
            const Text('RIDE COMPLETE',
                style: TextStyle(
                    color: Color(0xFFE8003D),
                    fontSize: 11,
                    letterSpacing: 3)),
            const SizedBox(height: 6),
            Text(ride.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300)),
            const SizedBox(height: 24),
            Row(
              children: [
                _summaryTile(
                    'DISTANCE', '${ride.distanceKm.toStringAsFixed(2)} km'),
                _summaryTile('DURATION', ride.formattedDuration),
                _summaryTile('TOP SPEED',
                    '${ride.maxSpeedKmh.toStringAsFixed(0)} km/h'),
              ],
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8003D),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('DONE',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String get _formattedTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Column(
        children: [
          // ── Map (top portion) ─────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                // Real map
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLatLng,
                    initialZoom: 15,
                    maxZoom: 19,
                    minZoom: 5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    // Dark OpenStreetMap tiles
                    TileLayer(
                      urlTemplate:
                          'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.example.motopulse',
                      maxZoom: 19,
                    ),
                    // Planned route (blue dashed)
                    if (RouteService.hasRoute)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: RouteService.activePlan!.routePoints,
                            color: const Color(0xFF2979FF).withOpacity(0.7),
                            strokeWidth: 4,
                            borderColor:
                                const Color(0xFF2979FF).withOpacity(0.2),
                            borderStrokeWidth: 8,
                            pattern: StrokePattern.dashed(
                                segments: [12, 6]),
                          ),
                        ],
                      ),

                    // Waypoint markers
                    if (RouteService.hasRoute)
                      MarkerLayer(
                        markers: RouteService.activePlan!.waypoints
                            .asMap()
                            .entries
                            .map((e) => Marker(
                                  point: e.value.position,
                                  width: 30,
                                  height: 30,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF2979FF),
                                      border: Border.all(
                                          color: Colors.white, width: 2),
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
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),

                    // Ridden route (red)
                    if (_routePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: const Color(0xFFE8003D),
                            strokeWidth: 4,
                            borderColor:
                                const Color(0xFFE8003D).withOpacity(0.25),
                            borderStrokeWidth: 8,
                          ),
                        ],
                      ),
                    // My position marker
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLatLng,
                          width: 52,
                          height: 52,
                          child: AnimatedBuilder(
                            animation: _pulseAnim,
                            builder: (_, __) => Transform.scale(
                              scale: _isRiding ? _pulseAnim.value : 1.0,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFE8003D)
                                      .withOpacity(0.15),
                                  border: Border.all(
                                    color: const Color(0xFFE8003D),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFE8003D)
                                          .withOpacity(0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: Color(0xFFE8003D),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Header overlay
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const Text(
                          'TRACKING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const Spacer(),
                        // Route plan button
                        GestureDetector(
                          onTap: () => _showRoutePlanner(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: RouteService.hasRoute
                                  ? const Color(0xFF2979FF).withOpacity(0.15)
                                  : const Color(0xFF111111).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: RouteService.hasRoute
                                    ? const Color(0xFF2979FF).withOpacity(0.5)
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.route_rounded,
                                  size: 13,
                                  color: RouteService.hasRoute
                                      ? const Color(0xFF2979FF)
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  RouteService.hasRoute
                                      ? 'ROUTE SET'
                                      : 'PLAN ROUTE',
                                  style: TextStyle(
                                    color: RouteService.hasRoute
                                        ? const Color(0xFF2979FF)
                                        : Colors.white30,
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isRiding
                                  ? Colors.green.withOpacity(0.5)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isRiding
                                      ? Colors.green
                                      : Colors.white24,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isRiding ? 'LIVE' : 'IDLE',
                                style: TextStyle(
                                  color: _isRiding
                                      ? Colors.green
                                      : Colors.white30,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Re-center button
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: GestureDetector(
                    onTap: () =>
                        _mapController.move(_currentLatLng, 15),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Icon(Icons.my_location_rounded,
                          color: Colors.white54, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Speed alert banner ────────────────────────────────────────
          if (_speedAlertActive)
            Container(
              color: const Color(0xFFE8003D).withOpacity(0.92),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'SPEED ALERT  ·  ${_speedKmh.toStringAsFixed(0)} km/h',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'limit ${_speedLimitKmh.round()} km/h',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),

          // ── Stats panel (bottom portion) ─────────────────────────────
          Container(
            color: const Color(0xFF080808),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                // Speed + distance + duration row
                Row(
                  children: [
                    // Speed — big
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SPEED',
                                style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 9,
                                    letterSpacing: 2)),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _speedKmh.toStringAsFixed(0),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w200,
                                      height: 1),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 4, left: 4),
                                  child: Text('km/h',
                                      style: TextStyle(
                                          color: Colors.white30,
                                          fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Distance + Duration stacked
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          _statTile('DISTANCE',
                              '${_distanceKm.toStringAsFixed(2)} km'),
                          const SizedBox(height: 10),
                          _statTile('DURATION', _formattedTime),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Max speed row (only when riding)
                if (_isRiding)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.speed_rounded,
                            color: Colors.white24, size: 16),
                        const SizedBox(width: 10),
                        const Text('Max speed',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 13)),
                        const Spacer(),
                        Text(
                          '${_maxSpeedKmh.toStringAsFixed(0)} km/h',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                // Fuel range estimate (while riding)
                if (_isRiding && _fuelEfficiencyKmL > 0) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (_) {
                    final fuelPct = _fuelTankL > 0 && _fuelEfficiencyKmL > 0
                        ? (((_fuelTankL - _distanceKm / _fuelEfficiencyKmL) /
                                _fuelTankL)
                            .clamp(0.0, 1.0))
                        : 1.0;
                    final rangeKm = (fuelPct * _fuelTankL * _fuelEfficiencyKmL)
                        .clamp(0.0, 9999.0);
                    final barColor = fuelPct > 0.3
                        ? const Color(0xFF00C853)
                        : const Color(0xFFFFD700);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.local_gas_station_rounded,
                                  color: barColor, size: 16),
                              const SizedBox(width: 10),
                              const Text('Est. range',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13)),
                              const Spacer(),
                              Text(
                                '~${rangeKm.toStringAsFixed(0)} km left',
                                style: TextStyle(
                                    color: barColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fuelPct,
                              backgroundColor: Colors.white10,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(barColor),
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // Group ride button (only when not riding)
                if (!_isRiding)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const GroupRideScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFE8003D).withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFFE8003D).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.group_rounded,
                                color: Color(0xFFE8003D), size: 16),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Group Ride',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                                Text('Ride with your crew on a live map',
                                    style: TextStyle(
                                        color: Colors.white30,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: Colors.white24, size: 14),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                // Speedometer button
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SpeedometerScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.speed_rounded,
                              color: Colors.white54, size: 16),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Speedometer',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text('Full-screen analogue dial',
                                  style: TextStyle(
                                      color: Colors.white30,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white24, size: 14),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Start / Stop button
                GestureDetector(
                  onTap: _isSaving
                      ? null
                      : (_isRiding ? _stopRide : _startRide),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _isSaving
                          ? const Color(0xFF1A1A1A)
                          : (_isRiding
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFE8003D)),
                      borderRadius: BorderRadius.circular(14),
                      border: _isRiding
                          ? Border.all(color: Colors.white12)
                          : null,
                      boxShadow: !_isRiding && !_isSaving
                          ? [
                              BoxShadow(
                                color:
                                    const Color(0xFFE8003D).withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white54))
                          : Text(
                              _isRiding ? 'STOP RIDE' : 'START RIDE',
                              style: TextStyle(
                                color: _isRiding
                                    ? Colors.white38
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                              ),
                            ),
                    ),
                  ),
                ),

                // Bottom padding for floating nav
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w300)),
        ],
      ),
    );
  }
}

// ── Route Planner Sheet ──────────────────────────────────────────────────────

class _RoutePlannerSheet extends StatefulWidget {
  final VoidCallback onRouteSet;
  const _RoutePlannerSheet({required this.onRouteSet});

  @override
  State<_RoutePlannerSheet> createState() => _RoutePlannerSheetState();
}

class _RoutePlannerSheetState extends State<_RoutePlannerSheet> {
  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<Waypoint?> _waypoints = [null, null];
  bool _isCalculating = false;
  String? _routeInfo;
  String? _error;
  String? _destWeather; // e.g. "⛅ 28°C · Good to ride"

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  void _addStop() {
    if (_controllers.length >= 6) return;
    setState(() {
      _controllers.insert(_controllers.length - 1, TextEditingController());
      _waypoints.insert(_waypoints.length - 1, null);
    });
  }

  void _removeStop(int index) {
    if (_controllers.length <= 2) return;
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
      _waypoints.removeAt(index);
    });
  }

  Future<void> _searchAndSet(int index) async {
    final query = _controllers[index].text.trim();
    if (query.isEmpty) return;

    setState(() => _error = null);
    final results = await RouteService.searchPlace(query);

    if (!mounted) return;
    if (results.isEmpty) {
      setState(() => _error = 'No results for "$query"');
      return;
    }
    if (results.length == 1) {
      _setWaypoint(index, results.first);
      return;
    }

    // Show picker
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            Divider(color: Colors.white.withOpacity(0.05), height: 1),
        itemBuilder: (ctx, i) => ListTile(
          leading:
              const Icon(Icons.location_on_rounded, color: Color(0xFF2979FF)),
          title: Text(results[i]['name'],
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(
            results[i]['full'].toString().split(',').take(2).join(','),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.pop(ctx);
            _setWaypoint(index, results[i]);
          },
        ),
      ),
    );
  }

  void _setWaypoint(int index, Map<String, dynamic> result) {
    setState(() {
      _controllers[index].text = result['name'];
      _waypoints[index] = Waypoint(
        label: result['name'],
        position: LatLng(result['lat'], result['lng']),
      );
    });
  }

  Future<void> _calculateRoute() async {
    final validWaypoints = _waypoints.whereType<Waypoint>().toList();
    if (validWaypoints.length < 2) {
      setState(() => _error = 'Search and select at least Start and End');
      return;
    }

    setState(() {
      _isCalculating = true;
      _error = null;
    });

    final plan = await RouteService.calculateRoute(validWaypoints);

    if (!mounted) return;
    setState(() => _isCalculating = false);

    if (plan == null) {
      setState(() => _error = 'Could not calculate route. Check your connection.');
      return;
    }

    final h = plan.durationMinutes ~/ 60;
    final m = plan.durationMinutes % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    setState(() =>
        _routeInfo = '${plan.distanceKm.toStringAsFixed(1)} km  ·  $timeStr');

    // Fetch weather at destination in background
    final dest = validWaypoints.last.position;
    final weather = await WeatherService.fetchWeather(
        dest.latitude, dest.longitude);
    if (mounted && weather != null) {
      setState(() =>
          _destWeather = '${weather.emoji} ${weather.tempC.round()}°C · ${weather.ridingCondition}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = ['Start', ...List.generate(_controllers.length - 2, (i) => 'Stop ${i + 1}'), 'End'];

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                const Text('PLAN ROUTE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w300)),
                const Spacer(),
                if (RouteService.hasRoute)
                  GestureDetector(
                    onTap: () {
                      RouteService.clearRoute();
                      widget.onRouteSet();
                      Navigator.pop(context);
                    },
                    child: const Text('Clear',
                        style: TextStyle(
                            color: Color(0xFFE8003D), fontSize: 13)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Enter addresses and tap the arrow to search',
                style: TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 20),

            // Waypoints
            ...List.generate(_controllers.length, (i) {
              final isFirst = i == 0;
              final isLast = i == _controllers.length - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    // Dot indicator
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _waypoints[i] != null
                                ? const Color(0xFF2979FF)
                                : const Color(0xFF1A1A1A),
                            border: Border.all(
                                color: _waypoints[i] != null
                                    ? const Color(0xFF2979FF)
                                    : Colors.white24),
                          ),
                          child: Center(
                            child: Text(
                              isFirst
                                  ? 'A'
                                  : isLast
                                      ? 'B'
                                      : '$i',
                              style: TextStyle(
                                  color: _waypoints[i] != null
                                      ? Colors.white
                                      : Colors.white38,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controllers[i],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: labels[i],
                          hintStyle: const TextStyle(
                              color: Colors.white24, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          suffixIcon: GestureDetector(
                            onTap: () => _searchAndSet(i),
                            child: const Icon(Icons.search_rounded,
                                color: Color(0xFF2979FF), size: 18),
                          ),
                        ),
                        onSubmitted: (_) => _searchAndSet(i),
                      ),
                    ),
                    // Remove stop button
                    if (!isFirst && !isLast && _controllers.length > 2)
                      GestureDetector(
                        onTap: () => _removeStop(i),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.remove_circle_outline_rounded,
                              color: Colors.white24, size: 18),
                        ),
                      ),
                  ],
                ),
              );
            }),

            // Add stop
            if (_controllers.length < 6)
              GestureDetector(
                onTap: _addStop,
                child: Padding(
                  padding: const EdgeInsets.only(left: 38, bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle_outline_rounded,
                          color: Color(0xFF2979FF), size: 16),
                      const SizedBox(width: 6),
                      Text('Add stop',
                          style: TextStyle(
                              color: const Color(0xFF2979FF)
                                  .withOpacity(0.8),
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFE8003D), fontSize: 12)),
              ),

            if (_routeInfo != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2979FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF2979FF).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.route_rounded,
                            color: Color(0xFF2979FF), size: 16),
                        const SizedBox(width: 8),
                        Text(_routeInfo!,
                            style: const TextStyle(
                                color: Color(0xFF2979FF), fontSize: 13)),
                      ],
                    ),
                    if (_destWeather != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Colors.white30, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Destination: $_destWeather',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ] else if (_routeInfo != null) ...[
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white24),
                          ),
                          SizedBox(width: 8),
                          Text('Fetching destination weather…',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            // Calculate / Done button
            GestureDetector(
              onTap: _isCalculating
                  ? null
                  : (_routeInfo != null
                      ? () {
                          widget.onRouteSet();
                          Navigator.pop(context);
                        }
                      : _calculateRoute),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: _isCalculating
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFF2979FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _isCalculating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54))
                      : Text(
                          _routeInfo != null
                              ? 'SHOW ON MAP'
                              : 'CALCULATE ROUTE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
