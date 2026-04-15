import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bikeCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  int _avatarIndex = 0;
  String _bloodType = '';
  double _fuelTankL = 15.0;
  double _fuelEfficiencyKmL = 30.0;
  double _speedLimitKmh = 100.0;
  bool _loading = true;
  bool _saving = false;

  static const _bloodTypes = [
    'A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−', 'Unknown'
  ];

  static const List<Map<String, dynamic>> _avatars = [
    {'emoji': '🏍️', 'color': Color(0xFFE8003D)},
    {'emoji': '🔥', 'color': Color(0xFFFF6B00)},
    {'emoji': '⚡', 'color': Color(0xFFFFD700)},
    {'emoji': '🐺', 'color': Color(0xFF7C4DFF)},
    {'emoji': '🦅', 'color': Color(0xFF00BCD4)},
    {'emoji': '💀', 'color': Color(0xFF607D8B)},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bikeCtrl.dispose();
    _allergiesCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await ProfileService.load();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = profile.name;
      _bikeCtrl.text = profile.bikeName;
      _allergiesCtrl.text = profile.allergies;
      _emergencyNameCtrl.text = profile.emergencyName;
      _emergencyPhoneCtrl.text = profile.emergencyPhone;
      _avatarIndex = profile.avatarIndex;
      _bloodType = profile.bloodType.isEmpty ? 'Unknown' : profile.bloodType;
      _fuelTankL = profile.fuelTankL;
      _fuelEfficiencyKmL = profile.fuelEfficiencyKmL;
      _speedLimitKmh = profile.speedLimitKmh;
      _loading = false;
    });
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    await ProfileService.save(
      name: _nameCtrl.text.trim().isEmpty ? 'Rider' : _nameCtrl.text.trim(),
      avatarIndex: _avatarIndex,
      bloodType: _bloodType,
      allergies: _allergiesCtrl.text.trim(),
      emergencyName: _emergencyNameCtrl.text.trim(),
      emergencyPhone: _emergencyPhoneCtrl.text.trim(),
      bikeName: _bikeCtrl.text.trim(),
      fuelTankL: _fuelTankL,
      fuelEfficiencyKmL: _fuelEfficiencyKmL,
      speedLimitKmh: _speedLimitKmh,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Profile saved'),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String get _qrData {
    final name = _nameCtrl.text.trim().isEmpty ? 'Rider' : _nameCtrl.text.trim();
    return 'MOTOPULSE EMERGENCY\n'
        'Name: $name\n'
        'Blood: $_bloodType\n'
        'Allergies: ${_allergiesCtrl.text.trim().isEmpty ? "None" : _allergiesCtrl.text.trim()}\n'
        'Bike: ${_bikeCtrl.text.trim().isEmpty ? "N/A" : _bikeCtrl.text.trim()}\n'
        'Emergency: ${_emergencyNameCtrl.text.trim().isEmpty ? "N/A" : "${_emergencyNameCtrl.text.trim()} · ${_emergencyPhoneCtrl.text.trim()}"}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF080808),
        body: Center(
          child: CircularProgressIndicator(
              color: Color(0xFFE8003D), strokeWidth: 1.5),
        ),
      );
    }

    final avatarColor = _avatars[_avatarIndex]['color'] as Color;
    final avatarEmoji = _avatars[_avatarIndex]['emoji'] as String;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Header ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'PROFILE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8003D),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.white))
                          : const Text(
                              'SAVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Avatar ────────────────────────────────────────────────────
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: avatarColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: avatarColor, width: 1.5),
                      ),
                      child: Center(
                        child: Text(avatarEmoji,
                            style: const TextStyle(fontSize: 36)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.white54, size: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Avatar selector
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _avatars.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final selected = _avatarIndex == i;
                    final c = _avatars[i]['color'] as Color;
                    return GestureDetector(
                      onTap: () => setState(() => _avatarIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected
                              ? c.withOpacity(0.15)
                              : const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? c : Colors.white12,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _avatars[i]['emoji'] as String,
                            style:
                                TextStyle(fontSize: selected ? 24 : 20),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 28),

              // ── Identity ──────────────────────────────────────────────────
              _sectionLabel('IDENTITY'),
              _field('Rider Name', _nameCtrl,
                  hint: 'Ghost Rider', capitalization: TextCapitalization.words),
              const SizedBox(height: 12),
              _field('Bike Name', _bikeCtrl,
                  hint: 'e.g. KTM Duke 390',
                  capitalization: TextCapitalization.words),
              const SizedBox(height: 12),

              // Blood type picker
              _label('BLOOD TYPE'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _bloodTypes.map((bt) {
                  final selected = _bloodType == bt;
                  return GestureDetector(
                    onTap: () => setState(() => _bloodType = bt),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFE8003D).withOpacity(0.15)
                            : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFE8003D)
                              : Colors.white12,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        bt,
                        style: TextStyle(
                          color:
                              selected ? const Color(0xFFE8003D) : Colors.white54,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              _field('Allergies / Medical Notes', _allergiesCtrl,
                  hint: 'e.g. Penicillin allergy'),

              const SizedBox(height: 28),

              // ── Emergency Contact ─────────────────────────────────────────
              _sectionLabel('EMERGENCY CONTACT'),
              _field('Contact Name', _emergencyNameCtrl,
                  hint: 'e.g. Mom',
                  capitalization: TextCapitalization.words),
              const SizedBox(height: 12),
              _field('Phone Number', _emergencyPhoneCtrl,
                  hint: '+91-9876543210',
                  keyboardType: TextInputType.phone),

              const SizedBox(height: 28),

              // ── Fuel Settings ─────────────────────────────────────────────
              _sectionLabel('FUEL TRACKER'),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    _sliderRow(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Tank Size',
                      value: _fuelTankL,
                      min: 5,
                      max: 30,
                      unit: 'L',
                      onChanged: (v) => setState(() => _fuelTankL = v),
                    ),
                    const SizedBox(height: 16),
                    _sliderRow(
                      icon: Icons.speed_rounded,
                      label: 'Fuel Efficiency',
                      value: _fuelEfficiencyKmL,
                      min: 10,
                      max: 80,
                      unit: 'km/L',
                      onChanged: (v) =>
                          setState(() => _fuelEfficiencyKmL = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Range: ~${(_fuelTankL * _fuelEfficiencyKmL).round()} km',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Speed Alert ───────────────────────────────────────────────
              _sectionLabel('SPEED ALERT'),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    _sliderRow(
                      icon: Icons.warning_amber_rounded,
                      label: 'Warn me above',
                      value: _speedLimitKmh,
                      min: 60,
                      max: 200,
                      unit: 'km/h',
                      color: const Color(0xFFFFD700),
                      onChanged: (v) => setState(() => _speedLimitKmh = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Colors.white24, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Visual + haptic alert when you exceed ${_speedLimitKmh.round()} km/h',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Helmet QR Preview ─────────────────────────────────────────
              _sectionLabel('HELMET QR'),
              Container(
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
                      'Attach to your helmet. First responders scan this in an emergency.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
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
                          data: _qrData,
                          version: QrVersions.auto,
                          size: 150,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D0D),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Text(
                        _qrData,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.6,
                        ),
                      ),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white24, fontSize: 10, letterSpacing: 3),
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white24, fontSize: 10, letterSpacing: 3),
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String hint = '',
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label.toUpperCase()),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: TextField(
            controller: ctrl,
            textCapitalization: capitalization,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: Colors.white12, fontSize: 15),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() {}), // live QR refresh
          ),
        ),
      ],
    );
  }

  Widget _sliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    Color color = const Color(0xFFE8003D),
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13)),
                  Text(
                    '${value.toStringAsFixed(value >= 10 ? 0 : 1)} $unit',
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: color,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: color,
                  overlayColor: color.withOpacity(0.12),
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
