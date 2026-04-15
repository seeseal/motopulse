import 'package:flutter/material.dart';
import '../models/ride_model.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  double _totalKm = 0;
  int _totalRides = 0;
  double _totalHours = 0;
  double _topSpeedKmh = 0;
  double _thisWeekKm = 0;
  List<double> _weeklyData = List.filled(7, 0.0);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await RideStorage.getStats();
    if (mounted) {
      setState(() {
        _totalKm = stats['totalKm'];
        _totalRides = stats['totalRides'];
        _totalHours = stats['totalHours'];
        _topSpeedKmh = stats['topSpeedKmh'];
        _thisWeekKm = stats['thisWeekKm'];
        _weeklyData = List<double>.from(stats['weeklyData']);
        _isLoading = false;
      });
    }
  }

  String _formatHours(double h) {
    if (h < 1) return '${(h * 60).toStringAsFixed(0)}min';
    return '${h.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFE8003D), strokeWidth: 1.5))
            : RefreshIndicator(
                onRefresh: _loadStats,
                color: const Color(0xFFE8003D),
                backgroundColor: const Color(0xFF1A1A1A),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      const Text(
                        'STATS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Hero stat
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL DISTANCE',
                              style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 10,
                                  letterSpacing: 3),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _totalKm.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w200,
                                    height: 1,
                                  ),
                                ),
                                const Padding(
                                  padding:
                                      EdgeInsets.only(bottom: 8, left: 8),
                                  child: Text('km',
                                      style: TextStyle(
                                          color: Colors.white30,
                                          fontSize: 18)),
                                ),
                              ],
                            ),
                            if (_totalRides == 0)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Complete your first ride to see stats',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                              child: _buildStatCard('$_totalRides',
                                  'rides', Icons.motorcycle)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard(
                                  _formatHours(_totalHours),
                                  'ride time',
                                  Icons.timer_outlined)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildStatCard(
                                  '${_topSpeedKmh.toStringAsFixed(0)}',
                                  'top km/h',
                                  Icons.speed_outlined)),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Weekly chart
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('THIS WEEK',
                                    style: TextStyle(
                                        color: Colors.white24,
                                        fontSize: 10,
                                        letterSpacing: 3)),
                                const Spacer(),
                                Text('${_thisWeekKm.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildBar('M', _weeklyData[0]),
                                _buildBar('T', _weeklyData[1]),
                                _buildBar('W', _weeklyData[2]),
                                _buildBar('T', _weeklyData[3]),
                                _buildBar('F', _weeklyData[4]),
                                _buildBar('S', _weeklyData[5]),
                                _buildBar('S', _weeklyData[6]),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      const Text('ACHIEVEMENTS',
                          style: TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                              letterSpacing: 3)),
                      const SizedBox(height: 16),

                      _buildAchievement('🏁', 'First Ride',
                          'Complete your first ride', _totalRides >= 1),
                      const SizedBox(height: 10),
                      _buildAchievement('🛣️', 'Road Starter',
                          'Ride 100+ km total', _totalKm >= 100),
                      const SizedBox(height: 10),
                      _buildAchievement('🏆', 'Road Warrior',
                          'Ride 1,000+ km total', _totalKm >= 1000),
                      const SizedBox(height: 10),
                      _buildAchievement('⚡', 'Speed Demon',
                          'Hit 120+ km/h', _topSpeedKmh >= 120),
                      const SizedBox(height: 10),
                      _buildAchievement(
                          '🔟', 'Veteran', 'Complete 10 rides', _totalRides >= 10),
                      const SizedBox(height: 10),
                      _buildAchievement('🌍', 'Explorer',
                          'Ride 5,000+ km total', _totalKm >= 5000),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white24, size: 16),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w300)),
          Text(label,
              style:
                  const TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBar(String day, double height) {
    final todayIndex = DateTime.now().weekday - 1;
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final isToday = days[todayIndex] == day;

    return Column(
      children: [
        Container(
          width: 28,
          height: height > 0 ? (80 * height).clamp(4.0, 80.0) : 4,
          decoration: BoxDecoration(
            color: height > 0
                ? (isToday
                    ? const Color(0xFFE8003D)
                    : const Color(0xFFE8003D).withOpacity(0.4))
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Text(day,
            style: TextStyle(
                color: isToday ? Colors.white54 : Colors.white24,
                fontSize: 11)),
      ],
    );
  }

  Widget _buildAchievement(
      String emoji, String title, String desc, bool unlocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked
              ? const Color(0xFFE8003D).withOpacity(0.2)
              : Colors.white.withOpacity(0.04),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: unlocked
                  ? const Color(0xFFE8003D).withOpacity(0.1)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(unlocked ? emoji : '🔒',
                  style:
                      TextStyle(fontSize: unlocked ? 20 : 16)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: unlocked ? Colors.white : Colors.white24,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Text(desc,
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
          if (unlocked)
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFFE8003D)),
            ),
        ],
      ),
    );
  }
}
