import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  int _selectedAvatar = 0;
  bool _isLoading = false;

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
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rider_name', _nameController.text.trim());
    await prefs.setInt('rider_avatar', _selectedAvatar);
    await prefs.setBool('onboarded', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _nameController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 56),

                  // Logo mark
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE8003D).withOpacity(0.12),
                          border: Border.all(
                              color: const Color(0xFFE8003D).withOpacity(0.5),
                              width: 1),
                        ),
                        child: const Icon(Icons.motorcycle,
                            color: Color(0xFFE8003D), size: 16),
                      ),
                      const SizedBox(width: 10),
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'MOTO',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w300,
                                  color: Colors.white,
                                  letterSpacing: 3),
                            ),
                            TextSpan(
                              text: 'PULSE',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFE8003D),
                                  letterSpacing: 3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 64),

                  const Text(
                    'What do we\ncall you?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w200,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Your name appears on group rides',
                    style: TextStyle(color: Colors.white30, fontSize: 14),
                  ),

                  const SizedBox(height: 48),

                  // Name label
                  const Text(
                    'RIDER NAME',
                    style: TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                        letterSpacing: 3),
                  ),
                  const SizedBox(height: 10),

                  // Name field
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasName
                            ? const Color(0xFFE8003D).withOpacity(0.3)
                            : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Ghost Rider',
                        hintStyle: TextStyle(
                            color: Colors.white12,
                            fontSize: 22,
                            fontWeight: FontWeight.w300),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Avatar label
                  const Text(
                    'PICK YOUR AVATAR',
                    style: TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                        letterSpacing: 3),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_avatars.length, (index) {
                      final isSelected = _selectedAvatar == index;
                      final avatar = _avatars[index];
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedAvatar = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (avatar['color'] as Color).withOpacity(0.15)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? avatar['color'] as Color
                                  : Colors.white.withOpacity(0.06),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              avatar['emoji'] as String,
                              style: TextStyle(
                                  fontSize: isSelected ? 26 : 22),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 44),

                  // Preview card
                  if (hasName) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: (_avatars[_selectedAvatar]['color']
                                      as Color)
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _avatars[_selectedAvatar]['color']
                                    as Color,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _avatars[_selectedAvatar]['emoji'] as String,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nameController.text.trim(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500),
                              ),
                              const Text(
                                'Rider · MotoPulse',
                                style: TextStyle(
                                    color: Colors.white30, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF00C853),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Continue button
                  GestureDetector(
                    onTap: hasName && !_isLoading ? _continue : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: hasName
                            ? const Color(0xFFE8003D)
                            : const Color(0xFF161616),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: hasName
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFE8003D)
                                      .withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white))
                            : Text(
                                "LET'S RIDE",
                                style: TextStyle(
                                  color: hasName
                                      ? Colors.white
                                      : Colors.white24,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
