import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/brand_mark.dart';
import 'auth_screen.dart';
import 'onboarding_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: CinematicBackdrop()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BrandMark(size: 74),
              const Spacer(),
              const Text('Welcome to\nDriveMate.', style: TextStyle(fontSize: 37, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 10),
              const Text('Choose how you want to continue.', style: TextStyle(color: muted, fontSize: 14)),
              const SizedBox(height: 27),
              const _RoleCard(icon: Icons.person_outline_rounded, title: 'I need a driver', subtitle: 'A professional drives your own car.', role: 'CUSTOMER'),
              const SizedBox(height: 12),
              const _RoleCard(icon: Icons.directions_car_outlined, title: 'I want to drive', subtitle: 'Apply to become a DriveMate driver.', role: 'DRIVER'),
              const SizedBox(height: 12),
              const _RoleCard(icon: Icons.admin_panel_settings_outlined, title: 'Administrator', subtitle: 'Restricted staff sign-in.', role: 'ADMIN'),
              const Spacer(),
              const Center(child: Text('YOUR CAR. YOUR DESTINATION. YOUR DRIVER.', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon; final String title, subtitle, role;
  const _RoleCard({required this.icon, required this.title, required this.subtitle, required this.role});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuthScreen(role: role))),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: const Color(0xCC171A20), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(.09))),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: red.withOpacity(.13), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: red)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: muted, fontSize: 11))])),
        const Icon(Icons.arrow_forward_ios, size: 15, color: red),
      ]),
    ),
  );
}
