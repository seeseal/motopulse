import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/ride_service.dart';
import '../services/profile_service.dart';
import '../services/weather_service.dart';

// ════════════════════════════════════════════════════════════════════════════
//  HUD Speedometer Screen
//  3-panel landscape layout: [mini gauge | stats grid | large dial + LED bar]
// ════════════════════════════════════════════════════════════════════════════

class SpeedometerScreen extends StatefulWidget {
  const SpeedometerScreen({super.key});

  @override
  State<SpeedometerScreen> createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen>
    with SingleTickerProviderStateMixin {
  // ── Speed state ───────────────────────────────────────────────────────────
  double _speedKmh = 0;
  double _maxSpeedKmh = 0;
  double _avgSpeedKmh = 0;
  double _speedLimitKmh = 100;
  double _fuelRangeKm = 200;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<void>? _rideSub;

  // ── Needle animation ──────────────────────────────────────────────────────
  late AnimationController _needleCtrl;
  late Animation<double> _needleAnim;
  double _prevNeedleSpd = 0;

  // ── Clock & weather ───────────────────────────────────────────────────────
  Timer? _clockTimer;
  String _timeStr = '';
  WeatherData? _weather;

  // ── Colours ───────────────────────────────────────────────────────────────
  static const _green  = Color(0xFF4CAF50);
  static const _red    = Color(0xFFE8003D);
  static const _amber  = Color(0xFFFFD700);
  static const _blue   = Color(0xFF2979FF);
  static const _purple = Color(0xFF7C4DFF);

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _needleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _needleAnim = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _needleCtrl, curve: Curves.easeOut));

    _tickClock();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _tickClock());

    _loadProfile();
    _fetchWeather();
    _listenRideService();
    if (!RideService.isRiding) _startOwnGPS();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _gpsSub?.cancel();
    _rideSub?.cancel();
    _needleCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  // ── Init helpers ──────────────────────────────────────────────────────────

  void _tickClock() {
    final n = DateTime.now();
    if (mounted) {
      setState(() {
        _timeStr = '${n.hour.toString().padLeft(2, '0')}:'
            '${n.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _loadProfile() async {
    final p = await ProfileService.load();
    if (!mounted) return;
    setState(() {
      _speedLimitKmh = p.speedLimitKmh;
      _fuelRangeKm   = p.fuelTankL * p.fuelEfficiencyKmL;
    });
  }

  Future<void> _fetchWeather() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low)
          .timeout(const Duration(seconds: 6));
      final w = await WeatherService.fetchWeather(pos.latitude, pos.longitude);
      if (mounted && w != null) setState(() => _weather = w);
    } catch (_) {}
  }

  void _listenRideService() {
    // Seed current values if already riding
    if (RideService.isRiding) {
      _speedKmh    = RideService.speedKmh;
      _maxSpeedKmh = RideService.maxSpeedKmh;
    }
    _rideSub = RideService.onChange.listen((_) {
      if (!mounted || !RideService.isRiding) return;
      final spd = RideService.speedKmh;
      final avg = RideService.speedReadings > 0
          ? RideService.totalSpeedSum / RideService.speedReadings
          : 0.0;
      _onNewSpeed(spd);
      setState(() {
        _maxSpeedKmh = RideService.maxSpeedKmh;
        _avgSpeedKmh = avg;
      });
    });
  }

  void _startOwnGPS() {
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final spd = (pos.speed * 3.6).clamp(0.0, 280.0);
      if (spd > _maxSpeedKmh) setState(() => _maxSpeedKmh = spd);
      _onNewSpeed(spd);
    });
  }

  void _onNewSpeed(double spd) {
    _needleAnim = Tween<double>(begin: _prevNeedleSpd, end: spd).animate(
        CurvedAnimation(parent: _needleCtrl, curve: Curves.easeOut));
    _needleCtrl.forward(from: 0);
    _prevNeedleSpd = spd;
    if (spd > _speedLimitKmh) HapticFeedback.heavyImpact();
    setState(() => _speedKmh = spd);
  }

  // ── Computed ──────────────────────────────────────────────────────────────
  bool get _over => _speedKmh > _speedLimitKmh;
  bool get _riding => RideService.isRiding;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060606),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final W = constraints.maxWidth;
            final H = constraints.maxHeight;

            // Fixed row heights
            const topH = 30.0;
            const botH = 26.0;
            const sepH = 0.5;
            final mainH = H - topH - botH - sepH * 2;

            // Panel widths
            final leftW  = W * 0.20;
            final rightW = W * 0.37;
            const ledW   = 14.0;

            // Dial sizes — never clip the panel
            final miniSize = (min(leftW * 0.84, mainH * 0.52)).clamp(60.0, 160.0);
            final dialSize = (min(rightW - ledW - 18, mainH * 0.88)).clamp(80.0, 280.0);

            return Column(
              children: [
                // ── Top bar ────────────────────────────────────────────────
                SizedBox(height: topH, child: _topBar()),
                Container(height: sepH, color: Colors.white.withOpacity(0.08)),

                // ── 3 panels ───────────────────────────────────────────────
                SizedBox(
                  height: mainH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // LEFT
                      SizedBox(
                          width: leftW,
                          child: _leftPanel(miniSize)),
                      Container(width: sepH, color: Colors.white.withOpacity(0.08)),
                      // CENTER
                      Expanded(child: _centerPanel()),
                      Container(width: sepH, color: Colors.white.withOpacity(0.08)),
                      // RIGHT
                      SizedBox(
                          width: rightW,
                          child: _rightPanel(dialSize, ledW, mainH)),
                    ],
                  ),
                ),

                Container(height: sepH, color: Colors.white.withOpacity(0.08)),
                // ── Bottom bar ─────────────────────────────────────────────
                SizedBox(height: botH, child: _bottomBar()),
              ],
            );
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Top bar
  // ══════════════════════════════════════════════════════════════════════════

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white38, size: 13),
          ),
          const SizedBox(width: 10),

          // Weather
          if (_weather != null) ...[
            Text(_weather!.emoji, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text('${_weather!.tempC.toStringAsFixed(0)}°C',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            const SizedBox(width: 6),
            Text(_weather!.ridingCondition,
                style: const TextStyle(color: Colors.white24, fontSize: 9),
                overflow: TextOverflow.ellipsis),
          ],

          const Spacer(),

          // Speed limit badge
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _over
                  ? _red.withOpacity(0.18)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _over
                    ? _red.withOpacity(0.55)
                    : Colors.white.withOpacity(0.09),
                width: 0.5,
              ),
            ),
            child: Text(
              'LIMIT  ${_speedLimitKmh.round()}',
              style: TextStyle(
                color: _over ? _red : Colors.white38,
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Clock
          Text(_timeStr,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Left panel — mini arc gauge + stats
  // ══════════════════════════════════════════════════════════════════════════

  Widget _leftPanel(double gaugeSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Mini gauge with speed number inside
        SizedBox(
          width: gaugeSize,
          height: gaugeSize,
          child: AnimatedBuilder(
            animation: _needleAnim,
            builder: (_, __) => CustomPaint(
              painter: _MiniArcDial(
                speed: _needleAnim.value,
                limitSpeed: _speedLimitKmh,
                overLimit: _over,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _speedKmh.toStringAsFixed(0),
                      style: TextStyle(
                        color: _over ? _red : Colors.white,
                        fontSize: gaugeSize * 0.21,
                        fontWeight: FontWeight.w200,
                        height: 1,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                          color: Colors.white24,
                          fontSize: gaugeSize * 0.09,
                          letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Stats below gauge
        if (_riding) ...[
          _lStat(RideService.distanceKm.toStringAsFixed(1), 'KM'),
          const SizedBox(height: 5),
          _lStat(RideService.formattedTime, 'ELAPSED'),
        ] else
          _lStat(_maxSpeedKmh.toStringAsFixed(0), 'MAX KM/H'),
      ],
    );
  }

  Widget _lStat(String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 0.2)),
          Text(label,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 7, letterSpacing: 2)),
        ],
      );

  // ══════════════════════════════════════════════════════════════════════════
  //  Center panel — 2×2 stat grid + weather strip
  // ══════════════════════════════════════════════════════════════════════════

  Widget _centerPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          // 2×2 grid
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                          child: _statBox('AVG',
                              _avgSpeedKmh.toStringAsFixed(0), 'km/h',
                              _green)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: _statBox('MAX',
                              _maxSpeedKmh.toStringAsFixed(0), 'km/h',
                              _over ? _red : Color(0xFFFF6B00))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                          child: _statBox(
                              'DIST',
                              _riding
                                  ? RideService.distanceKm.toStringAsFixed(1)
                                  : '—',
                              'km',
                              _blue)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: _statBox(
                              'TIME',
                              _riding ? RideService.formattedTime : '—',
                              '',
                              _purple)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Weather strip
          if (_weather != null) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(children: [
                Text(_weather!.emoji,
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_weather!.ridingCondition}  ·  '
                    '${_weather!.tempC.toStringAsFixed(0)}°C',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 9),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (_weather!.isGoodForRiding ? _green : _amber)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _weather!.badge,
                    style: TextStyle(
                      color: _weather!.isGoodForRiding ? _green : _amber,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, String unit, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.14), width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 7, letterSpacing: 2)),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w200,
                        height: 1),
                    overflow: TextOverflow.ellipsis),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(unit,
                      style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 8,
                          letterSpacing: 0.3)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Right panel — large HUD dial + LED bar
  // ══════════════════════════════════════════════════════════════════════════

  Widget _rightPanel(double dialSize, double ledW, double mainH) {
    final speedColor = _over ? _red : _green;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Dial + digital readout
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: dialSize,
                height: dialSize,
                child: AnimatedBuilder(
                  animation: _needleAnim,
                  builder: (_, __) => CustomPaint(
                    painter: _HUDDial(
                      speed: _needleAnim.value,
                      limitSpeed: _speedLimitKmh,
                      overLimit: _over,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              color: _over ? _red : Colors.white,
                              fontSize: dialSize * 0.30,
                              fontWeight: FontWeight.w100,
                              height: 1,
                            ),
                            child:
                                Text(_speedKmh.toStringAsFixed(0)),
                          ),
                          Text('km/h',
                              style: TextStyle(
                                  color: speedColor,
                                  fontSize: dialSize * 0.085,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text('MAX  ${_maxSpeedKmh.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                      letterSpacing: 1.5)),
            ],
          ),
        ),

        // LED bar — far right edge, like the reference image
        SizedBox(
          width: ledW,
          child: _ledBar(mainH),
        ),
        const SizedBox(width: 5),
      ],
    );
  }

  Widget _ledBar(double availH) {
    const total = 22;
    final lit = ((_speedKmh / 200.0) * total).ceil().clamp(0, total);
    final limitIdx = ((_speedLimitKmh / 200.0) * total).floor().clamp(0, total);
    final barH = ((availH - 20) / total * 0.58).clamp(2.0, 10.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: List.generate(total, (i) {
          final idx = total - 1 - i; // bottom = 0, top = total-1
          final isLit = idx < lit;
          final isRed = idx >= limitIdx;
          final isAmber = !isRed && idx >= limitIdx - 3;

          Color c;
          if (isLit) {
            c = isRed
                ? _red
                : isAmber
                    ? _amber
                    : _green;
          } else {
            c = Colors.white.withOpacity(0.07);
          }

          return Container(
            margin: EdgeInsets.symmetric(vertical: barH * 0.18),
            width: 5,
            height: barH,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Bottom bar
  // ══════════════════════════════════════════════════════════════════════════

  Widget _bottomBar() {
    final dist      = _riding ? RideService.distanceKm : 0.0;
    final remaining = (_fuelRangeKm - dist).clamp(0.0, _fuelRangeKm);
    final fuelPct   = _fuelRangeKm > 0 ? remaining / _fuelRangeKm : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.local_gas_station_rounded,
              color: Colors.white24, size: 11),
          const SizedBox(width: 5),
          Text('${remaining.toStringAsFixed(0)} km',
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
          const SizedBox(width: 7),
          SizedBox(
            width: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fuelPct.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.07),
                valueColor: AlwaysStoppedAnimation(
                    fuelPct > 0.25 ? _green : _red),
                minHeight: 3,
              ),
            ),
          ),

          const Spacer(),

          if (_over)
            Text(
              '⚠  +${(_speedKmh - _speedLimitKmh).toStringAsFixed(0)} OVER LIMIT',
              style: const TextStyle(
                  color: _red,
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700),
            ),

          const Spacer(),

          if (_riding)
            Text('TRIP  ${RideService.distanceKm.toStringAsFixed(1)} km',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 9))
          else
            Text('MAX  ${_maxSpeedKmh.toStringAsFixed(0)} km/h',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Left-panel mini arc dial
// ════════════════════════════════════════════════════════════════════════════

class _MiniArcDial extends CustomPainter {
  final double speed;
  final double limitSpeed;
  final bool overLimit;

  static const _maxSpeed = 200.0;

  const _MiniArcDial({
    required this.speed,
    required this.limitSpeed,
    required this.overLimit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    const startAngle  = 135.0 * pi / 180;
    const sweepAngle  = 270.0 * pi / 180;
    final fraction    = (speed / _maxSpeed).clamp(0.0, 1.0);
    final limitFrac   = (limitSpeed / _maxSpeed).clamp(0.0, 1.0);
    final activeColor = overLimit ? const Color(0xFFE8003D) : const Color(0xFF4CAF50);

    final trackPaint = Paint()
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false,
      trackPaint
        ..color       = Colors.white.withOpacity(0.07)
        ..strokeWidth = 5,
    );

    // Speed-limit zone (dim red)
    if (limitFrac < 1.0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + sweepAngle * limitFrac,
        sweepAngle * (1 - limitFrac),
        false,
        trackPaint
          ..color       = const Color(0xFFE8003D).withOpacity(0.18)
          ..strokeWidth = 5,
      );
    }

    // Active progress arc
    if (fraction > 0.005) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * fraction, false,
        trackPaint
          ..color       = activeColor.withOpacity(0.85)
          ..strokeWidth = 5,
      );
    }

    // Glowing tip dot
    if (fraction > 0.01) {
      final tipAngle = startAngle + sweepAngle * fraction;
      final tip = Offset(
        center.dx + radius * cos(tipAngle),
        center.dy + radius * sin(tipAngle),
      );
      canvas.drawCircle(tip, 7, Paint()..color = activeColor.withOpacity(0.2));
      canvas.drawCircle(tip, 4, Paint()..color = activeColor);
      canvas.drawCircle(tip, 1.8, Paint()..color = Colors.white.withOpacity(0.9));
    }
  }

  @override
  bool shouldRepaint(_MiniArcDial old) =>
      old.speed != speed || old.overLimit != overLimit;
}

