import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ride_model.dart';
import '../services/weather_service.dart';
import '../services/maintenance_service.dart';
import '../services/ride_service.dart';
import '../models/maintenance_model.dart';
import '../widgets/glass_card.dart';
import 'ride_history_screen.dart';
import 'maintenance_screen.dart';
import 'sos_screen.dart';
import 'group_ride_screen.dart';
import 'document_vault_screen.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onStartRide;
  final VoidCallback? onGoSOS;

  const DashboardScreen({super.key, this.onStartRide, this.onGoSOS});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  String _riderName = 'Rider';
  int _riderAvatar = 0;
  List<RideModel> _recentRides = [];
  double _totalKm = 0;
  double _thisWeekKm = 0;
  int _totalRides = 0;
  bool _isLoading = true;
  WeatherData? _weather;
  int _overdueCount = 0;
  int _dueSoonCount = 0;
  int _docCount = 0;
  int _docAlertCount = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  StreamSubscription<void>? _rideSub;

  final List<Map<String, dynamic>> _avatars = [
    {'emoji': '🏍️', 'color': const Color(0xFFE8003D)},
    {'emoji': '👤', 'color': const Color(0xFFFF6B00)},
    {'emoji': '🦺', 'color': const Color(0xFFFFD700)},
    {'emoji': '🎯', 'color': const Color(0xFF7C4DFF)},
    {'emoji': '🌍', 'color': const Color(0xFF00BCD4)},
    {'emoji': '🏆', 'color': const Color(0xFF607D8B)},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _rideSub = RideService.onChange.listen((_) {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final rides = await RideStorage.loadRides();
    final stats = await RideStorage.getStats();
    if (mounted) {
      setState(() {
        _riderName    = prefs.getString('rider_name') ?? 'Rider';
        _riderAvatar  = prefs.getInt('rider_avatar') ?? 0;
        _recentRides  = rides.take(3).toList();
        _totalKm      = stats['totalKm'];
        _thisWeekKm   = stats['thisWeekKm'];
        _totalRides   = stats['totalRides'];
        _isLoading    = false;
      });
    }
    _fetchWeather();
    _fetchMaintenance();
    _fetchDocs();
  }

  Future<void> _fetchMaintenance() async {
    await MaintenanceService.seedDefaults();
    final items = await MaintenanceService.loadItems();
    final odo   = await MaintenanceService.totalOdometerKm();
    if (!mounted) return;
    setState(() {
      _overdueCount = items.where((i) => i.isOverdue(odo)).length;
      _dueSoonCount = items.where((i) => !i.isOverdue(odo) && i.duePct(odo) >= 0.8).length;
    });
  }

  Future<void> _fetchDocs() async {
    final docs = await DocumentService.loadDocs();
    if (!mounted) return;
    setState(() {
      _docCount = docs.length;
      _docAlertCount =
          docs.where((d) => d.isExpired || d.isExpiringSoon).length;
    });
  }

  Future<void> _fetchWeather() async {
    try {
      final perm = await Geolocator.checkPermission();
      double lat = 3.1390, lng = 101.6869;
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      }
      final w = await WeatherService.fetchWeather(lat, lng);
      if (mounted && w != null) setState(() => _weather = w);
    } catch (_) {}
  }

  String _formatKm(double km) =>
      km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k' : km.toStringAsFixed(0);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final avatarData = _avatars[_riderAvatar.clamp(0, _avatars.length - 1)];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: const Color(0xFFE8003D),
            backgroundColor: Colors.white10,
            child: SafeArea(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [

                  // ── Header ────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                      child: Row(children: [
                        // Logo mark
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8003D),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text('MP',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('MOTOPULSE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                          Text(_greeting() + ', $_riderName',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ]),
                        const Spacer(),
                        // Avatar
                        GlassCard(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 44, height: 44,
                            alignment: Alignment.center,
                            child: Text(avatarData['emoji'] as String,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                      ]),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 6)),

                  // ── App purpose tagline ───────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8003D).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFFE8003D).withOpacity(0.3)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.motorcycle_rounded,
                                color: Color(0xFFE8003D), size: 13),
                            SizedBox(width: 5),
                            Text('Your Motorcycle Companion',
                                style: TextStyle(
                                    color: Color(0xFFE8003D),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3)),
                          ]),
                        ),
                      ]),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 20)),

                  // ── Hero START RIDE / ONGOING RIDE ───────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: GestureDetector(
                        onTap: widget.onStartRide,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: RideService.isRiding
                                ? const LinearGradient(
                                    colors: [Color(0xFF0D0D0D), Color(0xFF1A0A0A)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [Color(0xFFE8003D), Color(0xFFB5002F)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            borderRadius: BorderRadius.circular(22),
                            border: RideService.isRiding
                                ? Border.all(color: const Color(0xFFE8003D), width: 1.5)
                                : null,
                            boxShadow: RideService.isRiding
                                ? [BoxShadow(
                                    color: const Color(0xFFE8003D).withOpacity(0.3),
                                    blurRadius: 12, spreadRadius: 0)]
                                : [],
                          ),
                          child: Stack(children: [
                            Positioned(
                              right: -20, top: -20,
                              child: Opacity(
                                opacity: 0.08,
                                child: Container(
                                  width: 140, height: 140,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: RideService.isRiding
                                          ? const Color(0xFFE8003D).withOpacity(0.15)
                                          : Colors.white.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      RideService.isRiding
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.play_arrow_rounded,
                                      color: RideService.isRiding
                                          ? const Color(0xFFE8003D)
                                          : Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        RideService.isRiding ? 'ONGOING RIDE' : 'START RIDE',
                                        style: TextStyle(
                                          color: RideService.isRiding
                                              ? const Color(0xFFE8003D)
                                              : Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      Text(
                                        RideService.isRiding
                                            ? '${RideService.formattedTime}  ·  ${RideService.distanceKm.toStringAsFixed(1)} km'
                                            : 'Track your journey',
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── Stats row ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: _isLoading
                          ? Row(children: List.generate(3, (i) => Expanded(
                              child: Container(
                                margin: EdgeInsets.only(right: i < 2 ? 10 : 0),
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ))))
                          : Row(children: [
                              _statCard('TOTAL', _formatKm(_totalKm) + ' km',
                                  Icons.route_rounded, const Color(0xFFE8003D)),
                              const SizedBox(width: 10),
                              _statCard('THIS WEEK', '${_thisWeekKm.toStringAsFixed(0)} km',
                                  Icons.calendar_today_rounded, const Color(0xFFFF6B00)),
                              const SizedBox(width: 10),
                              _statCard('RIDES', '$_totalRides',
                                  Icons.motorcycle_rounded, const Color(0xFF7C4DFF)),
                            ]),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── Quick actions 2x2 grid ────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: _actionTile(
                            icon: Icons.sos_rounded,
                            label: 'SOS',
                            sublabel: 'Emergency alert',
                            color: const Color(0xFFE8003D),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const SOSScreen())),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _actionTile(
                            icon: Icons.group_rounded,
                            label: 'Group Ride',
                            sublabel: 'Ride with crew',
                            color: const Color(0xFF2979FF),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const GroupRideScreen())),
                          )),
                        ]),
                        const SizedBox(height: 10),
                        _actionTile(
                          icon: Icons.build_rounded,
                          label: 'Maintenance',
                          sublabel: _overdueCount > 0
                              ? '$_overdueCount overdue'
                              : _dueSoonCount > 0
                                  ? '$_dueSoonCount due soon'
                                  : 'All good',
                          color: _overdueCount > 0
                              ? const Color(0xFFE8003D)
                              : _dueSoonCount > 0
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF00C853),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MaintenanceScreen()))
                              .then((_) => _fetchMaintenance()),
                        ),
                        const SizedBox(height: 10),
                        // Documents — full-width tile
                        Row(children: [
                          Expanded(child: _actionTile(
                            icon: Icons.folder_special_rounded,
                            label: 'Documents',
                            sublabel: _docAlertCount > 0
                                ? '$_docAlertCount need attention'
                                : _docCount > 0
                                    ? '$_docCount stored · All good'
                                    : 'Insurance, reg & more',
                            color: _docAlertCount > 0
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF00BCD4),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const DocumentVaultScreen()))
                                .then((_) => _fetchDocs()),
                          )),
                        ]),
                      ]),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // ── Weather detail card ───────────────────────────────────
                  if (_weather != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: GlassCard(
                          padding: const EdgeInsets.all(18),
                          child: Row(children: [
                            Text(_weather!.emoji,
                                style: const TextStyle(fontSize: 34)),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('RIDING CONDITIONS',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                        letterSpacing: 2)),
                                const SizedBox(height: 4),
                                Text(_weather!.ridingCondition,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w300)),
                              ],
                            )),
                            Column(children: [
                              Text('${_weather!.tempC.toStringAsFixed(0)}°',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w200)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (_weather!.isGoodForRiding
                                          ? const Color(0xFF00C853)
                                          : const Color(0xFFFFD700))
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(_weather!.badge,
                                    style: TextStyle(
                                        color: _weather!.isGoodForRiding
                                            ? const Color(0xFF00C853)
                                            : const Color(0xFFFFD700),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5)),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── Recent rides header ───────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(children: [
                        const Text('RECENT RIDES',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                letterSpacing: 2.5,
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        if (_totalRides > 0)
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => const RideHistoryScreen())),
                            child: const Text('View all →',
                                style: TextStyle(
                                    color: Color(0xFFE8003D),
                                    fontSize: 12)),
                          ),
                      ]),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // ── Rides list ────────────────────────────────────────────
                  _recentRides.isEmpty && !_isLoading
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: GlassCard(
                              padding: const EdgeInsets.all(32),
                              child: Column(children: const [
                                Icon(Icons.motorcycle_rounded,
                                    color: Colors.white24, size: 40),
                                SizedBox(height: 12),
                                Text('No rides yet',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 14)),
                                SizedBox(height: 4),
                                Text('Tap START RIDE to log your first ride',
                                    style: TextStyle(
                                        color: Colors.white24, fontSize: 12)),
                              ]),
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => Padding(
                              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                              child: _rideCard(_recentRides[i]),
                            ),
                            childCount: _recentRides.length,
                          ),
                        ),

                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 9, letterSpacing: 1.5)),
        ]),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text(sublabel,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        )),
      ]),
    );
  }

  Widget _rideCard(RideModel ride) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8003D).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.motorcycle_rounded,
              color: Color(0xFFE8003D), size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ride.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text(
              '${ride.distanceKm.toStringAsFixed(2)} km  ·  ${ride.formattedDuration}  ·  ${ride.avgSpeedKmh.toStringAsFixed(0)} km/h avg',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        )),
        Text(ride.relativeDate,
            style: const TextStyle(color: Colors.white24, fontSize: 11)),
      ]),
    );
  }
}
