import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_ui.dart';
import 'booking_detail_screen.dart';

/// DRIVER — Earnings, from real completed trips.
///
/// v7: every number here is calculated by the server from bookings this driver
/// actually finished (`GET /api/rides/summary/`). With no trips the chart is
/// genuinely empty - the screen never invents data.
class DriverEarningsScreen extends StatefulWidget {
  final bool approved;
  const DriverEarningsScreen({super.key, required this.approved});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  DriverSummaryModel? _summary;
  BookingList _trips = const BookingList();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await RidesService.summary();
      final trips = await RidesService.trips();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _trips = trips;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final summary = _summary;
    final completedTrips =
        _trips.past.where((t) => t.status == 'COMPLETED').toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: red,
      backgroundColor: panel,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        children: [
          Row(
            children: [
              Expanded(child: Text('Earnings', style: dmHeading(size: 25))),
              if (summary != null && summary.available)
                const DmPill(label: 'ONLINE', color: success, solid: true),
            ],
          ),
          const SizedBox(height: 5),
          Text('Calculated from your completed trips.',
              style: dmSubtitle(size: 13)),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            DmErrorState(
                title: 'Could not load earnings',
                message: _error!,
                onRetry: _load)
          else if (summary != null)
            ...dmStagger([
              if (summary.isDemo)
                const DmDemoBadge(text: 'SAMPLE ACCOUNT • NOT REAL EARNINGS'),
              Container(
                padding: const EdgeInsets.all(18),
                decoration:
                    dmGradientSurface(accent: red, radius: 24, strength: 0.22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('THIS WEEK',
                              style: TextStyle(
                                  fontSize: 10.3,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                  color: red)),
                        ),
                        DmPill(
                          label: widget.approved
                              ? '${summary.completedTrips} TRIPS'
                              : 'LOCKED',
                          color: widget.approved ? success : warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(dmMoney(summary.week),
                        style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            height: 1.0)),
                    const SizedBox(height: 6),
                    Text(
                      widget.approved
                          ? (summary.completedTrips == 0
                              ? 'No completed trips yet. Your first payout lands after the first finished trip.'
                              : 'After the ${summary.platformFeePercent}% platform fee. Lifetime ${dmMoney(summary.lifetime)}.')
                          : 'Earnings start after your application is approved.',
                      style: dmSubtitle(size: 12.4),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: dividerSoft, height: 1),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                            child: _Mini(
                                label: 'Today', value: dmMoney(summary.today))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Mini(
                                label: 'This week',
                                value: dmMoney(summary.week))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Mini(
                                label: 'Lifetime',
                                value: dmMoney(summary.lifetime))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const DmSectionHeader(title: 'Last 7 days (payout)'),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                decoration: dmSurface(),
                child: Column(
                  children: [
                    DmBarChart(
                      values: summary.barValues.isEmpty
                          ? [0, 0, 0, 0, 0, 0, 0]
                          : summary.barValues,
                      labels: summary.barLabels.isEmpty
                          ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                          : summary.barLabels,
                      height: 128,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      summary.completedTrips == 0
                          ? 'Bars stay empty until a trip is completed and recorded. No money is transferred by this build.'
                          : 'Payout per day, after the ${summary.platformFeePercent}% platform fee.',
                      style: dmCaption(size: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const DmSectionHeader(title: 'Right now'),
              Row(
                children: [
                  Expanded(
                    child: DmStatTile(
                      label: 'Open requests',
                      value: '${summary.openRequests}',
                      note: 'Visible to online drivers',
                      icon: Icons.bolt_outlined,
                      accent: red,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: DmStatTile(
                      label: 'Active trips',
                      value: '${summary.activeTrips}',
                      note: 'Accepted or running',
                      icon: Icons.directions_car_filled_rounded,
                      accent: info,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const DmSectionHeader(title: 'How you get paid'),
              const DmStepRow(
                index: 1,
                icon: Icons.receipt_long_outlined,
                title: 'Trip ends',
                body:
                    'Complete the trip in the app to see the final fare.',
              ),
              DmStepRow(
                index: 2,
                icon: Icons.percent_rounded,
                title: 'Platform fee ${summary.platformFeePercent}%',
                body:
                    'The fee is calculated from the fare and shown in the breakdown. It is not automatically collected.',
              ),
              const DmStepRow(
                index: 3,
                icon: Icons.account_balance_outlined,
                title: 'Payout',
                body:
                    'The amounts shown are calculations, not proof of a bank transfer. UPI payments go directly to the driver and are confirmed manually.',
                last: true,
              ),
              const SizedBox(height: 20),
              const DmSectionHeader(title: 'Completed trips'),
              if (completedTrips.isEmpty)
                const DmEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No completed trips yet',
                  body:
                      'Finished trips with their fares appear here, newest first.',
                )
              else
                for (final trip in completedTrips) ...[
                  DmTapScale(
                    onTap: () => Navigator.of(context).push(
                      dmRoute(BookingDetailScreen(
                          bookingId: trip.id, initial: trip, isDriver: true)),
                    ),
                    borderRadius: BorderRadius.circular(radiusCard),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: dmSurface(),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.check_circle_rounded,
                                size: 19, color: success),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('#${trip.id} · ${trip.serviceLabel}',
                                    style: const TextStyle(
                                        fontSize: 13.2,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(trip.pickup,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: dmCaption(size: 10.9)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(dmMoney(trip.driverPayout),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: success)),
                              Text('payout', style: dmCaption(size: 9.8)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              const SizedBox(height: 18),
              const DmInfoBox(
                icon: Icons.info_outline_rounded,
                text:
                    'Cash and direct UPI payments are recorded manually. The platform fee and driver share shown here are calculated amounts, not automatic transfers.',
              ),
            ]),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final String value;
  const _Mini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: dmCaption(size: 10.6)),
      ],
    );
  }
}
