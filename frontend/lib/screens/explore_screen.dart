import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_ui.dart';
import 'book_driver_screen.dart';
import 'safety_screen.dart';

/// Services tab, retaining the old class name for update compatibility.
class ExploreScreen extends StatelessWidget {
  final String name;
  const ExploreScreen({super.key, required this.name});
  static const services = [
    (
      'Book now',
      'A driver for your own car, as soon as available.',
      'assets/images/svc_hourly.jpg',
      Icons.bolt_rounded,
    ),
    (
      'Hourly',
      'Errands, meetings and a driver by the hour.',
      'assets/images/svc_hourly.jpg',
      Icons.schedule_rounded,
    ),
    (
      'Airport',
      'Relax on the pickup or drop in your own car.',
      'assets/images/svc_airport.jpg',
      Icons.flight_takeoff_rounded,
    ),
    (
      'Outstation',
      'Choose destination pins for a longer journey.',
      'assets/images/svc_outstation.jpg',
      Icons.route_rounded,
    ),
    (
      'Outstation Getaways',
      'Plan a multi-day trip with a driver for your own car.',
      'assets/images/svc_outstation.jpg',
      Icons.travel_explore_rounded,
    ),
    (
      'Wedding / Event Driver',
      'A driver for your wedding or event, in your own car.',
      'assets/images/svc_hourly.jpg',
      Icons.celebration_outlined,
    ),
    (
      'Corporate / Business Driver',
      'Scheduled driver for business trips in your own car.',
      'assets/images/svc_hourly.jpg',
      Icons.business_center_outlined,
    ),
    (
      'Pilgrimage Trip',
      'A driver for your pilgrimage, in your own car.',
      'assets/images/svc_outstation.jpg',
      Icons.temple_hindu_outlined,
    ),
    (
      'Shopping / Errands Driver',
      'A driver for shopping and errands in your own car.',
      'assets/images/svc_hourly.jpg',
      Icons.shopping_bag_outlined,
    ),
    (
      'Full day',
      'A longer driver package for your day.',
      'assets/images/svc_outstation.jpg',
      Icons.sunny_snowing,
    ),
    (
      'Night drive',
      'A night-capable verified driver, your vehicle.',
      'assets/images/svc_night.jpg',
      Icons.nightlight_round,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        Text(dmLocal('Services', 'सेवाएं'), style: dmHeading(size: 32)),
        const SizedBox(height: 8),
        Text(
          'Ways to use DriveMate — pick a driver, keep your car.',
          style: dmSubtitle(size: 14),
        ),
        const SizedBox(height: 22),
        const DmPhotoBand(
          asset: 'assets/images/hero_chauffeur.jpg',
          height: 180,
          label: 'YOUR CAR, YOUR CHOICE',
          title: 'A trained driver. Your own car.',
        ),
        const SizedBox(height: 24),
        const DmSectionHeader(title: 'Services'),
        for (final service in services) ...[
          InkWell(
            onTap: () => Navigator.of(context).push(
              dmRoute(BookDriverScreen(name: name, initialService: service.$1)),
            ),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: dmSurface(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(service.$4, size: 18, color: softWhite),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                service.$1,
                                style: dmHeading(size: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(service.$2, style: dmCaption(size: 12)),
                        const SizedBox(height: 12),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: softWhite,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.asset(
                      service.$3,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 13),
        ],
        const SizedBox(height: 10),
        DmListCard(
          icon: Icons.shield_outlined,
          title: 'A safer way to book',
          body: 'Your assigned driver’s phone, mandatory customer PIN, map pickup and cash records.',
          accent: info,
          onTap: () =>
              Navigator.of(context).push(dmRoute(const SafetyScreen())),
        ),
      ],
    );
  }
}
