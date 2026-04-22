import 'package:flutter/material.dart';
import '../services/battery_guard.dart';

/// Full-screen blocking prompt shown when Android battery optimisation is
/// still enabled for MotoPulse.
///
/// This screen CANNOT be dismissed — it only pops (returning true) once the
/// system exemption is granted. The caller should treat any non-true return
/// value as "not granted" and abort the ride start.
///
/// Usage:
/// ```dart
/// final granted = await Navigator.push<bool>(
///   context,
///   MaterialPageRoute(builder: (_) => const BatteryGateScreen()),
/// );
/// if (granted != true) return; // user didn't grant — abort
/// ```
class BatteryGateScreen extends StatefulWidget {
  const BatteryGateScreen({super.key});

  @override
  State<BatteryGateScreen> createState() => _BatteryGateScreenState();
}

class _BatteryGateScreenState extends State<BatteryGateScreen> {
  String _guidance = '';
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _loadGuidance();
  }

  Future<void> _loadGuidance() async {
    final g = await BatteryGuard.oemGuidance();
    if (mounted) setState(() => _guidance = g);
  }

  Future<void> _openSettings() async {
    setState(() => _requesting = true);
    final granted = await BatteryGuard.requestExemption();
    if (!mounted) return;
    setState(() => _requesting = false);
    if (granted) {
      Navigator.of(context).pop(true);
    }
    // If not granted, stay on screen — user can try again or read the manual path
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent back-button dismissal — this gate must be passed, not bypassed
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF080808),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),

                // Icon
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8003D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFFE8003D).withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.battery_alert_rounded,
                    color: Color(0xFFE8003D),
                    size: 28,
                  ),
                ),

                const SizedBox(height: 28),

                // Heading
                const Text(
                  'One permission required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 14),

                // Explanation
                const Text(
                  'Live group tracking and crash detection need to run while your '
                  'screen is off. Android\'s battery optimisation will stop '
                  'MotoPulse mid-ride unless you disable it for this app.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),

                // OEM-specific path (shown once loaded)
                if (_guidance.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR DEVICE PATH',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _guidance,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // Primary action
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8003D),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFE8003D).withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _requesting ? null : _openSettings,
                    child: _requesting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Open Settings',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Warning note
                Center(
                  child: Text(
                    'Tracking will stop without this — it cannot be skipped.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.22),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
