import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ride_model.dart';
import '../services/weather_service.dart';
import '../services/maintenance_service.dart';
import '../models/maintenance_model.dart';
import 'ride_history_screen.dart';
import 'maintenance_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onStartRide;

  const DashboardScreen({super.key, this.onStartRide});

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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _avatars = [
    {'emoji': '🏍️', 'color': const Color(0xFFE8003D)},
    {'emoji': '🔥', 'color': const Color(0xFFFF6B00)},
    {'emoji': '⚡', 'color': const Color(0xFFFFD700)},
    {'emoji': '🐺', 'color': const Color(0xFF7C4DFF)},
    {'emoji': '🦅', 'color': const Color(0xFF00BCD4)},
    {'emoji': '💀', 'color': const Color(0xFF607D8B)},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final rides = await RideStorage.loadRides();
    final stats = await RideStorage.getStats();

    if (mounted) {
      setState(() {
        _riderName = prefs.getString('rider_name') ?? 'Rider';
        _riderAvatar = prefs.getInt('rider_avatar') ?? 0;
        _recentRides = rides.take(3).toList();
        _totalKm = stats['totalKm'];
        _thisWeekKm = stats['thisWeekKm'];
        _totalRides = stats['totalRides'];
        _isLoading = false;
      });
    }

    // Fetch weather & maintenance in background
    _fetchWeather();
    _fetchMaintenance();
  }

  Future<void> _fetchMaintenance() async {
    await MaintenanceService.seedDefaults();
    final items = await MaintenanceService.loadItems();
    final odo   = await MaintenanceService.totalOdometerKm();
    if (!mounted) return;
    setState(() {
      _overdueCount  = items.where((i) => i.isOverdue(odo)).length;
      _dueSoonCount  = items.where((i) => !i.isOverdue(odo) && i.duePct(odo) >= 0.8).length;
    });
  }

  Future<void> _fetchWeather() async {
    try {
      final perm = await Geolocator.checkPermission();
      double lat = 28.6139; // default: New Delhi
      double lng = 77.2090;
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      }
      final weather = await WeatherService.fetchWeather(lat, lng);
      if (mounted && weather != null) setState(() => _weather = weather);
    } catch (_) {}
  }

  String _formatKm(double km) {
    if (km >= 1000) {
      return '${(km / 1000).toStringAsFixed(1)}k';
    }
    return km.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final avatarData = _avatars[_riderAvatar];

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFFE8003D),
          backgroundColor: const Color(0xFF1A1A1A),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _riderName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: (avatarData['color'] as Color)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: avatarData['color'] as Color,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              avatarData['emoji'] as String,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 28)),

                // Quick Stats Row
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _isLoading
                        ? _shimmerRow()
                        : Row(
                            children: [
                              _statCard(
                                  'TOTAL KM',
                                  _formatKm(_totalKm),
                                  Icons.route_rounded,
                                  const Color(0xFFE8003D)),
                              const SizedBox(width: 12),
                              _statCard(
                                  'THIS WEEK',
                                  '${_thisWeekKm.toStringAsFixed(0)} km',
                                  Icons.calendar_today_rounded,
                                  const Color(0xFFFF6B00)),
                              const SizedBox(width: 12),
                              _statCard(
                                  'RIDES',
                                  '$_totalRides',
                                  Icons.motorcycle_rounded,
                                  const Color(0xFF7C4DFF)),
                            ],
                          ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Start Ride Button
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      onTap: widget.onStartRide,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE8003D), Color(0xFFFF6B00)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFFE8003D).withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Text(
                              'START RIDE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // Weather card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildWeatherCard(),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Maintenance Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MaintenanceScreen()))
                          .then((_) => _fetchMaintenance()),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _overdueCount > 0
                                ? const Color(0xFFE8003D).withOpacity(0.35)
                                : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: (_overdueCount > 0
                                  ? const Color(0xFFE8003D)
                                  : _dueSoonCount > 0
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF00C853))
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.build_rounded,
                                color: _overdueCount > 0
                                    ? const Color(0xFFE8003D)
                                    : _dueSoonCount > 0
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFF00C853),
                                size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Maintenance',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 3),
                                Text(
                                  _overdueCount > 0
                                      ? '$_overdueCount item${_overdueCount > 1 ? 's' : ''} overdue'
                                      : _dueSoonCount > 0
                                          ? '$_dueSoonCount item${_dueSoonCount > 1 ? 's' : ''} due soon'
                                          : 'All services up to date',
                                  style: TextStyle(
                                      color: _overdueCount > 0
                                          ? const Color(0xFFE8003D)
                                          : _dueSoonCount > 0
                                              ? const Color(0xFFFFD700)
                                              : Colors.white38,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: Colors.white24, size: 14),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 28)),

                // Recent Rides Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Text(
                          'RECENT RIDES',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (_totalRides > 0)
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const RideHistoryScreen()),
                            ),
                            child: Text(
                              'View all →',
                              style: TextStyle(
                                color: const Color(0xFFE8003D).withOpacity(0.7),
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 14)),

                // Rides list or empty state
                _recentRides.isEmpty && !_isLoading
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.motorcycle_rounded,
                                    color: Colors.white12, size: 40),
                                const SizedBox(height: 12),
                                const Text(
                                  'No rides yet',
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap START RIDE to log your first ride',
                                  style: TextStyle(
                                      color: Colors.white24,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final ride = _recentRides[index];
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 0, 24, 10),
                              child: _rideCard(ride),
                            );
                          },
                          childCount: _recentRides.length,
                        ),
                      ),

                // Bottom padding for floating nav
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    final w = _weather;
    final badgeColor =
        w != null && w.isGoodForRiding ? const Color(0xFF00C853) : const Color(0xFFFFD700);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Text(
            w != null ? w.emoji : '🌡️',
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONDITIONS',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 10, letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        w != null ? w.ridingCondition : 'Loading weather...',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w300),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (w != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: badgeColor.withOpacity(0.4)),
                        ),
                        child: Text(
                          w.badge,
                          style: TextStyle(
                              color: badgeColor,
                              fontSize: 9,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (w != null) ...[
            const SizedBox(width: 12),
            Column(
              children: [
                Text(
                  '${w.tempC.toStringAsFixed(0)}°',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w200),
                ),
                Text(
                  '${w.windSpeedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _shimmerRow() {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Container(
            height: 90,
            margin: EdgeInsets.only(right: i < 2 ? 12 : 0),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 9,
                    letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(RideModel ride) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8003D).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFE8003D).withOpacity(0.2)),
            ),
            child: const Icon(Icons.motorcycle_rounded,
                color: Color(0xFFE8003D), size: 20),
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 4),
                Text(
                  '${ride.distanceKm.toStringAsFixed(2)} km  ·  ${ride.formattedDuration}  ·  ${ride.avgSpeedKmh.toStringAsFixed(0)} km/h avg',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            ride.relativeDate,
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING,';
    if (hour < 17) return 'GOOD AFTERNOON,';
    return 'GOOD EVENING,';
  }
}