// ════════════════════════════════════════════════════════════════════════════
//  Right-panel large HUD dial
// ════════════════════════════════════════════════════════════════════════════

class _HUDDial extends CustomPainter {
  final double speed;
  final double limitSpeed;
  final bool overLimit;

  static const _maxSpeed = 200.0;

  const _HUDDial({
    required this.speed,
    required this.limitSpeed,
    required this.overLimit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center      = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 6;
    final trackRadius = outerRadius - 16;

    const startAngle = 135.0 * pi / 180;
    const sweepAngle = 270.0 * pi / 180;
    final fraction   = (speed / _maxSpeed).clamp(0.0, 1.0);
    final limitFrac  = (limitSpeed / _maxSpeed).clamp(0.0, 1.0);

    final activeColor = overLimit ? const Color(0xFFE8003D) : const Color(0xFF4CAF50);

    // ── Outer tick marks ─────────────────────────────────────────────────────
    const ticks = 36;
    for (int i = 0; i <= ticks; i++) {
      final a       = startAngle + sweepAngle * (i / ticks);
      final frac    = i / ticks;
      final isMaj   = i % 6 == 0;
      final inLimit = frac > limitFrac;
      final len     = isMaj ? 14.0 : 8.0;

      final outer = Offset(
          center.dx + outerRadius * cos(a), center.dy + outerRadius * sin(a));
      final inner = Offset(
          center.dx + (outerRadius - len) * cos(a),
          center.dy + (outerRadius - len) * sin(a));

      canvas.drawLine(
        outer,
        inner,
        Paint()
          ..color      = inLimit
              ? const Color(0xFFE8003D).withOpacity(isMaj ? 0.45 : 0.2)
              : Colors.white.withOpacity(isMaj ? 0.38 : 0.12)
          ..strokeWidth = isMaj ? 1.5 : 0.8
          ..strokeCap  = StrokeCap.round,
      );
    }

    final arcPaint = Paint()
      ..style     = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ── Background track ─────────────────────────────────────────────────────
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius),
      startAngle, sweepAngle, false,
      arcPaint
        ..color       = Colors.white.withOpacity(0.06)
        ..strokeWidth = 9,
    );

