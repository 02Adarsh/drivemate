import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Full-bleed night-drive banner used on the login screen.
///
/// The image fades into the background at the top and bottom, so the header
/// above and the form below stay readable. It is decoded once at screen width
/// (`cacheWidth`) so it never slows the first frame.
class HeroBand extends StatelessWidget {
  final double height;
  const HeroBand({super.key, this.height = 165});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final width = MediaQuery.sizeOf(context).width;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(320, 1400);

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/night_drive.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, 0.15),
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => ColoredBox(color: panel),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    navy,
                    navy.withValues(alpha: 0.35),
                    navy.withValues(alpha: 0.15),
                    navy,
                  ],
                  stops: const [0, 0.28, 0.62, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
