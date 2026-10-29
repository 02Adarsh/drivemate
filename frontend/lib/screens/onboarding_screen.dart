import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/brand_header.dart';
import '../services/navigation.dart';
import '../widgets/dm_animations.dart';
import '../widgets/slide_to_start.dart';
import 'login_screen.dart';
import 'register_screen.dart';

// Kept exported for backwards compatibility: older screens imported
// `CinematicBackdrop` and `OnboardingScreen` from this file.
export '../widgets/auth_backdrop.dart' show CinematicBackdrop;

/// Three-page introduction, redesigned.
///
/// Page 3 fixes the earlier "slide to get started does nothing" problem:
///   * the PageView is frozen on the last page so its gesture cannot swallow
///     the slide gesture,
///   * the slider itself now accumulates drag deltas and also reacts to a tap,
///   * explicit "Log in" / "Create account" links sit under the slider so
///     nobody depends on finding the gesture.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pager = PageController();
  int _index = 0;

  static final List<_OnboardPage> _pages = [
    const _OnboardPage(
      eyebrow: 'Your car stays yours',
      title: 'Your car.\nYour driver.\nYour rules.',
      body:
          'DriveMate connects you with a driver for the car you already own — not a rented taxi.',
      icon: Icons.directions_car_filled_rounded,
      chips: ['Your vehicle', 'Driver booking'],
      bullets: [
        (Icons.pin_drop_outlined, 'Driver comes to your pickup point'),
        (Icons.timer_outlined, 'Hourly, full day, outstation or airport'),
        (Icons.receipt_long_outlined, 'Clear estimate before you confirm'),
      ],
    ),
    const _OnboardPage(
      eyebrow: 'Driver applications',
      title: 'Trust is earned,\nnever assumed.',
      body:
          'Drivers provide identity and licence documents and complete a safety checklist as part of their application.',
      icon: Icons.verified_user_rounded,
      chips: ['Driver documents', 'Safety checklist'],
      bullets: [
        (Icons.badge_outlined, 'Identity and licence documents submitted for review'),
        (Icons.school_outlined, 'Safety and conduct training checklist'),
        (Icons.pin_outlined, 'Trip PIN verified before the drive starts'),
      ],
    ),
    const _OnboardPage(
      eyebrow: 'Control from start to finish',
      title: 'You are in control\nof every trip.',
      body:
          'Keep track of bookings and access safety information throughout your trip.',
      icon: Icons.route_rounded,
      chips: ['Trip details', 'Safety centre'],
      bullets: [
        (Icons.pin_outlined, 'Trip PIN before the drive starts'),
        (Icons.shield_outlined, 'Emergency contacts and safety information'),
        (Icons.history_rounded, 'Every booking and receipt in one place'),
      ],
    ),
  ];

  void _goToAuth({required bool signup}) {
    Navigator.of(context).pushReplacement(
      dmRoute(signup
          ? const RegisterScreen(role: 'CUSTOMER')
          : const LoginScreen(role: 'CUSTOMER')),
    );
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      backgroundColor: navy,
      body: Stack(
        children: [
          const Positioned.fill(child: CinematicBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 16, 0),
                  child: BrandHeader(
                    markSize: 40,
                    trailing: Row(
                      children: [
                        Text('${_index + 1}/${_pages.length}',
                            style: dmCaption(size: 11)),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => _goToAuth(signup: false),
                          child: Text('Skip',
                              style:
                                  dmCaption(size: 12).copyWith(color: muted)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pager,
                    itemCount: _pages.length,
                    // Frozen on the last page: nothing competes with the slide gesture.
                    physics: isLast
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) =>
                        _PageBody(page: _pages[index]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
                  child: isLast
                      ? Column(
                          children: [
                            SlideToStart(
                              onCompleted: () => _goToAuth(signup: false),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _TextLink(
                                  text: 'New here? Create an account',
                                  onTap: () => _goToAuth(signup: true),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                    width: 1, height: 12, color: hairline),
                                const SizedBox(width: 10),
                                _TextLink(
                                    text: 'Log in',
                                    onTap: () => _goToAuth(signup: false)),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            // Dots
                            ...List.generate(_pages.length, (dot) {
                              final active = dot == _index;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                margin: const EdgeInsets.only(right: 6),
                                width: active ? 26 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: active
                                      ? red
                                      : Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              );
                            }),
                            const Spacer(),
                            if (_index > 0)
                              IconButton(
                                onPressed: () => _pager.previousPage(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                ),
                                icon: Icon(Icons.arrow_back_rounded,
                                    size: 20, color: muted),
                              ),
                            FilledButton(
                              onPressed: () => _pager.nextPage(
                                duration: const Duration(milliseconds: 320),
                                curve: Curves.easeOutCubic,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: red,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(16),
                                minimumSize: const Size(0, 0),
                              ),
                              child: const Icon(Icons.arrow_forward_rounded,
                                  size: 20),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _TextLink({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11.8, fontWeight: FontWeight.w600, color: red),
      ),
    );
  }
}

class _OnboardPage {
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final List<String> chips;
  final List<(IconData, String)> bullets;

  const _OnboardPage({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.chips,
    required this.bullets,
  });
}

class _PageBody extends StatelessWidget {
  final _OnboardPage page;
  const _PageBody({required this.page});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DmEntrance(child: _SceneCard(icon: page.icon, chips: page.chips)),
          const SizedBox(height: 26),
          DmEntrance(
              delay: 70,
              child: Text(page.eyebrow.toUpperCase(), style: dmSectionLabel())),
          const SizedBox(height: 10),
          DmEntrance(
              delay: 120,
              child:
                  Text(page.title, style: dmHeading(size: 34, height: 1.10))),
          const SizedBox(height: 12),
          DmEntrance(
              delay: 170,
              child: Text(page.body, style: dmSubtitle(size: 13.6))),
          const SizedBox(height: 20),
          ...page.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(bullet.$1, size: 16, color: red),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        bullet.$2,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: softWhite.withValues(alpha: 0.86)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustration card: gradient panel, soft glow, main icon and floating chips.
class _SceneCard extends StatelessWidget {
  final IconData icon;
  final List<String> chips;
  const _SceneCard({required this.icon, required this.chips});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      height: 216,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26141A), Color(0xFF14171D)],
        ),
        border: Border.all(color: red.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 14))
        ],
      ),
      child: Stack(
        children: [
          // Glow + dotted route line
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  red.withValues(alpha: 0.30),
                  red.withValues(alpha: 0)
                ]),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _RoutePainter()),
          ),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Icon(icon, size: 44, color: red),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: _Chip(text: chips.first, icon: Icons.check_circle_rounded),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _Chip(text: chips.last, icon: Icons.bolt_rounded),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: red),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: softWhite)),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = red.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.80)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.30,
          size.width * 0.62, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.80, size.height * 0.85,
          size.width * 0.95, size.height * 0.35);

    final dashed = _dashPath(path, dash: 7, gap: 7);
    canvas.drawPath(dashed, paint);

    canvas.drawCircle(
        Offset(size.width * 0.10, size.height * 0.80), 4, Paint()..color = red);
    canvas.drawCircle(Offset(size.width * 0.95, size.height * 0.35), 4,
        Paint()..color = Colors.white70);
  }

  Path _dashPath(Path source, {required double dash, required double gap}) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        dest.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gap;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
