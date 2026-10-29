import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/brand_mark.dart';
import '../widgets/dm_buttons.dart';
import 'session_resume_screen.dart';
import 'onboarding_screen.dart';

/// Branded launch screen. After the animation it either resumes an existing
/// session or shows the introduction pages.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();
    _fade = CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.7, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.8, curve: Curves.easeOutBack)),
    );
    // While the logo animates, work out which backend address actually answers
    // (LAN IP, USB tunnel or emulator). Nobody notices the check, and the first
    // real request then goes straight to a working address instead of failing
    // with "Cannot reach the DriveMate server".
    unawaited(AuthService.detectBaseUrl());
    _timer = Timer(const Duration(milliseconds: 1850), _next);
  }

  Future<void> _next() async {
    final hasSession = await AuthService.hasSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(dmRoute(
      hasSession ? const SessionResumeScreen() : const OnboardingScreen(),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Scaffold(
      backgroundColor: navy,
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBackdrop(child: SizedBox.shrink())),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 96),
                    const SizedBox(height: 22),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1),
                        children: <TextSpan>[
                          TextSpan(
                              text: 'Drive',
                              style: TextStyle(color: softWhite)),
                          const TextSpan(
                              text: 'Mate', style: TextStyle(color: red)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'YOUR CAR. YOUR DESTINATION. YOUR DRIVER.',
                      style: TextStyle(
                        color: softWhite.withValues(alpha: 0.62),
                        fontSize: 9,
                        letterSpacing: 1.7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 34),
                    const DmDemoBadge(),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 42),
              child: FadeTransition(
                opacity: _fade,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Color(0xFF1D2026),
                          color: red,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Booking a driver for the car you own.',
                        style: dmCaption(size: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
