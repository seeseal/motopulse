import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride_model.dart';
import '../services/route_service.dart';
import '../services/profile_service.dart';
import '../services/weather_service.dart';
import '../services/ride_service.dart';
import '../services/crash_detector.dart';
import '../widgets/crash_alert_overlay.dart';
import '../widgets/glass_card.dart';
import '../services/battery_guard.dart';
import 'battery_gate_screen.dart';
import 'group_ride_screen.dart';

const String _kDarkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#141414"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#6b6b6b"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#141414"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2a2a2a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#383838"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3d3d3d"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#888888"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]}
]''';

/// Convert latlong2.LatLng → gmaps.LatLng
gmaps.LatLng _gl(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

/// Render a Material icon into a [gmaps.BitmapDescriptor] at [sizePx].
Future<gmaps.BitmapDescriptor> _iconToBitmap(
    IconData icon, Color bg, double sizePx) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final r = sizePx / 2;

  // Circle background
  canvas.drawCircle(
    ui.Offset(r, r),
    r,
    ui.Paint()..color = bg,
  );

  // Icon glyph
  final tp = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: sizePx * 0.55,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    )
    ..layout();
  tp.paint(canvas, ui.Offset((sizePx - tp.width) / 2, (sizePx - tp.height) / 2));

  final picture = recorder.endRecording();
  final img = await picture.toImage(sizePx.toInt(), sizePx.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return gmaps.BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
}

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({super.key});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen>
    with SingleTickerProviderStateMixin {
  // Map
  gmaps.GoogleMapController? _mapController;
  LatLng _currentLatLng = const LatLng(3.1390, 101.6869);
  LatLng _displayLatLng = const LatLng(3.1390, 101.6869); // smoothed position
  bool _locationReady = false;
  bool _trafficEnabled = false;
  bool _headingUp = true; // navigation (heading-up) vs north-up
  gmaps.BitmapDescriptor? _bikeMarker;
  LatLng? _rideStartPos;
  Timer? _interpTimer;

  // Profile-driven settings
  double _speedLimitKmh = 100.0;
  double _fuelTankL = 15.0;
  double _fuelEfficiencyKmL = 30.0;
  bool _speedAlertActive = false;
  bool _speedAlertShownOnce = false;

  // Pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // RideService listener
  StreamSubscription<void>? _rideServiceSub;
  StreamSubscription<void>? _crashSub;

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
    ProfileService.load().then((p) {
      if (mounted) setState(() {
        _speedLimitKmh = p.speedLimitKmh;
        _fuelTankL = p.fuelTankL;
        _fuelEfficiencyKmL = p.fuelEfficiencyKmL;
      });
    });
    _iconToBitmap(Icons.two_wheeler_rounded, const Color(0xFFE8003D), 56)
        .then((bmp) { if (mounted) setState(() => _bikeMarker = bmp); });

    // Smooth marker interpolation at 20 fps
    _interpTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !RideService.isRiding) return;
      final target = _currentLatLng;
      final curr = _displayLatLng;
      const alpha = 0.25;
      final lat = curr.latitude + (target.latitude - curr.latitude) * alpha;
      final lng = curr.longitude + (target.longitude - curr.longitude) * alpha;
      if ((lat - curr.latitude).abs() > 1e-7 ||
          (lng - curr.longitude).abs() > 1e-7) {
        setState(() => _displayLatLng = LatLng(lat, lng));
      }
    });
    _crashSub = CrashDetector.onCrashDetected.listen((_) {
      if (!mounted) return;
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => const CrashAlertOverlay(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ));
    });
    _rideServiceSub = RideService.onChange.listen((_) {
      if (!mounted) return;
      final pts = RideService.routePoints;
      if (pts.isNotEmpty) {
        _currentLatLng = pts.last;
        if (RideService.isRiding) _updateCamera();
      }
      final overLimit = RideService.speedKmh > _speedLimitKmh;
      if (overLimit && !_speedAlertShownOnce) {
        HapticFeedback.heavyImpact();
        _speedAlertShownOnce = true;
      }
      if (!overLimit) _speedAlertShownOnce = false;
      _speedAlertActive = overLimit;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initLocation();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rideServiceSub?.cancel();
    _crashSub?.cancel();
    _interpTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentLatLng = ll;
          _locationReady = true;
        });
        _mapController?.animateCamera(
          gmaps.CameraUpdate.newCameraPosition(
            gmaps.CameraPosition(target: _gl(ll), zoom: 15),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _locationReady = true);
    }
  }

  // ── Navigation camera ──────────────────────────────────────────────────────

  double _speedToZoom(double kmh) {
    if (kmh < 10) return 17.5;
    if (kmh < 30) return 17.0;
    if (kmh < 60) return 16.0;
    if (kmh < 100) return 15.5;
    return 15.0;
  }

  void _updateCamera() {
    if (_mapController == null) return;
    if (_headingUp) {
      _mapController!.animateCamera(
        gmaps.CameraUpdate.newCameraPosition(
          gmaps.CameraPosition(
            target: _gl(_currentLatLng),
            zoom: _speedToZoom(RideService.speedKmh),
            bearing: RideService.bearing,
            tilt: 45.0,
          ),
        ),
      );
    } else {
      _mapController!.animateCamera(
        gmaps.CameraUpdate.newLatLng(_gl(_currentLatLng)),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

  void _startRide() async {
    // Battery gate — must be exempted from Android battery optimisation or
    // the foreground GPS service will be killed mid-ride on most OEM ROMs.
    final exempted = await BatteryGuard.isExempted();
    if (!exempted) {
      if (!mounted) return;
      final granted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const BatteryGateScreen()),
      );
      if (granted != true) return; // user did not grant — abort
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Please enable location services.');
      return;
    }
    setState(() {
      _rideStartPos = _currentLatLng;
      _displayLatLng = _currentLatLng;
    });
    RideService.startRide(initialPos: _locationReady ? _currentLatLng : null);
  }

  Future<void> _stopRide() async {
    setState(() => _rideStartPos = null);
    final ride = await RideService.stopRide();
    if (!mounted) return;
    if (ride == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride too short to save'),
          backgroundColor: Color(0xFF1A1A1A),
        ),
      );
    } else {
      _showRideSummary(ride);
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _showRoutePlanner() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoutePlannerSheet(onRouteSet: () => setState(() {})),
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('RIDE COMPLETE',
                style: TextStyle(color: Color(0xFFE8003D), fontSize: 11, letterSpacing: 3)),
            const SizedBox(height: 6),
            Text(ride.title,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300)),
            const SizedBox(height: 24),
            Row(children: [
              _summaryTile('DISTANCE', '${ride.distanceKm.toStringAsFixed(2)} km'),
              _summaryTile('DURATION', ride.formattedDuration),
              _summaryTile('TOP SPEED', '${ride.maxSpeedKmh.toStringAsFixed(0)} km/h'),
            ]),
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
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 3)),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Set<gmaps.Polyline> _buildPolylines() {
    final result = <gmaps.Polyline>{};
    if (RouteService.hasRoute && RouteService.activePlan!.routePoints.length > 1) {
      result.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('planned'),
        points: RouteService.activePlan!.routePoints.map(_gl).toList(),
        color: const Color(0x882979FF),
        width: 5,
        patterns: [gmaps.PatternItem.dash(12), gmaps.PatternItem.gap(6)],
      ));
    }
    // Prefer road-snapped route; fall back to raw GPS
    final ridePoints = RideService.snappedRoutePoints.length > 1
        ? RideService.snappedRoutePoints
        : RideService.routePoints;
    if (ridePoints.length > 1) {
      result.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('ridden'),
        points: ridePoints.map(_gl).toList(),
        color: const Color(0xFFE8003D),
        width: 5,
      ));
    }
    return result;
  }

  Set<gmaps.Marker> _buildMarkers() {
    final result = <gmaps.Marker>{};

    // Red start pin — shown at the ride's origin while riding
    if (RideService.isRiding && _rideStartPos != null) {
      result.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('start'),
        position: _gl(_rideStartPos!),
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1.0),
        infoWindow: const gmaps.InfoWindow(title: 'Ride Start'),
      ));
    }

    // Current position: bike icon (smoothed + rotated) when riding, red pin idle
    result.add(gmaps.Marker(
      markerId: const gmaps.MarkerId('me'),
      position: _gl(RideService.isRiding ? _displayLatLng : _currentLatLng),
      icon: RideService.isRiding && _bikeMarker != null
          ? _bikeMarker!
          : gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueRed),
      anchor: const Offset(0.5, 0.5),
      flat: RideService.isRiding,
      rotation: RideService.isRiding ? RideService.bearing : 0.0,
    ));

    // Waypoint markers
    if (RouteService.hasRoute) {
      final wpts = RouteService.activePlan!.waypoints;
      for (var i = 0; i < wpts.length; i++) {
        final label = i == 0 ? 'A' : i == wpts.length - 1 ? 'B' : '$i';
        result.add(gmaps.Marker(
          markerId: gmaps.MarkerId('wp_$i'),
          position: _gl(wpts[i].position),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueAzure),
          infoWindow: gmaps.InfoWindow(title: label, snippet: wpts[i].label),
          anchor: const Offset(0.5, 1.0),
        ));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: Column(children: [
          // ── Map ───────────────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(children: [
              gmaps.GoogleMap(
                onMapCreated: (ctrl) {
                  _mapController = ctrl;
                  ctrl.setMapStyle(_kDarkMapStyle);
                  if (_locationReady) {
                    ctrl.animateCamera(gmaps.CameraUpdate.newCameraPosition(
                      gmaps.CameraPosition(target: _gl(_currentLatLng), zoom: 15),
                    ));
                  }
                },
                initialCameraPosition: gmaps.CameraPosition(
                  target: _gl(_currentLatLng),
                  zoom: 15,
                ),
                polylines: _buildPolylines(),
                markers: _buildMarkers(),
                trafficEnabled: _trafficEnabled,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
              ),

              // Header overlay
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    const Text('TRACKING',
                        style: TextStyle(
                            color: Colors.white, fontSize: 13,
                            letterSpacing: 4, fontWeight: FontWeight.w300)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _showRoutePlanner,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        child: Row(children: [
                          Icon(Icons.route_rounded, size: 13,
                              color: RouteService.hasRoute
                                  ? const Color(0xFF2979FF) : Colors.white38),
                          const SizedBox(width: 5),
                          Text(
                            RouteService.hasRoute ? 'ROUTE SET' : 'PLAN ROUTE',
                            style: TextStyle(
                              color: RouteService.hasRoute
                                  ? const Color(0xFF2979FF) : Colors.white30,
                              fontSize: 10, letterSpacing: 1.5,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: RideService.isRiding
                              ? Colors.green.withOpacity(0.5) : Colors.white12,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: RideService.isRiding ? Colors.green : Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          RideService.isRiding ? 'LIVE' : 'IDLE',
                          style: TextStyle(
                            color: RideService.isRiding ? Colors.green : Colors.white30,
                            fontSize: 10, letterSpacing: 2,
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),

              // Heading-up / North-up toggle
              Positioned(
                right: 16, bottom: 112,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _headingUp = !_headingUp);
                    if (!_headingUp) {
                      // Reset to north-up flat view
                      _mapController?.animateCamera(
                        gmaps.CameraUpdate.newCameraPosition(
                          gmaps.CameraPosition(
                            target: _gl(_currentLatLng),
                            zoom: _speedToZoom(RideService.speedKmh),
                            bearing: 0,
                            tilt: 0,
                          ),
                        ),
                      );
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _headingUp
                          ? const Color(0xFF2979FF).withOpacity(0.9)
                          : const Color(0xFF111111).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _headingUp
                            ? const Color(0xFF2979FF).withOpacity(0.5)
                            : Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Icon(
                      _headingUp
                          ? Icons.navigation_rounded
                          : Icons.explore_rounded,
                      color: _headingUp ? Colors.white : Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
              ),

              // Traffic toggle button
              Positioned(
                right: 16, bottom: 64,
                child: GestureDetector(
                  onTap: () => setState(() => _trafficEnabled = !_trafficEnabled),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _trafficEnabled
                          ? const Color(0xFFE8003D).withOpacity(0.9)
                          : const Color(0xFF111111).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _trafficEnabled
                            ? const Color(0xFFE8003D).withOpacity(0.5)
                            : Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Icon(Icons.traffic_rounded,
                        color: _trafficEnabled ? Colors.white : Colors.white54,
                        size: 18),
                  ),
                ),
              ),

              // Re-center button
              Positioned(
                right: 16, bottom: 16,
                child: GestureDetector(
                  onTap: () => _mapController?.animateCamera(
                    gmaps.CameraUpdate.newLatLng(_gl(_currentLatLng)),
                  ),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Icon(Icons.my_location_rounded,
                        color: Colors.white54, size: 18),
                  ),
                ),
              ),
            ]),
          ),

          // ── Speed alert banner ────────────────────────────────────────────
          if (_speedAlertActive)
            Container(
              color: const Color(0xFFE8003D).withOpacity(0.92),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'SPEED ALERT  ·  ${RideService.speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700,
                      fontSize: 13, letterSpacing: 1),
                ),
                const Spacer(),
                Text('limit ${_speedLimitKmh.round()} km/h',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            ),

          // ── Stats panel ───────────────────────────────────────────────────
          ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                color: Colors.black.withOpacity(0.55),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        flex: 2,
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('SPEED',
                                style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
                            const SizedBox(height: 2),
                            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(
                                RideService.speedKmh.toStringAsFixed(0),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 40,
                                    fontWeight: FontWeight.w200, height: 1),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4, left: 4),
                                child: Text('km/h',
                                    style: TextStyle(color: Colors.white30, fontSize: 11)),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Column(children: [
                          _statTile('DISTANCE',
                              '${RideService.distanceKm.toStringAsFixed(2)} km'),
                          const SizedBox(height: 10),
                          _statTile('DURATION', RideService.formattedTime),
                        ]),
                      ),
                    ]),

                    const SizedBox(height: 10),

                    if (RideService.isRiding)
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        borderRadius: BorderRadius.circular(14),
                        child: Row(children: [
                          const Icon(Icons.speed_rounded, color: Colors.white24, size: 16),
                          const SizedBox(width: 10),
                          const Text('Max speed',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const Spacer(),
                          Text('${RideService.maxSpeedKmh.toStringAsFixed(0)} km/h',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ),

                    if (RideService.isRiding && _fuelEfficiencyKmL > 0) ...[
                      const SizedBox(height: 10),
                      Builder(builder: (_) {
                        final fuelPct = _fuelTankL > 0
                            ? ((_fuelTankL -
                                        RideService.distanceKm / _fuelEfficiencyKmL) /
                                    _fuelTankL)
                                .clamp(0.0, 1.0)
                            : 1.0;
                        final rangeKm =
                            (fuelPct * _fuelTankL * _fuelEfficiencyKmL).clamp(0.0, 9999.0);
                        final barColor =
                            fuelPct > 0.3 ? const Color(0xFF00C853) : const Color(0xFFFFD700);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(children: [
                            Row(children: [
                              Icon(Icons.local_gas_station_rounded,
                                  color: barColor, size: 16),
                              const SizedBox(width: 10),
                              const Text('Est. range',
                                  style: TextStyle(color: Colors.white38, fontSize: 13)),
                              const Spacer(),
                              Text('~${rangeKm.toStringAsFixed(0)} km left',
                                  style: TextStyle(
                                      color: barColor, fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ]),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fuelPct,
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                minHeight: 3,
                              ),
                            ),
                          ]),
                        );
                      }),
                    ],

                    if (!RideService.isRiding)
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const GroupRideScreen())),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFFE8003D).withOpacity(0.2)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8003D).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.group_rounded,
                                  color: Color(0xFFE8003D), size: 16),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Group Ride',
                                        style: TextStyle(color: Colors.white, fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    Text('Ride with your crew on a live map',
                                        style: TextStyle(color: Colors.white30, fontSize: 11)),
                                  ]),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white24, size: 14),
                          ]),
                        ),
                      ),


                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: RideService.isSaving
                          ? null
                          : (RideService.isRiding ? _stopRide : _startRide),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        height: RideService.isRiding ? 68 : 54,
                        decoration: BoxDecoration(
                          color: RideService.isSaving
                              ? const Color(0xFF1A1A1A)
                              : (RideService.isRiding
                                  ? const Color(0xFF0D0D0D)
                                  : const Color(0xFFE8003D)),
                          borderRadius: BorderRadius.circular(14),
                          border: RideService.isRiding
                              ? Border.all(
                                  color: const Color(0xFFE8003D).withOpacity(0.5),
                                  width: 1.5)
                              : null,
                          boxShadow: RideService.isRiding
                              ? [BoxShadow(
                                  color: const Color(0xFFE8003D).withOpacity(0.15),
                                  blurRadius: 12, spreadRadius: 1)]
                              : (!RideService.isSaving
                                  ? [BoxShadow(
                                      color: const Color(0xFFE8003D).withOpacity(0.35),
                                      blurRadius: 16, offset: const Offset(0, 6))]
                                  : null),
                        ),
                        child: RideService.isSaving
                            ? const Center(
                                child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5, color: Colors.white38),
                                ))
                            : RideService.isRiding
                                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Container(
                                        width: 7, height: 7,
                                        decoration: const BoxDecoration(
                                            color: Color(0xFFE8003D), shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(RideService.formattedTime,
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 22,
                                              fontWeight: FontWeight.w200, letterSpacing: 2)),
                                      const SizedBox(width: 16),
                                      Text('${RideService.distanceKm.toStringAsFixed(2)} km',
                                          style: const TextStyle(
                                              color: Colors.white38, fontSize: 13,
                                              fontWeight: FontWeight.w400)),
                                    ]),
                                    const SizedBox(height: 4),
                                    const Text('TAP TO STOP',
                                        style: TextStyle(
                                            color: Color(0xFFE8003D), fontSize: 9,
                                            letterSpacing: 3, fontWeight: FontWeight.w700)),
                                  ])
                                : const Center(
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('START RIDE',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 14,
                                              fontWeight: FontWeight.w700, letterSpacing: 3)),
                                      SizedBox(width: 10),
                                      Icon(Icons.arrow_forward_rounded,
                                          color: Colors.white, size: 16),
                                    ]),
                                  ),
                      ),
                    ),

                    const SizedBox(height: 82),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300)),
        ]),
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
  bool _avoidTolls = false;
  bool _avoidHighways = false;
  String? _routeInfo;
  String? _error;
  String? _destWeather;
  List<SegmentInfo> _segments = [];
  List<SavedRoute> _savedRoutes = [];
  bool _showSaved = false;

  // Live autocomplete state
  int? _activeFieldIdx;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final routes = await RouteService.loadSavedRoutes();
    if (mounted) setState(() => _savedRoutes = routes);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  // Called on every keystroke — debounced 400 ms
  void _onFieldChanged(int index, String value) {
    // Clear the confirmed waypoint when the user edits the field
    if (_waypoints[index] != null) {
      setState(() => _waypoints[index] = null);
    }
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _suggestions = [];
        _activeFieldIdx = null;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _activeFieldIdx = index;
      _isSearching = true;
      _suggestions = [];
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await RouteService.searchPlace(q);
      if (mounted && _activeFieldIdx == index) {
        setState(() {
          _suggestions = results;
          _isSearching = false;
        });
      }
    });
  }

  // Tap on an autocomplete suggestion → fetch Place Details → set waypoint
  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    final idx = _activeFieldIdx;
    if (idx == null) return;
    // Show the chosen name immediately
    _controllers[idx].text = suggestion['name'] as String;
    setState(() {
      _suggestions = [];
      _isSearching = false;
      _activeFieldIdx = null;
      _error = null;
    });
    final details =
        await RouteService.getPlaceDetails(suggestion['place_id'] as String);
    if (!mounted) return;
    if (details == null) {
      setState(() => _error = 'Could not get location details. Try again.');
      return;
    }
    _setWaypoint(idx, details);
  }

  // Manual search trigger (search icon tap) — fetches suggestions immediately
  Future<void> _searchAndSet(int index) async {
    final query = _controllers[index].text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _activeFieldIdx = index;
      _isSearching = true;
      _suggestions = [];
    });
    final results = await RouteService.searchPlace(query);
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _suggestions = results;
    });
    if (results.isEmpty) {
      setState(() => _error = 'No results for "$query"');
    }
  }

  void _setWaypoint(int index, Map<String, dynamic> result) {
    setState(() {
      _controllers[index].text = result['name'] as String;
      _waypoints[index] = Waypoint(
        label: result['name'] as String,
        position: LatLng(
          (result['lat'] as num).toDouble(),
          (result['lng'] as num).toDouble(),
        ),
      );
    });
  }

  Future<void> _calculateRoute() async {
    final valid = _waypoints.whereType<Waypoint>().toList();
    if (valid.length < 2) {
      setState(() => _error = 'Search and select at least Start and End');
      return;
    }
    setState(() { _isCalculating = true; _error = null; });
    final plan = await RouteService.calculateRoute(
      valid,
      avoidTolls: _avoidTolls,
      avoidHighways: _avoidHighways,
    );
    if (!mounted) return;
    setState(() => _isCalculating = false);
    if (plan == null) {
      setState(() => _error = 'Could not calculate route. Check connection.');
      return;
    }
    final h = plan.durationMinutes ~/ 60;
    final m = plan.durationMinutes % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    setState(() {
      _routeInfo = '${plan.distanceKm.toStringAsFixed(1)} km  ·  $timeStr';
      _segments = plan.segments;
    });
    // Weather at destination
    final dest = valid.last.position;
    final weather = await WeatherService.fetchWeather(dest.latitude, dest.longitude);
    if (mounted && weather != null) {
      setState(() => _destWeather =
          '${weather.emoji} ${weather.tempC.round()}°C · ${weather.ridingCondition}');
    }
  }

  Future<void> _saveCurrentRoute() async {
    final valid = _waypoints.whereType<Waypoint>().toList();
    if (RouteService.activePlan == null || valid.length < 2) return;
    final plan = RouteService.activePlan!;
    final name = valid.map((w) => w.label.split(',').first).take(2).join(' → ');
    final route = SavedRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      waypoints: valid,
      distanceKm: plan.distanceKm,
      durationMinutes: plan.durationMinutes,
      savedAt: DateTime.now(),
    );
    await RouteService.saveRoute(route);
    await _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route saved'),
          backgroundColor: Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _loadSavedRoute(SavedRoute route) {
    // Clear existing waypoints
    for (final c in _controllers) c.dispose();
    _controllers.clear();
    _waypoints.clear();
    for (final w in route.waypoints) {
      _controllers.add(TextEditingController(text: w.label));
      _waypoints.add(w);
    }
    setState(() { _showSaved = false; _routeInfo = null; _segments = []; });
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Start',
      ...List.generate(_controllers.length - 2, (i) => 'Stop ${i + 1}'),
      'End',
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white12, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              const Text('PLAN ROUTE',
                  style: TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w300)),
              const Spacer(),
              // Saved toggle
              GestureDetector(
                onTap: () => setState(() => _showSaved = !_showSaved),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _showSaved
                        ? const Color(0xFF2979FF).withOpacity(0.15)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _showSaved
                            ? const Color(0xFF2979FF).withOpacity(0.4)
                            : Colors.white12),
                  ),
                  child: Row(children: [
                    Icon(Icons.bookmark_rounded,
                        size: 13,
                        color: _showSaved ? const Color(0xFF2979FF) : Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      'Saved${_savedRoutes.isNotEmpty ? ' (${_savedRoutes.length})' : ''}',
                      style: TextStyle(
                          color: _showSaved ? const Color(0xFF2979FF) : Colors.white30,
                          fontSize: 11),
                    ),
                  ]),
                ),
              ),
              if (RouteService.hasRoute) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    RouteService.clearRoute();
                    widget.onRouteSet();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear',
                      style: TextStyle(color: Color(0xFFE8003D), fontSize: 13)),
                ),
              ],
            ]),

            // Saved routes panel
            if (_showSaved) ...[
              const SizedBox(height: 16),
              if (_savedRoutes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No saved routes yet',
                      style: TextStyle(color: Colors.white30, fontSize: 13)),
                )
              else
                ..._savedRoutes.map((r) => Dismissible(
                  key: Key(r.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) async {
                    await RouteService.deleteSavedRoute(r.id);
                    await _loadSaved();
                  },
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    child: const Icon(Icons.delete_outline,
                        color: Color(0xFFE8003D), size: 18),
                  ),
                  child: GestureDetector(
                    onTap: () => _loadSavedRoute(r),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.route_rounded,
                            color: Color(0xFF2979FF), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${r.distanceKm.toStringAsFixed(1)} km  ·  '
                                  '${r.durationMinutes < 60 ? '${r.durationMinutes}m' : '${r.durationMinutes ~/ 60}h ${r.durationMinutes % 60}m'}',
                                  style: const TextStyle(
                                      color: Colors.white30, fontSize: 11),
                                ),
                              ]),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            color: Colors.white24, size: 12),
                      ]),
                    ),
                  ),
                )),
              const Divider(color: Colors.white12, height: 24),
            ],

            const SizedBox(height: 4),
            const Text('Type a place name — suggestions appear instantly',
                style: TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 16),

            // Waypoints (reorderable)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _controllers.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final ctrl = _controllers.removeAt(oldIndex);
                  _controllers.insert(newIndex, ctrl);
                  final wp = _waypoints.removeAt(oldIndex);
                  _waypoints.insert(newIndex, wp);
                });
              },
              itemBuilder: (_, i) {
                final isFirst = i == 0;
                final isLast = i == _controllers.length - 1;
                return Padding(
                  key: ValueKey('wp_$i'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _waypoints[i] != null
                            ? const Color(0xFF2979FF) : const Color(0xFF1A1A1A),
                        border: Border.all(
                            color: _waypoints[i] != null
                                ? const Color(0xFF2979FF) : Colors.white24),
                      ),
                      child: Center(
                        child: Text(
                          isFirst ? 'A' : isLast ? 'B' : '$i',
                          style: TextStyle(
                              color: _waypoints[i] != null ? Colors.white : Colors.white38,
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controllers[i],
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: labels[i],
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                          filled: true,
                          fillColor: _activeFieldIdx == i
                              ? const Color(0xFF222222)
                              : const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: const Color(0xFF2979FF).withOpacity(0.4)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          suffixIcon: _isSearching && _activeFieldIdx == i
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF2979FF)),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: () => _searchAndSet(i),
                                  child: Icon(
                                    _waypoints[i] != null
                                        ? Icons.check_circle_rounded
                                        : Icons.search_rounded,
                                    color: _waypoints[i] != null
                                        ? const Color(0xFF00C853)
                                        : const Color(0xFF2979FF),
                                    size: 18,
                                  ),
                                ),
                        ),
                        onChanged: (v) => _onFieldChanged(i, v),
                        onSubmitted: (_) => _searchAndSet(i),
                      ),
                    ),
                    if (!isFirst && !isLast && _controllers.length > 2)
                      GestureDetector(
                        onTap: () => _removeStop(i),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.remove_circle_outline_rounded,
                              color: Colors.white24, size: 18),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(Icons.drag_handle_rounded,
                        color: Colors.white12, size: 18),
                  ]),
                );
              },
            ),

            // ── Autocomplete suggestions panel ──────────────────────────────
            if (_isSearching && _suggestions.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF2979FF)),
                  ),
                ),
              )
            else if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2979FF).withOpacity(0.25)),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: _suggestions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final s = entry.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (idx > 0)
                          Divider(
                              color: Colors.white.withOpacity(0.05), height: 1),
                        InkWell(
                          onTap: () => _selectSuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            child: Row(children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF2979FF).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.location_on_rounded,
                                    color: Color(0xFF2979FF), size: 16),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s['name'] as String,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      s['full'] as String,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.north_west_rounded,
                                  color: Colors.white24, size: 14),
                            ]),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

            // Add stop
            if (_controllers.length < 6)
              GestureDetector(
                onTap: _addStop,
                child: Padding(
                  padding: const EdgeInsets.only(left: 38, bottom: 12),
                  child: Row(children: [
                    const Icon(Icons.add_circle_outline_rounded,
                        color: Color(0xFF2979FF), size: 16),
                    const SizedBox(width: 6),
                    Text('Add stop',
                        style: TextStyle(
                            color: const Color(0xFF2979FF).withOpacity(0.8),
                            fontSize: 13)),
                  ]),
                ),
              ),

            // Avoid options
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.tune_rounded, color: Colors.white24, size: 16),
                const SizedBox(width: 10),
                const Text('Avoid tolls',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: _avoidTolls,
                    onChanged: (v) => setState(() => _avoidTolls = v),
                    activeColor: const Color(0xFF2979FF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Highways',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: _avoidHighways,
                    onChanged: (v) => setState(() => _avoidHighways = v),
                    activeColor: const Color(0xFF2979FF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ]),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFE8003D), fontSize: 12)),
              ),

            // Route result card
            if (_routeInfo != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2979FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2979FF).withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.route_rounded, color: Color(0xFF2979FF), size: 16),
                    const SizedBox(width: 8),
                    Text(_routeInfo!,
                        style: const TextStyle(color: Color(0xFF2979FF), fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _saveCurrentRoute,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2979FF).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(children: [
                          Icon(Icons.bookmark_add_rounded,
                              color: Color(0xFF2979FF), size: 12),
                          SizedBox(width: 4),
                          Text('Save', style: TextStyle(color: Color(0xFF2979FF), fontSize: 11)),
                        ]),
                      ),
                    ),
                  ]),

                  // Per-segment breakdown
                  if (_segments.length > 1) ...[
                    const SizedBox(height: 10),
                    ..._segments.asMap().entries.map((e) {
                      final seg = e.value;
                      final h = seg.durationMinutes ~/ 60;
                      final m = seg.durationMinutes % 60;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2979FF).withOpacity(0.2),
                            ),
                            child: Center(
                              child: Text('${e.key + 1}',
                                  style: const TextStyle(
                                      color: Color(0xFF2979FF), fontSize: 9,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${seg.fromLabel.split(',').first} → ${seg.toLabel.split(',').first}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${seg.distanceKm.toStringAsFixed(1)} km  '
                            '${h > 0 ? '${h}h ' : ''}${m}m',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ]),
                      );
                    }),
                  ],

                  if (_destWeather != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: Colors.white30, size: 14),
                      const SizedBox(width: 6),
                      Text('Destination: $_destWeather',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ]),
                  ] else ...[
                    const SizedBox(height: 6),
                    const Row(children: [
                      SizedBox(
                        width: 10, height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white24),
                      ),
                      SizedBox(width: 8),
                      Text('Fetching destination weather…',
                          style: TextStyle(color: Colors.white24, fontSize: 11)),
                    ]),
                  ],
                ]),
              ),

            // Action button
            GestureDetector(
              onTap: _isCalculating
                  ? null
                  : (_routeInfo != null
                      ? () { widget.onRouteSet(); Navigator.pop(context); }
                      : _calculateRoute),
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: _isCalculating
                      ? const Color(0xFF1A1A1A) : const Color(0xFF2979FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _isCalculating
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white54))
                      : Text(
                          _routeInfo != null ? 'SHOW ON MAP' : 'CALCULATE ROUTE',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700,
                              letterSpacing: 2, fontSize: 12),
                        ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
