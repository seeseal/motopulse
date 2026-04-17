import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS-style frosted glass card.
/// Wrap any content with this for the glassmorphism effect.
/// Requires a non-solid background (gradient/image) to look correct.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blur;
  final double opacity;
  final Color? borderColor;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.blur = 14,
    this.opacity = 0.07,
    this.borderColor,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(20);
    final bc = borderColor ?? Colors.white.withOpacity(0.12);

    Widget card = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? Colors.white).withOpacity(opacity),
            borderRadius: br,
            border: Border.all(color: bc, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

/// Gradient background scaffold — replaces the flat #080808.
/// Wrap screens or the root widget with this.
class GradientBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;

  const GradientBackground({super.key, required this.child, this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.6, -0.7),
          radius: 1.4,
          colors: colors ?? [
            const Color(0xFF1A0A0E),  // deep red tint top-left
            const Color(0xFF0D0D0D),  // dark centre
            const Color(0xFF080808),  // near black edges
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: child,
    );
  }
}
