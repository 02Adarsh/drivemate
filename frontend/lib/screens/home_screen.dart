import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/brand_mark.dart';

class HomeScreen extends StatelessWidget {
  final String role, name;
  const HomeScreen({super.key, required this.role, required this.name});

  @override
  Widget build(BuildContext context) {
    final driver = role == 'Driver';
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [BrandMark(size: 44), SizedBox(width: 8), Text('DriveMate', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Hey, ${name.split(' ').first} 👋', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(driver ? 'Your driver journey starts here.' : 'Your car. Your destination. Your driver.', style: const TextStyle(color: muted)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(21),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF341719), Color(0xFF171A20)]),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: red.withOpacity(.22)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(driver ? 'DRIVER APPLICATION' : 'DRIVEMATE', style: const TextStyle(color: red, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 10)),
              const SizedBox(height: 12),
              Text(driver ? 'Complete your driver profile' : 'A professional driver for your own car.', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(driver ? 'Email verified. Next: personal profile, driving details and private document verification.' : 'You are signed in. Your vehicles and booking tools are the next build step.', style: const TextStyle(color: muted, height: 1.5, fontSize: 13)),
              const SizedBox(height: 16),
              const Row(children: [Icon(Icons.verified_rounded, color: red, size: 18), SizedBox(width: 7), Text('Email verified', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))]),
            ]),
          ),
          const SizedBox(height: 17),
          if (driver) ...[
            const _StepCard(title: 'Personal profile', text: 'Photo, date of birth, address, service city and emergency contact.', icon: Icons.badge_outlined),
            const _StepCard(title: 'Driving details', text: 'Licence expiry, experience and driving capabilities.', icon: Icons.directions_car_outlined),
            const _StepCard(title: 'Documents & review', text: 'Private uploads and verification status.', icon: Icons.verified_user_outlined),
          ] else ...[
            const _StepCard(title: 'Add your vehicle', text: 'Add the car you own and want your driver to drive.', icon: Icons.directions_car_outlined),
            const _StepCard(title: 'Book a driver', text: 'Pick a service, location and time.', icon: Icons.event_available_outlined),
          ],
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)), child: const Text('Prototype mode • Live matching, GPS and payments are not active.', style: TextStyle(color: muted, fontSize: 11))),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel, indicatorColor: red.withOpacity(.18), selectedIndex: 0,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: driver ? 'Requests' : 'Bookings'),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String title, text;
  final IconData icon;
  const _StepCard({required this.title, required this.text, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white.withOpacity(.06))),
    child: Row(children: [
      Container(width: 43, height: 43, decoration: BoxDecoration(color: red.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: red)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(text, style: const TextStyle(fontSize: 11, color: muted, height: 1.4))])),
      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: muted),
    ]),
  );
}
