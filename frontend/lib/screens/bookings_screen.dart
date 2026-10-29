import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_ui.dart';
import 'book_driver_screen.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatefulWidget {
  final String name;
  final bool isAdmin;
  const BookingsScreen({super.key, required this.name, this.isAdmin = false});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  BookingList _data = const BookingList();
  bool _loading = true;
  String? _error;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await RidesService.bookings();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(BookingModel b) async {
    await Navigator.of(context)
        .push(dmRoute(BookingDetailScreen(bookingId: b.id, initial: b)));
    if (mounted) await _load();
  }

  String _date(DateTime? date) {
    if (date == null) return 'Now';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final items = _tab == 0 ? _data.active : _data.past;
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            children: [
              Row(children: [
                Expanded(
                    child: Text(
                        widget.isAdmin ? 'Booking operations' : 'Your activity',
                        style: dmHeading(size: 30))),
                if (!widget.isAdmin)
                  IconButton(
                      onPressed: () => Navigator.of(context)
                          .push(dmRoute(BookDriverScreen(name: widget.name))),
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Book a driver')
              ]),
              const SizedBox(height: 9),
              Text(
                  'Live requests, trip details, cash receipts and your history.',
                  style: dmSubtitle(size: 13)),
              const SizedBox(height: 20),
              DmSegmentTabs(tabs: [
                dmLocal('Upcoming & live', 'आगामी और चालू'),
                dmLocal('Past', 'पुरानी यात्राएं')
              ], index: _tab, onChanged: (i) => setState(() => _tab = i)),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                DmErrorState(
                    title: 'Could not load your bookings',
                    message: _error!,
                    onRetry: _load)
              else if (items.isEmpty)
                DmEmptyState(
                    icon: _tab == 0
                        ? Icons.event_available_outlined
                        : Icons.history_rounded,
                    title: _tab == 0 ? 'No active booking' : 'No past trips',
                    body: _tab == 0
                        ? 'Choose a driver package and a map pickup. Your request and assigned driver appear here.'
                        : 'Completed and cancelled trips will be listed here, newest first.',
                    actionLabel: widget.isAdmin ? null : 'Book a driver',
                    onAction: widget.isAdmin
                        ? null
                        : () => Navigator.of(context)
                            .push(dmRoute(BookDriverScreen(name: widget.name))))
              else
                for (final b in items) ...[
                  InkWell(
                      onTap: () => _open(b),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: dmSurface(),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                          color: panel2,
                                          borderRadius:
                                              BorderRadius.circular(15)),
                                      child: Icon(
                                          Icons.directions_car_filled_rounded,
                                          color: softWhite,
                                          size: 26)),
                                  const SizedBox(width: 13),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(b.serviceLabel,
                                            style: dmHeading(size: 18)),
                                        const SizedBox(height: 4),
                                        Text(
                                            _date(b.scheduledAt ?? b.createdAt),
                                            style: dmCaption(size: 10.5))
                                      ])),
                                  const SizedBox(width: 8),
                                  Text(dmMoney(b.finalFare ?? b.estimatedFare),
                                      style: TextStyle(
                                          color: softWhite,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800))
                                ]),
                                const SizedBox(height: 13),
                                Text(b.pickup,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: dmSubtitle(size: 12.5)),
                                const SizedBox(height: 12),
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  DmPill(
                                      label: b.statusLabel,
                                      color: b.statusColor),
                                  if (b.status == 'COMPLETED')
                                    DmPill(
                                        label: b.paymentLabel,
                                        color: b.paymentReceived
                                            ? success
                                            : warning)
                                ]),
                                if (b.driver != null) ...[
                                  const SizedBox(height: 11),
                                  Text('Driver: ${b.driver!.name}',
                                      style: dmCaption(size: 11))
                                ],
                                if (b.status == 'ACCEPTED') ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                      'Open trip to view your start code',
                                      style: TextStyle(
                                          color: info,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12))
                                ],
                              ]))),
                  const SizedBox(height: 13),
                ],
            ]));
  }
}
