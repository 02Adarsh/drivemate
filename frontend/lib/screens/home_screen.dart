import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/foreground_refresh.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../services/vehicle_store.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_screen.dart';
import '../widgets/dm_ui.dart';
import 'account_screen.dart';
import 'account_tools_screen.dart';
import 'admin_queue_screen.dart';
import 'book_driver_screen.dart';
import 'booking_detail_screen.dart';
import 'bookings_screen.dart';
import 'driver_application_status_screen.dart';
import 'driver_documents_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_requests_screen.dart';
import 'explore_screen.dart';
import 'map_picker_screen.dart';
import 'notifications_screen.dart';
import 'payments_support_screen.dart';
import 'safety_screen.dart';
import 'vehicles_screen.dart';

/// V9 shell: Home / Services / Activity / Account. Data is fetched, never seeded
/// by the UI. Updates poll only while visible/foregrounded.
class HomeScreen extends StatefulWidget {
  final String role, name;
  const HomeScreen({super.key, required this.role, required this.name});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with ForegroundRefresh<HomeScreen> {
  int _tab = 0, _unread = 0;
  bool _loading = true, _refreshing = false, _toggling = false, _online = false;
  String? _error;
  late String _name;
  List<VehicleModel> _cars = [];
  List<Map<String, dynamic>> _places = [];
  BookingList _bookings = const BookingList();
  Map<String, dynamic>? _progress;
  DriverSummaryModel? _summary;
  int? _pending, _approved;
  Map<String, dynamic>? _ops;
  bool get _driver => widget.role == 'Driver';
  bool get _admin => widget.role == 'Admin';
  bool get _isApproved => _progress?['verification_status'] == 'APPROVED';
  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
    startForegroundRefresh(() => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    try {
      final user = await AuthService.cachedUser();
      final count = await RidesService.unreadCount();
      if (_driver) {
        final p = await AuthService.driverApplication();
        final s = await RidesService.summary();
        final trips = await RidesService.trips();
        if (mounted) {
          setState(() {
            _progress = (p['progress'] as Map?)?.cast<String, dynamic>();
            _summary = s;
            _online = s.available;
            _bookings = trips;
          });
        }
      } else if (_admin) {
        final pending =
            await AuthService.adminDrivers(status: 'PENDING_REVIEW');
        final approved = await AuthService.adminDrivers(status: 'APPROVED');
        final ops = await RidesService.adminOverview();
        if (mounted) {
          setState(() {
            _pending = (pending['count'] as num?)?.toInt();
            _approved = (approved['count'] as num?)?.toInt();
            _ops = ops;
          });
        }
      } else {
        final cars = await VehicleStore.sync();
        final bookings = await RidesService.bookings();
        final places = await HubService.list('places');
        if (mounted) {
          setState(() {
            _cars = cars;
            _bookings = bookings;
            _places = places;
          });
        }
      }
      if (mounted) {
        setState(() {
          _name = (user?['name'] ?? widget.name).toString();
          _unread = count;
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
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(dmRoute(page));
    if (mounted) await _load();
  }

  Future<void> _onlineChange(bool wanted) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final online = await RidesService.setAvailability(wanted);
      if (mounted) setState(() => _online = online);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _book([String? service, ChosenPlace? place]) => _open(BookDriverScreen(
      name: _name, initialService: service, initialPickup: place));

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
        backgroundColor: navy,
        body: SafeArea(
            bottom: false,
            child: KeyedSubtree(
                key: ValueKey('v9-${widget.role}-$_tab'), child: _body())),
        bottomNavigationBar: NavigationBar(
            height: 72,
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              setState(() => _tab = i);
              if (i == 0) _load();
            },
            destinations: _destinations()));
  }

  List<NavigationDestination> _destinations() => _admin
      ? [
          NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: dmLocal('Home', 'होम')),
          const NavigationDestination(
              icon: Icon(Icons.verified_user_outlined), label: 'Queue'),
          NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              label: dmLocal('Account', 'अकाउंट')),
        ]
      : _driver
          ? [
              NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: dmLocal('Home', 'होम')),
              const NavigationDestination(
                  icon: Icon(Icons.bolt_outlined), label: 'Requests'),
              const NavigationDestination(
                  icon: Icon(Icons.payments_outlined), label: 'Earnings'),
              NavigationDestination(
                  icon: const Icon(Icons.person_outline_rounded),
                  label: dmLocal('Account', 'अकाउंट')),
            ]
          : [
              NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: dmLocal('Home', 'होम')),
              NavigationDestination(
                  icon: const Icon(Icons.grid_view_rounded),
                  label: dmLocal('Services', 'सेवाएं')),
              NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: dmLocal('Activity', 'गतिविधि')),
              NavigationDestination(
                  icon: const Icon(Icons.person_outline_rounded),
                  label: dmLocal('Account', 'अकाउंट')),
            ];
  Widget _body() {
    if (_admin) {
      if (_tab == 1) return const AdminQueueScreen();
      if (_tab == 2) {
        return AccountScreen(
            role: widget.role, name: _name, progress: _progress);
      }
      return _scroll(_adminHome());
    }
    if (_driver) {
      if (_tab == 1) {
        return DriverRequestsScreen(
            approved: _isApproved,
            online: _online,
            onToggleOnline: _onlineChange);
      }
      if (_tab == 2) return DriverEarningsScreen(approved: _isApproved);
      if (_tab == 3) {
        return AccountScreen(
            role: widget.role, name: _name, progress: _progress);
      }
      return _scroll(_driverHome());
    }
    if (_tab == 1) return ExploreScreen(name: _name);
    if (_tab == 2) return BookingsScreen(name: _name);
    if (_tab == 3) return AccountScreen(role: widget.role, name: _name);
    return _scroll(_customerHome());
  }

  Widget _scroll(List<Widget> items) => RefreshIndicator(
      onRefresh: _load,
      child: ListView(
          key: const ValueKey('home-0'),
          padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: items));
  Widget _header() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const BrandMark(size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text('DriveMate', style: dmHeading(size: 24))),
          IconButton(
              onPressed: () =>
                  DmAppearance.instance.setDark(!DmAppearance.instance.dark),
              icon: Icon(DmAppearance.instance.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined),
              tooltip: 'Light / Dark mode'),
          Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: IconButton(
                  onPressed: () =>
                      _open(NotificationsScreen(role: widget.role)),
                  icon: const Icon(Icons.notifications_none_rounded),
                  tooltip: 'Notifications'))
        ]),
        const SizedBox(height: 19),
        Text('Hello, ${_name.split(' ').first}', style: dmHeading(size: 29)),
        const SizedBox(height: 7),
        Text(
            _driver
                ? 'Your work. Your schedule.'
                : _admin
                    ? 'Platform operations and support'
                    : 'Your car. A professional driver. Wherever the day takes you.',
            style: dmSubtitle(size: 13)),
        if (_error != null) ...[
          const SizedBox(height: 14),
          DmListCard(
              icon: Icons.cloud_off_rounded,
              title: 'Could not sync the dashboard',
              body: _error!,
              accent: warning,
              onTap: _load)
        ],
      ]);
  List<Widget> _customerHome() => [
        _header(),
        const SizedBox(height: 22),
        DmSearchBar(
            hint: 'Where should the driver come?',
            onTap: () => _book(),
            trailing: const Icon(Icons.arrow_forward_rounded),
            icon: Icons.search_rounded),
        const SizedBox(height: 16),
        if (_bookings.active.isNotEmpty) ...[
          _activeCard(_bookings.active.first),
          const SizedBox(height: 20)
        ],
        DmPhotoCard(
            asset: 'assets/images/hero_chauffeur.jpg',
            label: 'Your car. Your choice.',
            title: 'A verified driver for the car you own.',
            body: 'Choose a pickup pin. Your customer code verifies the start.',
            height: 210,
            footer: Row(children: [
              Expanded(
                  child: FilledButton(
                      onPressed: () => _book(),
                      child: const Text('Book a driver'))),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                  onPressed: () => setState(() => _tab = 1),
                  icon: const Icon(Icons.arrow_outward_rounded))
            ])),
        const SizedBox(height: 24),
        DmSectionHeader(
            title: dmLocal('Suggestions', 'सुझाव'),
            action: 'See all',
            onAction: () => setState(() => _tab = 1)),
        Row(children: [
          _serviceTile('Hourly', 'assets/images/svc_hourly.jpg'),
          const SizedBox(width: 10),
          _serviceTile('Airport', 'assets/images/svc_airport.jpg'),
          const SizedBox(width: 10),
          _serviceTile('Outstation', 'assets/images/svc_outstation.jpg')
        ]),
        const SizedBox(height: 24),
        DmSectionHeader(
            title: 'Saved places',
            action: 'Manage',
            onAction: () => _open(const HubCollectionScreen(kind: 'places'))),
        if (_places.isEmpty)
          DmListCard(
              icon: Icons.add_location_alt_outlined,
              title: 'Add home or work',
              body: 'Save map locations for faster booking.',
              onTap: () => _open(const HubCollectionScreen(kind: 'places')))
        else
          for (final p in _places.take(3)) ...[
            DmListCard(
                icon: p['kind'] == 'HOME'
                    ? Icons.home_outlined
                    : Icons.place_outlined,
                title: p['label'].toString(),
                body: p['address'].toString(),
                onTap: () => _book(
                    null,
                    ChosenPlace(
                        address: p['address'].toString(),
                        latitude: double.parse(p['latitude'].toString()),
                        longitude: double.parse(p['longitude'].toString())))),
            const SizedBox(height: 10)
          ],
        const SizedBox(height: 24),
        DmSectionHeader(
            title: 'Your garage',
            action: 'Manage',
            onAction: () => _open(const VehiclesScreen())),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_cars.isEmpty)
          DmEmptyState(
              icon: Icons.garage_outlined,
              title: 'Add your car',
              body:
                  'The driver drives your vehicle. Register its details before booking.',
              actionLabel: 'Add a vehicle',
              onAction: () => _open(const VehiclesScreen()))
        else
          for (final car in _cars.take(2)) ...[
            DmListCard(
                icon: Icons.directions_car_filled_outlined,
                title: car.displayName,
                body:
                    '${car.registration} • ${car.transmissionLabel}${car.isDefault ? ' • Default' : ''}',
                onTap: () => _open(const VehiclesScreen())),
            const SizedBox(height: 10)
          ],
        const SizedBox(height: 22),
        DmListCard(
            icon: Icons.shield_outlined,
            title: 'Safety, built into every trip',
            body:
                'Mandatory start code, driver contact, trusted people and the phone dialer.',
            onTap: () => _open(const SafetyScreen())),
        const SizedBox(height: 14),
        const DmInfoBox(
            icon: Icons.info_outline_rounded,
            text:
                'Maps use OpenStreetMap. Pay cash after the trip. GPS sharing requires driver consent/permission; a stale location is labelled, never animated as live.'),
      ];
  Widget _serviceTile(String label, String asset) => Expanded(
      child: InkWell(
          onTap: () => _book(label),
          borderRadius: BorderRadius.circular(18),
          child: Container(
              decoration: dmSurface(),
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(asset,
                            height: 65,
                            width: double.infinity,
                            fit: BoxFit.cover)),
                    const SizedBox(height: 10),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: softWhite,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    const SizedBox(height: 5),
                    const Icon(Icons.arrow_forward_rounded, size: 17),
                  ]))));
  Widget _activeCard(BookingModel b) => DmListCard(
      icon: b.statusIcon,
      title: b.status == 'ACCEPTED'
          ? 'Your driver accepted • view start code'
          : b.statusLabel,
      body: '#${b.id} • ${b.serviceLabel} • ${b.pickup}',
      accent: b.statusColor,
      onTap: () => _open(
          BookingDetailScreen(bookingId: b.id, initial: b, isDriver: _driver)));
  List<Widget> _driverHome() => [
        _header(),
        const SizedBox(height: 20),
        DmOnlineToggle(
            online: _online,
            locked: !_isApproved,
            onChanged: _toggling ? null : _onlineChange,
            onlineNote:
                'Requests match your capabilities. No nearest-driver dispatch is claimed.',
            lockedNote: 'Finish verification before accepting work.'),
        if (_bookings.active.isNotEmpty) ...[
          const SizedBox(height: 14),
          _activeCard(_bookings.active.first)
        ],
        const SizedBox(height: 20),
        const DmSectionHeader(title: 'Your application'),
        DmPhotoCard(
            asset: 'assets/images/driver_hero.jpg',
            label: 'Professional driver',
            title: _isApproved
                ? 'You are approved'
                : (_progress?['verification_status_label'] ??
                        'Finish your application')
                    .toString(),
            body:
                'Documents, training and consents are reviewed separately from your online/offline availability.',
            height: 190,
            footer: FilledButton(
                onPressed: () =>
                    _open(DriverApplicationStatusScreen(name: _name)),
                child: const Text('View status'))),
        const SizedBox(height: 24),
        DmSectionHeader(
            title: 'Today',
            action: 'Earnings',
            onAction: () => setState(() => _tab = 2)),
        Row(children: [
          Expanded(
              child: DmStatTile(
                  label: 'Earnings',
                  value: _summary == null ? '—' : dmMoney(_summary!.today),
                  icon: Icons.payments_outlined,
                  note: 'Trip ledger',
                  accent: success)),
          const SizedBox(width: 10),
          Expanded(
              child: DmStatTile(
                  label: 'Requests',
                  value: _summary == null ? '—' : '${_summary!.openRequests}',
                  icon: Icons.bolt_outlined,
                  note: 'Eligible while online')),
          const SizedBox(width: 10),
          Expanded(
              child: DmStatTile(
                  label: 'Trips',
                  value: _summary == null ? '—' : '${_summary!.completedTrips}',
                  icon: Icons.flag_outlined,
                  note: 'Completed',
                  accent: info))
        ]),
        const SizedBox(height: 22),
        const DmSectionHeader(title: 'Quick actions'),
        Row(children: [
          Expanded(
              child: DmActionTile(
                  icon: Icons.bolt_outlined,
                  label: 'Requests',
                  caption: 'Accept real requests',
                  onTap: () => setState(() => _tab = 1))),
          const SizedBox(width: 10),
          Expanded(
              child: DmActionTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Cash & receipts',
                  caption: 'Record and share',
                  onTap: () => _open(const PaymentsScreen(isDriver: true))))
        ]),
        const SizedBox(height: 12),
        DmListCard(
            icon: Icons.folder_shared_outlined,
            title: 'Documents & training',
            body: 'Keep your licence and verification documents current.',
            onTap: () => _open(DriverDocumentsScreen(name: _name))),
        const SizedBox(height: 12),
        DmListCard(
            icon: Icons.shield_outlined,
            title: 'Safety centre',
            body: 'Emergency dialer and trusted contacts.',
            onTap: () => _open(const SafetyScreen())),
        const SizedBox(height: 16),
        const DmInfoBox(
            text:
                'Start requires the customer’s code. Collect cash only after the trip; record it only after actually receiving it. No automated bank payout is performed.'),
      ];
  List<Widget> _adminHome() => [
        _header(),
        const SizedBox(height: 22),
        Text('Verification is live', style: dmHeading(size: 25)),
        const SizedBox(height: 12),
        DmListCard(
            icon: Icons.verified_user_outlined,
            title: 'Driver verification queue',
            body: 'Review documents, training, consents and applications.',
            onTap: () => setState(() => _tab = 1)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: DmStatTile(
                  label: 'Pending review',
                  value: _pending?.toString() ?? '—',
                  icon: Icons.hourglass_top_rounded,
                  accent: warning)),
          const SizedBox(width: 10),
          Expanded(
              child: DmStatTile(
                  label: 'Approved',
                  value: _approved?.toString() ?? '—',
                  icon: Icons.verified_rounded,
                  accent: success))
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: DmStatTile(
                  label: 'Open requests',
                  value: _ops?['open_requests']?.toString() ?? '—',
                  icon: Icons.radar_rounded)),
          const SizedBox(width: 10),
          Expanded(
              child: DmStatTile(
                  label: 'Active trips',
                  value: _ops?['active_trips']?.toString() ?? '—',
                  icon: Icons.route_outlined,
                  accent: info))
        ]),
        const SizedBox(height: 22),
        DmListCard(
            icon: Icons.receipt_long_outlined,
            title: 'Booking operations',
            body: 'Inspect actual bookings, states and timeline.',
            onTap: () => _open(DmScreen(
                showBack: true,
                scroll: false,
                padding: EdgeInsets.zero,
                child: BookingsScreen(name: _name, isAdmin: true)))),
        const SizedBox(height: 12),
        DmListCard(
            icon: Icons.forum_outlined,
            title: 'Support inbox',
            body: 'Read customer/driver tickets, reply, close or reopen.',
            onTap: () => _open(const SupportScreen())),
        const SizedBox(height: 16),
        const DmInfoBox(
            text:
                'Promotions are managed by your team.'),
      ];
}
