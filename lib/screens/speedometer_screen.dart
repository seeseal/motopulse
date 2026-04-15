import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/profile_service.dart';

/// Full-screen speedometer — landscape-optimised, glanceable while riding.
class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen>
    with SingleTickerProviderStateMixin {
  double _speedKmh = 0;
  double _maxSpeedKmh = 0;
  double _speedLimitKmh = 100;
  StreamSubscription<Position>? _sub;
  late AnimationController _needleController;
  late Animation<double> _needleAnim;
  double _prevSpeed = 0;

  @override
  void initState() {
    super.initState();
    // Lock to landscape for this screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _needleController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _needleAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _needleController, curve: Curves.easeOut),
    );
    ProfileService.load().then((p) {
      if (mounted) setState(() => _speedLimitKmh = p.speedLimitKmh);
    });
    _startGPS();
  }

  @override
  void dispose() {
    // Restore all orientations on exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _sub?.cancel();
    _needleController.dispose();
    super.dispose();
  }

  void _startGPS() {
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final speed = (pos.speed * 3.6).clamp(0.0, 300.0);
      if (speed > _maxSpeedKmh) _maxSpeedKmh = speed;

      // Animate needle
      _needleAnim = Tween<double>(begin: _prevSpeed, end: speed).animate(
        CurvedAnimation(parent: _needleController, curve: Curves.easeOut),
      );
      _needleController.forward(from: 0);
      _prevSpeed = speed;

      if (speed > _speedLimitKmh) HapticFeedback.heavyImpact();
      setState(() => _speedKmh = speed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final overLimit = _speedKmh > _speedLimitKmh;
    final screenW = MediaQuery.of(context).size.width;
    final dialSize = screenW * 0.55;

    return Scaffold(
      backgroundColor: const Color(0xFF060606),
      body: SafeArea(
        child: Stack(
          children: [
            // Back button
            Positioned(
              top: 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white54, size: 16),
                ),
              ),
            ),

            // Speed limit badge
            Positioned(
              top: 12,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: overLimit
                      ? const Color(0xFFE8003D).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: overLimit
                        ? const Color(0xFFE8003D)
                        : Colors.white12,
                  ),
                ),
                child: Text(
                  'LIMIT  ${_speedLimitKmh.round()}',
                  style: TextStyle(
                    color: overLimit
                        ? const Color(0xFFE8003D)
                        : Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Main content — centred dial
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Dial
                  SizedBox(
                    width: dialSize,
                    height: dialSize,
                    child: AnimatedBuilder(
                      animation: _needleAnim,
                      builder: (_, __) => CustomPaint(
                        painter: _SpeedoDial(
                          speed: _needleAnim.value,
                          maxSpeed: 240,
                          limitSpeed: _speedLimitKmh,
                          overLimit: overLimit,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 48),

                  // Digital readout
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: overLimit
                              ? const Color(0xFFE8003D)
                              : Colors.white,
                          fontSize: 96,
                          fontWeight: FontWeight.w100,
                          height: 1,
                        ),
                        child: Text(_speedKmh.toStringAsFixed(0)),
                      ),
                      const Text(
                        'km/h',
                        style: TextStyle(
                            color: Colors.white24,
                            fontSize: 16,
                            letterSpacing: 2),
                      ),
                      const SizedBox(height: 24),
                      _statRow('MAX', '${_maxSpeedKmh.toStringAsFixed(0)} km/h'),
                    ],
                  ),
                ],
              ),
            ),

            // Over-limit warning bar at bottom
            if (overLimit)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: const Color(0xFFE8003D).withOpacity(0.9),
                  child: const Center(
                    child: Text(
                      '⚠  SPEED LIMIT EXCEEDED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
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

  Widget _statRow(String label, String value) {
    return Row(
      children: [
        Text('$label  ',
            style: const TextStyle(
                color: Colors.white24,
                fontSize: 11,
                letterSpacing: 2)),
        Text(value,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ── Custom painter for the analogue dial ─────────────────────────────────────

class _SpeedoDial extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final double limitSpeed;
  final bool overLimit;

  const _SpeedoDial({
    required this.speed,
    required this.maxSpeed,
    required this.limitSpeed,
    required this.overLimit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Arc spans from 225° to -45° (270° sweep)
    const startAngle = 135.0 * pi / 180;
    const sweepAngle = 270.0 * pi / 180;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Speed limit zone (red tint)
    final limitFraction = (limitSpeed / maxSpeed).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + sweepAngle * limitFraction,
      sweepAngle * (1 - limitFraction),
      false,
      Paint()
        ..color = const Color(0xFFE8003D).withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Active arc
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * fraction,
        false,
        Paint()
          ..color = overLimit
              ? const Color(0xFFE8003D)
              : const Color(0xFFE8003D).withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }

    // Tick marks
    for (int i = 0; i <= 24; i++) {
      final angle = startAngle + sweepAngle * (i / 24);
      final isMajor = i % 4 == 0;
      final innerR = isMajor ? radius - 22 : radius - 14;
      final outerR = radius - 4;
      final p1 = Offset(
        center.dx + innerR * cos(angle),
        center.dy + innerR * sin(angle),
      );
      final p2 = Offset(
        center.dx + outerR * cos(angle),
        center.dy + outerR * sin(angle),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.white.withOpacity(isMajor ? 0.4 : 0.15)
          ..strokeWidth = isMajor ? 2 : 1,
      );
    }

    // Needle
    final needleAngle = startAngle + sweepAngle * fraction;
    final needleLen = radius - 28;
    final needleTip = Offset(
      center.dx + needleLen * cos(needleAngle),
      center.dy + needleLen * sin(needleAngle),
    );
    canvas.drawLine(
      center,
      needleTip,
      Paint()
        ..color = overLimit ? const Color(0xFFE8003D) : Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Centre dot
    canvas.drawCircle(
      center,
      6,
      Paint()..color = Colors.white.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(_SpeedoDial old) =>
      old.speed != speed || old.overLimit != overLimit;
}
