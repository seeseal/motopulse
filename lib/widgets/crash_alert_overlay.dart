import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/profile_service.dart';
import '../services/ride_service.dart';

/// Full-screen crash-detected alert.
/// Shows a 30-second countdown. Tapping "I'M OK" dismisses immediately.
/// When the timer expires the app opens an SMS to the emergency contact.
class CrashAlertOverlay extends StatefulWidget {
  const CrashAlertOverlay({super.key});

  @override
  State<CrashAlertOverlay> createState() => _CrashAlertOverlayState();
}

class _CrashAlertOverlayState extends State<CrashAlertOverlay>
    with SingleTickerProviderStateMixin {
  static const int _countdownStart = 30;
  int _remaining = _countdownStart;
  Timer? _ticker;
  late AnimationController _pulse;
  String _emergencyPhone = '';
  String _emergencyName  = '';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    HapticFeedback.heavyImpact();

    ProfileService.load().then((p) {
      if (mounted) {
        setState(() {
          _emergencyPhone = p.emergencyPhone;
          _emergencyName  = p.emergencyName;
        });
      }
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _remaining--);
      if (_remaining <= 0) _sendSOS();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _dismiss() {
    _ticker?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _sendSOS() async {
    _ticker?.cancel();
    final lat = RideService.routePoints.isNotEmpty
        ? RideService.routePoints.last.latitude
        : 0.0;
    final lng = RideService.routePoints.isNotEmpty
        ? RideService.routePoints.last.longitude
        : 0.0;

    final body =
        'CRASH ALERT from MotoPulse!\n'
        'I may have been in an accident.\n'
        'Last location: https://maps.google.com/?q=$lat,$lng\n'
        'Please check on me.';

    final phone = _emergencyPhone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isNotEmpty) {
      final uri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': body},
      );
      await launchUrl(uri);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _remaining / _countdownStart;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Container(
            color: Color.lerp(
              const Color(0xFF1A0000),
              const Color(0xFF3D0010),
              _pulse.value,
            ),
            child: child,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  // Warning icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE8003D).withOpacity(0.15),
                      border: Border.all(
                          color: const Color(0xFFE8003D), width: 2),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFE8003D), size: 36),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'CRASH DETECTED',
                    style: TextStyle(
                      color: Color(0xFFE8003D),
                      fontSize: 13,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you okay?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w200,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emergencyName.isNotEmpty
                        ? 'SOS will be sent to $_emergencyName'
                        : 'Set an emergency contact in your profile',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),

                  const Spacer(),

                  // Circular countdown
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: pct,
                            strokeWidth: 6,
                            backgroundColor:
                                const Color(0xFFE8003D).withOpacity(0.15),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFE8003D)),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_remaining',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 56,
                                fontWeight: FontWeight.w200,
                                height: 1,
                              ),
                            ),
                            const Text(
                              'SECONDS',
                              style: TextStyle(
                                color: Colors.white30,
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // I'M OK button
                  GestureDetector(
                    onTap: _dismiss,
                    child: Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          "I'M OK — CANCEL",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Send now button
                  GestureDetector(
                    onTap: _sendSOS,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8003D),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'SEND SOS NOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
