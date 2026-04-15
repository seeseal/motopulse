import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
      // Cancel SOS
      await GroupRideService.cancelSOS();
      setState(() {
        _sosActivated = false;
        _alertingSent = false;
      });
      return;
    }

    setState(() => _sosActivated = true);

    // Get current GPS location
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

    // Send SMS to emergency contact
    if (_profile != null && _profile!.emergencyPhone.isNotEmpty) {
      final phone = _profile!.emergencyPhone.replaceAll(RegExp(r'[^\d+]'), '');
      final lat = position?.latitude.toStringAsFixed(5) ?? 'unknown';
      final lng = position?.longitude.toStringAsFixed(5) ?? 'unknown';
      final msg = Uri.encodeComponent(
        'EMERGENCY: ${_profile!.name} needs help! '
        'Location: https://maps.google.com/?q=$lat,$lng '
        '- Sent via MotoPulse',
      );
      final smsUri = Uri.parse('sms:$phone?body=$msg');
      try {
        await launchUrl(smsUri);
      } catch (_) {}
    }

    // Alert group ride if active
    bool groupAlerted = false;
    if (GroupRideService.isActive && position != null) {
      await GroupRideService.triggerSOS(position.latitude, position.longitude);
      groupAlerted = true;
    }

    if (!mounted) return;
    setState(() => _alertingSent = groupAlerted);

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
            if (groupAlerted) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8003D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFE8003D).withOpacity(0.3)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.group_rounded,
                        color: Color(0xFFE8003D), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Group ride alerted with your live location',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (position != null)
              Text(
                'Location: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              )
            else
              const Text(
                'Could not get exact location.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            const SizedBox(height: 8),
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
    final uri = Uri.parse('tel:$clean');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> _smsContact(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('sms:$clean');
    try {
      await launchUrl(uri);
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
