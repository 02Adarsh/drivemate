import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/foreground_refresh.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_ui.dart';
import 'booking_detail_screen.dart';

/// DRIVER — the live request inbox and the driver's own trips.
///
/// v7: this is no longer a mock. Requests come from
/// `GET /api/rides/requests/` (only while you are approved and online), accept
/// and decline really change the booking, and "My trips" shows the assigned work
/// with a start / complete action.
class DriverRequestsScreen extends StatefulWidget {
  final bool approved;
  final bool online;
  final Future<void> Function(bool)? onToggleOnline;
  const DriverRequestsScreen({
    super.key,
    required this.approved,
    required this.online,
    this.onToggleOnline,
  });

  @override
  State<DriverRequestsScreen> createState() => _DriverRequestsScreenState();
}

class _DriverRequestsScreenState extends State<DriverRequestsScreen>
    with ForegroundRefresh<DriverRequestsScreen> {
  static final List<String> _tabs = ['Open requests', 'My trips'];

  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<BookingModel> _requests = const [];
  BookingList _trips = const BookingList();
  int _busyId = 0;
  bool _refreshing = false;
  bool _reloadQueued = false;
  int _mutationVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
    startForegroundRefresh(() => _load(silent: true));
  }

  @override
  void didUpdateWidget(covariant DriverRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.online != widget.online ||
        oldWidget.approved != widget.approved) {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted || _busyId != 0) return;
    if (_refreshing) {
      if (!silent) _reloadQueued = true;
      return;
    }
    _refreshing = true;
    final version = _mutationVersion;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final trips = await RidesService.trips();
      List<BookingModel> requests = const [];
      if (widget.online && widget.approved) {
        try {
          requests = await RidesService.openRequests();
        } on ApiException catch (error) {
          if (error.statusCode != 403) rethrow;
        }
      }
      if (!mounted || version != _mutationVersion) return;
      setState(() {
        _trips = trips;
        _requests = requests;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || version != _mutationVersion) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } finally {
      _refreshing = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        _load(silent: true);
      }
    }
  }

  Future<void> _accept(BookingModel booking) async {
    _mutationVersion++;
    setState(() => _busyId = booking.id);
    try {
      final accepted = await RidesService.acceptRequest(booking.id);
      if (!mounted) return;
      setState(() => _busyId = 0);
      showDmMessage(
        context,
        '${accepted.customer?.name ?? "The customer"} is now your trip.',
      );
      setState(() {
        _tab = 1;
        _trips = BookingList(
          active: [
            accepted,
            ..._trips.active.where((t) => t.id != accepted.id),
          ],
          past: _trips.past,
        );
        _requests = _requests.where((r) => r.id != accepted.id).toList();
      });
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busyId = 0);
      showDmMessage(context, error.message, error: true);
      await _load();
    }
  }

  Future<void> _decline(BookingModel booking) async {
    _mutationVersion++;
    setState(() => _busyId = booking.id);
    try {
      await RidesService.declineRequest(booking.id);
      if (!mounted) return;
      setState(() => _busyId = 0);
      showDmMessage(context, 'Request hidden from your feed.');
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busyId = 0);
      showDmMessage(context, error.message, error: true);
    }
  }

  Future<void> _open(BookingModel booking) async {
    await Navigator.of(context).push(
      dmRoute(
        BookingDetailScreen(
          bookingId: booking.id,
          initial: booking,
          isDriver: true,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Requests', style: dmHeading(size: 25))),
                  DmPill(
                    label: widget.approved && widget.online
                        ? 'ONLINE'
                        : 'OFFLINE',
                    color: widget.approved && widget.online ? success : muted,
                    solid: widget.approved && widget.online,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Eligible requests. Auto-refreshes every 8 seconds in the foreground.',
                style: dmSubtitle(size: 13),
              ),
              const SizedBox(height: 14),
              DmSegmentTabs(
                tabs: _tabs,
                index: _tab,
                onChanged: (index) {
                  setState(() => _tab = index);
                  _load();
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: red,
            backgroundColor: panel,
            child: _body(),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (!widget.approved) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: const [
          DmListCard(
            icon: Icons.lock_outline_rounded,
            title: 'Locked until approval',
            body:
                'Requests unlock once your documents, training and consents are approved. Check the Home tab '
                'for progress.',
            accent: warning,
          ),
          SizedBox(height: 18),
          DmEmptyState(
            icon: Icons.bolt_outlined,
            title: 'No requests yet',
            body: 'Nothing is simulated here: the feed stays empty until your account is approved.',
          ),
        ],
      );
    }

    if (!widget.online && _tab == 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          DmListCard(
            icon: Icons.power_settings_new_rounded,
            title: 'You are offline',
            body: 'Go online to see and accept requests. The server only offers work to online drivers.',
            accent: warning,
            onTap: () async {
              await widget.onToggleOnline?.call(true);
              await _load();
            },
          ),
          const SizedBox(height: 18),
          if (_trips.active.isNotEmpty) ...[
            const DmSectionHeader(title: 'Your active trip'),
            for (final trip in _trips.active) ...[
              _TripCard(booking: trip, onTap: () => _open(trip)),
              const SizedBox(height: 12),
            ],
          ] else
            const DmEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: 'No active trip',
              body: 'Turn yourself online to start receiving work.',
            ),
        ],
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 50),
          DmErrorState(
            title: 'Could not load your requests',
            message: _error!,
            onRetry: _load,
          ),
        ],
      );
    }

    if (_tab == 1) return _tripsList();
    return _requestsList();
  }

  Widget _requestsList() {
    if (_requests.isEmpty && _trips.active.isNotEmpty) {
      final active = _trips.active.first;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          DmListCard(
            icon: Icons.route_rounded,
            title: 'Finish your active trip',
            body:
                'Booking #${active.id} is ${active.statusLabel.toLowerCase()}. Only one trip at a time is allowed.',
            accent: info,
            onTap: () => _open(active),
          ),
        ],
      );
    }
    if (_requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: const [
          DmEmptyState(
            icon: Icons.radar_rounded,
            title: 'No live requests right now',
            body:
                'A customer request appears here if your driving capabilities match, with the car, the pickup and '
                'the fare the server calculated.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final booking = _requests[index];
        return DmEntrance(delay: index * 40, child: _requestCard(booking));
      },
    );
  }

  Widget _requestCard(BookingModel booking) {
    final busy = _busyId == booking.id;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: dmGradientSurface(
        accent: red,
        radius: radiusCard + 2,
        strength: 0.14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DmAvatar(name: booking.customer?.name ?? 'Customer', size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.customer?.name ?? 'Customer',
                      style: const TextStyle(
                        fontSize: 14.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(booking.serviceLabel, style: dmCaption(size: 11.2)),
                  ],
                ),
              ),
              DmPill(
                label: dmMoney(booking.estimatedFare),
                color: success,
                solid: true,
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (booking.vehicle != null) ...[
            DmInfoRow(
              label: 'Car',
              value:
                  '${booking.vehicle!.displayName} • ${booking.vehicle!.transmissionLabel}',
              icon: Icons.directions_car_outlined,
            ),
            Divider(color: dividerSoft, height: 14),
          ],
          DmInfoRow(
            label: 'Pickup',
            value: booking.pickup,
            icon: Icons.my_location_rounded,
          ),
          Divider(color: dividerSoft, height: 14),
          DmInfoRow(
            label: 'Duration',
            value: '${booking.durationHours} hours',
            icon: Icons.timer_outlined,
          ),
          if (booking.service == 'EVENT' ||
              booking.service == 'CORPORATE' ||
              booking.service == 'ERRANDS' ||
              booking.service == 'PILGRIMAGE') ...[
            Divider(color: dividerSoft, height: 14),
            DmInfoRow(
              label: 'Starts',
              value: booking.scheduledAt == null
                  ? 'As soon as available'
                  : formatRideDateTime(booking.scheduledAt),
              icon: Icons.event,
            ),
            if (booking.dropAddress.isNotEmpty) ...[
              Divider(color: dividerSoft, height: 14),
              DmInfoRow(
                label: 'Destination',
                value: booking.dropAddress,
                icon: Icons.flag_outlined,
              ),
            ],
          ],
          if (booking.service == 'GETAWAY') ...[
            Divider(color: dividerSoft, height: 14),
            DmInfoRow(
              label: 'Destination',
              value: booking.dropAddress,
              icon: Icons.flag_outlined,
            ),
            Divider(color: dividerSoft, height: 14),
            DmInfoRow(
              label: 'Starts',
              value: formatRideDateTime(booking.scheduledAt),
              icon: Icons.event,
            ),
            Divider(color: dividerSoft, height: 14),
            DmInfoRow(
              label: 'Return',
              value: formatRideDateTime(booking.returnAt),
              icon: Icons.event_available,
            ),
            const SizedBox(height: 8),
            Text(
              'Fuel, tolls, parking and driver stay/food are paid separately by customer.',
              style: dmCaption(size: 11),
            ),
          ],
          Divider(color: dividerSoft, height: 14),
          DmInfoRow(
            label: 'You earn',
            value: dmMoney(booking.driverPayout),
            icon: Icons.account_balance_wallet_outlined,
            valueColor: success,
          ),
          if (booking.notes.isNotEmpty) ...[
            Divider(color: dividerSoft, height: 14),
            DmInfoRow(
              label: 'Notes',
              value: booking.notes,
              icon: Icons.sticky_note_2_outlined,
            ),
          ],
          const SizedBox(height: 15),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => _decline(booking),
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => _accept(booking),
                      child: const Text(
                        'Accept request',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tripsList() {
    if (_trips.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: const [
          DmEmptyState(
            icon: Icons.local_taxi_outlined,
            title: 'No trips yet',
            body:
                'Accept a request and the trip moves here: start it when you meet the customer and complete it '
                'when the drive is done.',
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        if (_trips.active.isNotEmpty) ...[
          const DmSectionHeader(title: 'In progress'),
          for (final trip in _trips.active) ...[
            _TripCard(booking: trip, onTap: () => _open(trip)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 10),
        ],
        const DmSectionHeader(title: 'History'),
        if (_trips.past.isEmpty)
          Text(
            'Completed trips will be listed here.',
            style: dmCaption(size: 11.6),
          )
        else
          for (final trip in _trips.past) ...[
            _TripCard(booking: trip, onTap: () => _open(trip), compact: true),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// One assigned trip.
class _TripCard extends StatelessWidget {
  final BookingModel booking;
  final VoidCallback onTap;
  final bool compact;

  const _TripCard({
    required this.booking,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard + 2),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: dmSurface(
          border: booking.statusColor.withValues(alpha: 0.32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(booking.statusIcon, size: 19, color: booking.statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '#${booking.id} · ${booking.customer?.name ?? "Customer"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: DmPill(
                    label: booking.statusLabel,
                    color: booking.statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DmInfoRow(
              label: 'Pickup',
              value: booking.pickup,
              icon: Icons.my_location_rounded,
            ),
            if (!compact) ...[
              Divider(color: dividerSoft, height: 14),
              DmInfoRow(
                label: 'Service',
                value: booking.serviceLabel,
                icon: Icons.local_taxi_outlined,
              ),
              Divider(color: dividerSoft, height: 14),
              DmInfoRow(
                label: 'Payout',
                value: dmMoney(booking.driverPayout),
                icon: Icons.account_balance_wallet_outlined,
                valueColor: success,
              ),
            ],
            if (booking.canStart || booking.canComplete) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap to open the trip controls',
                      style: dmCaption(size: 10.8),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 19, color: muted),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
