import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/glass_card.dart';
import 'dashboard_screen.dart';
import 'ride_tracking_screen.dart';
import 'sos_screen.dart';
import 'stats_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  void _switchTab(int index) {
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        onStartRide: () => _switchTab(1),
        onGoSOS: () => _switchTab(2),
      ),
      const RideTrackingScreen(),
      const SOSScreen(),
      const StatsScreen(),
      const ProfileScreen(),
    ];

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: _GlassNavBar(
          currentIndex: _currentIndex,
          onTap: _switchTab,
        ),
      ),
    );
  }
}

// ── Glass Nav Bar ─────────────────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GlassNavBar({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.grid_view_rounded,   label: 'Home'),
    _NavItem(icon: Icons.route_rounded,        label: 'Track'),
    _NavItem(icon: Icons.sos_rounded,          label: 'SOS'),
    _NavItem(icon: Icons.bar_chart_rounded,    label: 'Stats'),
    _NavItem(icon: Icons.person_rounded,       label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, right: 28, bottom: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.white.withOpacity(0.13),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_items.length, (i) {
                final selected = currentIndex == i;
                final isSOS = i == 2;
                return GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 58,
                    height: 66,
                    child: Center(
                      child: isSOS
                          // SOS gets a special pill treatment
                          ? AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFE8003D)
                                    : const Color(0xFFE8003D).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE8003D)
                                      .withOpacity(selected ? 0 : 0.4),
                                ),
                              ),
                              child: Icon(
                                _items[i].icon,
                                color: Colors.white,
                                size: 20,
                              ),
                            )
                          : AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFE8003D).withOpacity(0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _items[i].icon,
                                color: selected
                                    ? const Color(0xFFE8003D)
                                    : Colors.white30,
                                size: 22,
                              ),
                            ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
