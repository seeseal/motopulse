import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/crash_detector.dart';
import '../services/group_ride_service.dart';
import '../services/profile_service.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _sosActivated = false;
  bool _alertingSent = false;
  RiderProfile? _profile;

  @override
  void initState() {
    super.initState();
    ProfileService.load().then((p) {
      if (mounted) setState(() => _profile = p);
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _activateSOS() async {
    if (_sosActivated) {
      // User cancelled — they are conscious and safe.
      // Reset crash detector cooldown so a new real incident can be detected.
      CrashDetector.resetCooldown();
      await GroupRideService.cancelSOS();
      setState(() {
        _sosActivated = false;
        _alertingSent = false;
      });
      return;
    }

    setState(() => _sosActivated = true);

    // ── 1. Get current GPS position ──────────────────────────────────────────
    Position? position;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 6));
      }
    } catch (_) {}

    // ── 2. Check network before deciding dispatch path ───────────────────────
    // Note: connectivity_plus reports network TYPE (wifi/mobile), not whether
    // the internet is actually reachable. We treat it as "maybe online" and
    // use a timeout on the Firebase write to detect true unreachability.
    final connectivity = await Connectivity().checkConnectivity();
    final likelyOnline = connectivity != ConnectivityResult.none;

    bool groupAlerted = false;
    bool smsSent = false;
    bool callAttempted = false;
    bool firebaseSucceeded = false;

    if (likelyOnline && GroupRideService.isActive && position != null) {
      // ── Attempt Firebase group alert (5 s timeout) ───────────────────────
      try {
        await GroupRideService.triggerSOS(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 5));
        groupAlerted = true;
        firebaseSucceeded = true;
      } catch (_) {
        // Firebase timed out or threw — fall through to direct contacts below
        firebaseSucceeded = false;
      }
    }

    // ── SMS — always send, regardless of Firebase outcome ───────────────────
    // (url_launcher intent is network-independent)
    await _sendSMSToContact(position);
    smsSent = true;

    // ── Call — send when offline OR Firebase failed OR no group active ───────
    // In the online+group path the group alert is the primary escalation;
    // the call is the fallback when that path fails.
    if (!firebaseSucceeded || !likelyOnline) {
      await _attemptEmergencyCall();
      callAttempted = true;
    }

    // ── Queue locally if Firebase was unavailable ────────────────────────────
    if (!firebaseSucceeded && GroupRideService.isActive) {
      await _saveSOSLocally(position);
    }

    if (!mounted) return;
    setState(() => _alertingSent = groupAlerted);

    _showSOSConfirmDialog(
      position: position,
      groupAlerted: groupAlerted,
      wasOffline: !likelyOnline || !firebaseSucceeded,
      callAttempted: callAttempted,
    );
  }

  // ── SOS helpers ─────────────────────────────────────────────────────────────

  Future<void> _sendSMSToContact(Position? position) async {
    if (_profile == null || _profile!.emergencyPhone.isEmpty) return;
    final phone = _profile!.emergencyPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final lat = position?.latitude.toStringAsFixed(5) ?? 'unknown';
    final lng = position?.longitude.toStringAsFixed(5) ?? 'unknown';
    final msg = Uri.encodeComponent(
      'EMERGENCY: ${_profile!.name} needs help! '
      'Location: https://maps.google.com/?q=$lat,$lng '
      '— Sent via MotoPulse',
    );
    try {
      await launchUrl(Uri.parse('sms:$phone?body=$msg'));
    } catch (_) {}
  }

  Future<void> _attemptEmergencyCall() async {
    if (_profile == null || _profile!.emergencyPhone.isEmpty) return;
    final phone = _profile!.emergencyPhone.replaceAll(RegExp(r'[^\d+]'), '');
    try {
      await launchUrl(Uri.parse('tel:$phone'));
    } catch (_) {}
  }

  /// Persists an offline SOS event to SharedPreferences so GroupRideService
  /// can flush it to Firebase when connectivity is restored.
  Future<void> _saveSOSLocally(Position? position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_sos') ?? [];
      pending.add(jsonEncode({
        'lat': position?.latitude,
        'lng': position?.longitude,
        'ts': DateTime.now().toIso8601String(),
        'riderName': _profile?.name ?? 'Rider',
      }));
      await prefs.setStringList('pending_sos', pending);
    } catch (_) {}
  }

  void _showSOSConfirmDialog({
    required Position? position,
    required bool groupAlerted,
    required bool wasOffline,
    required bool callAttempted,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: const Color(0xFFE8003D).withOpacity(0.4)),
        ),
        title: const Text(
          'SOS Activated',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w300,
            letterSpacing: 1,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Network / dispatch status banner
            _sosStatusBanner(
              groupAlerted: groupAlerted,
              wasOffline: wasOffline,
              callAttempted: callAttempted,
            ),
            const SizedBox(height: 12),

            // Location
            if (position != null)
              Text(
                'Location: ${position.latitude.toStringAsFixed(5)}, '
                '${position.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              )
            else
              const Text(
                'Could not get exact location.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),

            const SizedBox(height: 8),

            // Offline queued note
            if (wasOffline)
              const Text(
                'No signal — SOS saved and will sync when you reconnect.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
              )
            else
              const Text(
                'Your emergency contacts have been notified.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              CrashDetector.resetCooldown(); // user is safe — allow fresh detection
              await GroupRideService.cancelSOS();
              setState(() {
                _sosActivated = false;
                _alertingSent = false;
              });
            },
            child: const Text(
              'Cancel SOS',
              style: TextStyle(color: Color(0xFFE8003D)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sosStatusBanner({
    required bool groupAlerted,
    required bool wasOffline,
    required bool callAttempted,
  }) {
    final IconData icon;
    final String label;
    final Color color;

    if (wasOffline && callAttempted) {
      icon = Icons.signal_wifi_off_rounded;
      label = 'Offline — SMS + call sent directly to contacts';
      color = Colors.orange;
    } else if (wasOffline) {
      icon = Icons.signal_wifi_off_rounded;
      label = 'Offline — SMS sent directly to contacts';
      color = Colors.orange;
    } else if (groupAlerted) {
      icon = Icons.group_rounded;
      label = 'Group ride alerted with your live location';
      color = const Color(0xFFE8003D);
    } else {
      icon = Icons.message_rounded;
      label = 'SMS sent to emergency contact';
      color = const Color(0xFFE8003D);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color.withOpacity(0.9), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SAFETY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (GroupRideService.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF00C853).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.group_rounded,
                              color: Color(0xFF00C853), size: 12),
                          SizedBox(width: 5),
                          Text(
                            'GROUP RIDE ACTIVE',
                            style: TextStyle(
                                color: Color(0xFF00C853),
                                fontSize: 9,
                                letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 48),

              // SOS Button
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return GestureDetector(
                    onTap: _activateSOS,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_sosActivated)
                          Transform.scale(
                            scale: _pulseAnimation.value * 1.3,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFE8003D)
                                      .withOpacity(0.15),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        Transform.scale(
                          scale: _sosActivated
                              ? _pulseAnimation.value * 1.1
                              : 1.0,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE8003D).withOpacity(
                                    _sosActivated ? 0.3 : 0.15),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _sosActivated
                                ? const Color(0xFFE8003D)
                                : const Color(0xFF120008),
                            border: Border.all(
                              color: const Color(0xFFE8003D),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'SOS',
                                style: TextStyle(
                                  color: _sosActivated
                                      ? Colors.white
                                      : const Color(0xFFE8003D),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                              Text(
                                _sosActivated ? 'ACTIVE' : 'PRESS',
                                style: TextStyle(
                                  color: _sosActivated
                                      ? Colors.white70
                                      : Colors.white24,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),
              Text(
                _sosActivated
                    ? (_alertingSent
                        ? 'Group ride alerted · Tap to cancel'
                        : 'SOS active · Tap to cancel')
                    : (GroupRideService.isActive
                        ? 'Tap to alert your group ride'
                        : 'Tap to send emergency alert'),
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 40),

              // QR Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EMERGENCY QR',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Attach to your helmet',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: _profile?.qrData ??
                              'MotoPulse Emergency\nName: Rider\nBlood: Unknown',
                          version: QrVersions.auto,
                          size: 140,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Contacts
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EMERGENCY CONTACTS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_profile != null &&
                        _profile!.emergencyName.isNotEmpty) ...[
                      _buildContact(
                          _profile!.emergencyName, _profile!.emergencyPhone),
                      const SizedBox(height: 12),
                    ] else
                      const Text(
                        'No emergency contact set.\nAdd one in your Profile.',
                        style: TextStyle(
                            color: Colors.white30, fontSize: 13, height: 1.5),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_add_rounded,
                            color: Color(0xFFE8003D), size: 15),
                        const SizedBox(width: 8),
                        Text(
                          'Edit in Profile tab',
                          style: TextStyle(
                            color: const Color(0xFFE8003D).withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callContact(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    try {
      await launchUrl(Uri.parse('tel:$clean'));
    } catch (_) {}
  }

  Future<void> _smsContact(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    try {
      await launchUrl(Uri.parse('sms:$clean'));
    } catch (_) {}
  }

  Widget _buildContact(String name, String phone) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 2),
              Text(phone,
                  style:
                      const TextStyle(color: Colors.white30, fontSize: 12)),
            ],
          ),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () => _smsContact(phone),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.message_outlined,
                    color: Colors.white38, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _callContact(phone),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF00C853).withOpacity(0.3)),
                ),
                child: const Icon(Icons.call_rounded,
                    color: Color(0xFF00C853), size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
