import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import 'onboarding_screen.dart';
import '../widgets/brand_header.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Role gateway.
///
/// The normal path is: introduction pages -> login/register with a Rider or
/// Driver switch. This screen still exists because the administrator account
/// signs in from here (admin accounts are created by staff, never by public
/// signup).
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      backFallback: const OnboardingScreen(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandHeader(markSize: 44),
          const SizedBox(height: 30),
          Text('Continue as', style: dmHeading(size: 27)),
          const SizedBox(height: 7),
          Text('Choose the account type you want to open.',
              style: dmSubtitle(size: 13.2)),
          const SizedBox(height: 24),
          _RoleCard(
            icon: Icons.directions_car_outlined,
            title: 'I need a driver',
            subtitle: 'A verified professional drives the car you own.',
            onLogin: () => Navigator.of(context)
                .pushReplacement(dmRoute(const LoginScreen(role: 'CUSTOMER'))),
            onRegister: () => Navigator.of(context).pushReplacement(
                dmRoute(const RegisterScreen(role: 'CUSTOMER'))),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.person_pin_circle_outlined,
            title: 'I want to drive',
            subtitle: 'Apply to become a DriveMate driver.',
            onLogin: () => Navigator.of(context)
                .pushReplacement(dmRoute(const LoginScreen(role: 'DRIVER'))),
            onRegister: () => Navigator.of(context)
                .pushReplacement(dmRoute(const RegisterScreen(role: 'DRIVER'))),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Administrator',
            subtitle: 'Restricted staff access. No public signup.',
            onLogin: () => Navigator.of(context)
                .pushReplacement(dmRoute(const LoginScreen(role: 'ADMIN'))),
          ),
          const SizedBox(height: 22),
          const DmInfoBox(
            icon: Icons.lock_outline_rounded,
            text: 'Administrator accounts are created on the server with '
                '"python manage.py createsuperuser". The app never grants admin access by itself.',
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onLogin;
  final VoidCallback? onRegister;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onLogin,
    this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: red, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: dmCaption(size: 11.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLogin,
                  child: const Text('Log in'),
                ),
              ),
              if (onRegister != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onRegister,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                    child: const Text('Create account'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