    // ── Limit zone ───────────────────────────────────────────────────────────
    if (limitFrac < 1.0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: trackRadius),
        startAngle + sweepAngle * limitFrac,
        sweepAngle * (1 - limitFrac),
        false,
        arcPaint
          ..color       = const Color(0xFFE8003D).withOpacity(0.15)
          ..strokeWidth = 9,
      );
    }

    // ── Active arc ───────────────────────────────────────────────────────────
    if (fraction > 0.005) {
      // Soft glow
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: trackRadius),
        startAngle, sweepAngle * fraction, false,
        arcPaint
          ..color       = activeColor.withOpacity(0.14)
          ..strokeWidth = 20,
      );
      // Main
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: trackRadius),
        startAngle, sweepAngle * fraction, false,
        arcPaint
          ..color       = activeColor.withOpacity(0.88)
          ..strokeWidth = 9,
      );
    }

    // ── Indicator dot at speed tip ───────────────────────────────────────────
    if (fraction > 0.01) {
      final da = startAngle + sweepAngle * fraction;
      final dp = Offset(
          center.dx + trackRadius * cos(da),
          center.dy + trackRadius * sin(da));

      // Outer glow
      canvas.drawCircle(dp, 12, Paint()..color = activeColor.withOpacity(0.18));
      // Ring
      canvas.drawCircle(dp, 8,
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      // Fill
      canvas.drawCircle(dp, 6, Paint()..color = activeColor);
      // Specular
      canvas.drawCircle(dp, 2.5, Paint()..color = Colors.white.withOpacity(0.85));
    }

    // ── Inner subtle ring ────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      trackRadius - 18,
      Paint()
        ..color       = Colors.white.withOpacity(0.04)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_HUDDial old) =>
      old.speed != speed || old.overLimit != overLimit;
}
