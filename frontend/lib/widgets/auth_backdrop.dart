import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Deep-red ambient glow used behind auth screens (kept subtle on purpose).
class RedGlow extends StatelessWidget {
  final Alignment alignment;
  final double size;
  final double opacity;
  const RedGlow(
      {super.key,
      this.alignment = Alignment.bottomRight,
      this.size = 420,
      this.opacity = 0.20});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                red.withValues(alpha: opacity),
                red.withValues(alpha: 0)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain dark background with a soft red glow — used by the login/register
/// screens. No photograph, so the form stays the focus.
///
/// [animate] is off by default: this widget sits behind long forms, and a
/// constantly repainting background is one of the easiest ways to make an app
/// feel slow on a real phone.
class AuthBackdrop extends StatelessWidget {
  final Widget child;
  final bool glowTopRight;
  final bool glowBottomLeft;
  const AuthBackdrop({
    super.key,
    required this.child,
    this.glowTopRight = true,
    this.glowBottomLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: navy),
          if (glowTopRight)
            const RedGlow(
                alignment: Alignment.topRight, size: 320, opacity: 0.15),
          if (glowBottomLeft)
            const RedGlow(
                alignment: Alignment.bottomLeft, size: 380, opacity: 0.12),
          child,
        ],
      ),
    );
  }
}

/// Cinematic night-drive background (onboarding + splash).
///
/// Performance notes:
///   * the photo is decoded once at the size actually needed (`cacheWidth`),
///     not at its full 1376 px height, which cuts decode time and memory;
///   * there is **no** looping animation by default — a constant
///     `Transform.scale` + repaint behind a whole screen was a major source of
///     the "laggy" feeling on device.
class CinematicBackdrop extends StatelessWidget {
  final double dim; // 0 = photo clearly visible, 1 = almost black
  final bool animate;

  const CinematicBackdrop({super.key, this.dim = 0.0, this.animate = false});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final cacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/night_drive.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0, 0.15),
            // Decode once at screen resolution instead of the raw file size.
            cacheWidth: cacheWidth.clamp(320, 1400),
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => ColoredBox(color: navy),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  navy.withValues(alpha: 0.94 + dim * 0.06),
                  navy.withValues(alpha: 0.58 + dim * 0.28),
                  navy.withValues(alpha: 0.98),
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
          ),
          // A single static red wash instead of an animated one.
          ColoredBox(color: red.withValues(alpha: 0.03)),
        ],
      ),
    );
  }
}
