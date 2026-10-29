import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../services/vehicle_store.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_screen.dart';
import '../widgets/dm_ui.dart';
import 'booking_detail_screen.dart';
import 'vehicles_screen.dart';
import 'map_picker_screen.dart';

/// BOOK A DRIVER — the full request flow.
///
/// The server creates the request, prices it and enforces ownership. The
/// assigned driver then starts/completes the trip. No GPS dispatch or money
/// collection is claimed by this beta.
class BookDriverScreen extends StatefulWidget {
  final String name;
  final String? initialService;
  final ChosenPlace? initialPickup;
  const BookDriverScreen({
    super.key,
    required this.name,
    this.initialService,
    this.initialPickup,
  });

  @override
  State<BookDriverScreen> createState() => _BookDriverScreenState();
}

class _BookingService {
  final String key; // server service key
  final String label;
  final String caption;
  final String asset;
  final IconData icon;

  const _BookingService(
    this.key,
    this.label,
    this.caption,
    this.asset,
    this.icon,
  );
}

class _BookDriverScreenState extends State<BookDriverScreen> {
  static final List<_BookingService> _services = [
    const _BookingService(
      'BOOK_NOW',
      'Book now',
      'As soon as a driver accepts',
      'assets/images/svc_hourly.jpg',
      Icons.bolt_rounded,
    ),
    const _BookingService(
      'AIRPORT',
      'Airport',
      'Terminal pickup or drop',
      'assets/images/svc_airport.jpg',
      Icons.flight_takeoff_rounded,
    ),
    const _BookingService(
      'HOURLY',
      'Hourly',
      'City package',
      'assets/images/svc_hourly.jpg',
      Icons.timer_outlined,
    ),
    const _BookingService(
      'OUTSTATION',
      'Outstation',
      'One way or round trip',
      'assets/images/svc_outstation.jpg',
      Icons.route_rounded,
    ),
    const _BookingService(
      'GETAWAY',
      'Outstation Getaways',
      'Multi-day driver for your own car',
      'assets/images/svc_outstation.jpg',
      Icons.travel_explore_rounded,
    ),
    const _BookingService(
      'EVENT',
      'Wedding / Event Driver',
      'A driver for a wedding or event in your own car',
      'assets/images/svc_hourly.jpg',
      Icons.celebration_outlined,
    ),
    const _BookingService(
      'CORPORATE',
      'Corporate / Business Driver',
      'Scheduled driver for business trips in your own car.',
      'assets/images/svc_hourly.jpg',
      Icons.business_center_outlined,
    ),
    const _BookingService(
      'FULL_DAY',
      'Full day',
      'Up to 12 hours',
      'assets/images/svc_outstation.jpg',
      Icons.wb_sunny_outlined,
    ),
    const _BookingService(
      'NIGHT',
      'Night drive',
      '10 pm – 6 am',
      'assets/images/svc_night.jpg',
      Icons.nightlight_round,
    ),
  ];

  static final List<int> _durations = [1, 2, 4, 6, 8, 12, 14];

  /// Server-side prices, loaded once. Empty = the review step shows a note
  /// instead of a number (never a made-up price).
  List<Map<String, dynamic>> _pricingRows = const [];

  int _step = 0;
  int _serviceIndex = 0;
  int _durationIndex = 2;
  bool _scheduleLater = false;
  DateTime? _when;
  DateTime? _returnAt;
  final _getawayHours = TextEditingController(text: '8');
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _notes = TextEditingController();
  List<VehicleModel> _vehicles = const [];
  VehicleModel? _vehicle;
  ChosenPlace? _pickupPlace;
  ChosenPlace? _dropPlace;
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _businesses = [];
  List<Map<String, dynamic>> _promos = [];
  Map<String, dynamic>? _person;
  int? _businessId;
  String _promo = '';
  bool _searching = false;
  bool _vehiclesLoading = true;
  String? _vehicleError;
  String? _pricingError;
  final String _requestKey = RidesService.newRequestKey();

  _BookingService get _service => _services[_serviceIndex];
  bool get _isGetaway => _service.key == 'GETAWAY';
  bool get _isEvent => _service.key == 'EVENT';
  bool get _requiresSchedule =>
      _isGetaway || _isEvent || _service.key == 'CORPORATE';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialService;
    if (initial != null) {
      final index = _services.indexWhere(
        (service) => service.label.toLowerCase() == initial.toLowerCase(),
      );
      if (index >= 0) _serviceIndex = index;
      if (_requiresSchedule) _scheduleLater = true;
    }
    _pickupPlace = widget.initialPickup;
    if (_pickupPlace != null) _pickup.text = _pickupPlace!.address;
    _loadVehicles();
    _loadPricing();
    _loadAccountOptions();
  }

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    _notes.dispose();
    _getawayHours.dispose();
    super.dispose();
  }

  Future<void> _loadAccountOptions() async {
    try {
      final people = await HubService.list('contacts');
      final businesses = await HubService.list('business');
      final promos = HubService.rows(await HubService.promotions());
      if (mounted) {
        setState(() {
          _people = people;
          _businesses = businesses;
          _promos = promos
              .where((p) => p['active'] == true && p['used'] != true)
              .toList();
        });
      }
    } on ApiException {
      /* Optional account tools do not invent a default. */
    }
  }

  Future<void> _pickPlace(bool pickup) async {
    final result = await Navigator.of(context).push<ChosenPlace>(
      dmRoute(
        MapPickerScreen(
          title: pickup ? 'Choose pickup' : 'Choose destination',
          initial: pickup ? _pickupPlace : _dropPlace,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (pickup) {
        _pickupPlace = result;
        _pickup.text = result.address;
      } else {
        _dropPlace = result;
        _drop.text = result.address;
      }
    });
  }

  Future<void> _loadVehicles() async {
    try {
      final vehicles = await VehicleStore.sync();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _vehicle = vehicles.isEmpty
            ? null
            : vehicles.firstWhere(
                (v) => v.isDefault,
                orElse: () => vehicles.first,
              );
        _vehiclesLoading = false;
        _vehicleError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _vehiclesLoading = false;
        _vehicleError = error.message;
        _vehicle = null;
      });
    }
  }

  Future<void> _loadPricing() async {
    try {
      final data = await RidesService.pricing();
      final rows = ((data['services'] as List?) ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _pricingRows = rows;
        _pricingError = null;
        _normaliseDuration();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _pricingError = error.message);
    }
  }

  /// Hours for the selected duration chip.
  int get _hours => _isGetaway
      ? (int.tryParse(_getawayHours.text) ?? 0)
      : _durations[_durationIndex];

  /// Fare for the current choices, from the server pricing table.
  int? get _estimate {
    final row = _pricingRows.firstWhere(
      (item) => item['service'] == _service.key,
      orElse: () => {},
    );
    if (row.isEmpty || _hours < 1 || (_isGetaway && _hours > 744)) return null;
    final base = (row['base'] as num?)?.toInt() ?? 0;
    final perHour = (row['per_hour'] as num?)?.toInt() ?? 0;
    final minimum = (row['minimum_hours'] as num?)?.toInt() ?? 1;
    final billable = _hours < minimum ? minimum : _hours;
    final total = base + perHour * billable;
    final promo = _promos.firstWhere(
      (p) => p['code'] == _promo,
      orElse: () => {},
    );
    final off = double.tryParse('${promo['amount'] ?? 0}')?.round() ?? 0;
    return total -
        (off < 0
            ? 0
            : off > total
            ? total
            : off);
  }

  String get _estimateLabel {
    final value = _estimate;
    return value == null ? 'Calculated by the server' : '₹$value';
  }

  /// Minimum total quote, not just the base fee, from the server table.
  String _servicePriceLabel(_BookingService service) {
    final row = _pricingRows.firstWhere(
      (item) => item['service'] == service.key,
      orElse: () => {},
    );
    final base = (row['base'] as num?)?.toInt();
    final perHour = (row['per_hour'] as num?)?.toInt();
    final minimum = (row['minimum_hours'] as num?)?.toInt();
    if (base == null || perHour == null || minimum == null) {
      return _pricingRows.isEmpty
          ? 'Price from the server'
          : 'Unavailable — admin rate not set';
    }
    return 'from ₹${base + perHour * minimum}';
  }

  Map<String, dynamic> get _priceRow => _pricingRows.firstWhere(
    (r) => r['service'] == _service.key,
    orElse: () => {},
  );

  int get _minimumHours => (_priceRow['minimum_hours'] as num?)?.toInt() ?? 1;

  void _normaliseDuration() {
    if (!_isGetaway && _hours < _minimumHours) {
      _durationIndex = _durations.indexWhere((h) => h >= _minimumHours);
      if (_durationIndex < 0) _durationIndex = _durations.length - 1;
    }
  }

  String get _fareExplanation => _priceRow.isEmpty
      ? 'Reconnect to load service pricing.'
      : 'Base ₹${_priceRow['base']} + ₹${_priceRow['per_hour']}/hour × ${_hours}h';

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _priceRow.isNotEmpty;
      case 1:
        if (_isGetaway) {
          final start = _when;
          final end = _returnAt;
          if (start == null || end == null || !start.isAfter(DateTime.now())) {
            return false;
          }
          final startDay = DateTime(start.year, start.month, start.day);
          final endDay = DateTime(end.year, end.month, end.day);
          final minutes = end.difference(start).inMinutes;
          return endDay.isAfter(startDay) &&
              end.isAfter(start) &&
              end.difference(start) <= const Duration(days: 31) &&
              _hours >= 1 &&
              _hours <= 744 &&
              _hours <= (minutes / 60).ceil();
        }
        return _hours >= _minimumHours &&
            (!_scheduleLater || (_when?.isAfter(DateTime.now()) ?? false));
      case 2:
        return _pickupPlace != null &&
            _pickup.text.trim().length >= 4 &&
            (!(_service.key == 'OUTSTATION' || _isGetaway) ||
                (_dropPlace != null && _drop.text.trim().length >= 4));
      case 3:
        return _vehicle?.id != null &&
            !_vehiclesLoading &&
            _vehicleError == null;
      default:
        return _vehicle?.id != null &&
            _pricingRows.isNotEmpty &&
            _pickup.text.trim().length >= 4;
    }
  }

  String get _whenLabel {
    if (!_scheduleLater) return 'As soon as possible';
    return _formatWhen(_when);
  }

  String _formatWhen(DateTime? when) {
    if (when == null) return 'Pick date & time';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final period = when.hour < 12 ? 'AM' : 'PM';
    return '${when.day} ${months[when.month - 1]} ${when.year}, $hour:$minute $period';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when ?? now.add(const Duration(hours: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _when ?? now.add(const Duration(hours: 2)),
      ),
    );
    if (time == null || !mounted) return;
    setState(
      () => _when = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickReturnDateTime() async {
    final start = _when;
    if (start == null) return;
    final first = DateTime(
      start.year,
      start.month,
      start.day,
    ).add(const Duration(days: 1));
    final last = start.add(const Duration(days: 31));
    final proposed = _returnAt;
    final initial =
        proposed != null && !proposed.isBefore(first) && !proposed.isAfter(last)
        ? proposed
        : first;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(proposed ?? start),
    );
    if (time == null || !mounted) return;
    setState(
      () => _returnAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_canContinue) return;
    if (_step < 4) {
      setState(() => _step++);
      return;
    }
    _review();
  }

  void _back() {
    if (_step == 0) {
      goBackOr(context);
      return;
    }
    setState(() => _step--);
  }

  Future<void> _review() async {
    final confirmed = await dmShowSheet<bool>(
      context,
      title: 'Check your request',
      subtitle: 'The server confirms the fare when the booking is created.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: dmSurface(),
            child: Column(
              children: [
                DmInfoRow(
                  label: 'Service',
                  value: _service.label,
                  icon: _service.icon,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'When',
                  value: _whenLabel,
                  icon: Icons.schedule_rounded,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Duration',
                  value: '$_hours hours',
                  icon: Icons.timer_outlined,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Pickup',
                  value: _pickup.text.trim(),
                  icon: Icons.my_location_rounded,
                ),
                if (_isGetaway) ...[
                  Divider(color: dividerSoft, height: 18),
                  DmInfoRow(
                    label: 'Return',
                    value: _formatWhen(_returnAt),
                    icon: Icons.event_available,
                  ),
                ],
                if (_service.key == 'OUTSTATION' || _isGetaway) ...[
                  Divider(color: dividerSoft, height: 18),
                  DmInfoRow(
                    label: 'Drop',
                    value: _drop.text.trim(),
                    icon: Icons.place_outlined,
                  ),
                ],
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Car',
                  value: _vehicle == null
                      ? 'No car added'
                      : '${_vehicle!.displayName} • ${_vehicle!.registration}',
                  icon: Icons.directions_car_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: dmGradientSurface(
              accent: red,
              radius: radiusCard,
              strength: 0.20,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated fare',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _estimate == null
                            ? 'Calculated on the server'
                            : 'Base ₹${_pricingRows.firstWhere((r) => r['service'] == _service.key)['base']} '
                                  '+ ₹${_pricingRows.firstWhere((r) => r['service'] == _service.key)['per_hour']}/hour',
                        style: dmCaption(size: 10.8),
                      ),
                    ],
                  ),
                ),
                Text(
                  _estimateLabel,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          DmInfoBox(
            icon: Icons.verified_user_outlined,
            text:
                'Eligible approved and online drivers see this request immediately, even for future dates. '
                '${_isGetaway ? 'Fuel, tolls, parking and driver stay/food are not included and are paid separately by the customer.' : 'Fuel, tolls, parking and other extras are not included; confirm extras with support.'} '
                'No automatic payment is taken.',
          ),
          const SizedBox(height: 18),
          DmPrimaryButton(
            label: 'Send request to drivers',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _searching = true);

    try {
      final booking = await RidesService.createBooking(
        service: _service.key,
        durationHours: _durationHours,
        pickup: _pickup.text.trim(),
        dropAddress: _drop.text.trim(),
        notes: _notes.text.trim(),
        scheduledAt: _scheduleLater ? _when : null,
        returnAt: _isGetaway ? _returnAt : null,
        vehicleId: _vehicle!.id!,
        requestKey: _requestKey,
        pickupLatitude: _pickupPlace?.latitude,
        pickupLongitude: _pickupPlace?.longitude,
        dropLatitude: _dropPlace?.latitude,
        dropLongitude: _dropPlace?.longitude,
        passengerName: (_person?['name'] ?? '').toString(),
        passengerPhone: (_person?['phone'] ?? '').toString(),
        businessId: _businessId,
        promoCode: _promo,
      );
      if (!mounted) return;
      setState(() => _searching = false);
      await _showCreated(booking);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _searching = false);
      showDmMessage(context, error.message, error: true);
    }
  }

  int get _durationHours => _hours;

  Future<void> _showCreated(BookingModel booking) async {
    final open = await dmShowSheet<bool>(
      context,
      title: 'Request sent to drivers',
      subtitle:
          'Booking #${booking.id} · ₹${booking.estimatedFare.round()} estimate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DmPhotoBand(
            asset: 'assets/images/hero_chauffeur.jpg',
            height: 150,
            label: booking.statusLabel,
            title: 'Eligible online drivers see this',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: dmSurface(),
            child: Column(
              children: [
                DmInfoRow(
                  label: 'Service',
                  value: booking.serviceLabel,
                  icon: Icons.local_taxi_outlined,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Pickup',
                  value: booking.pickup,
                  icon: Icons.my_location_rounded,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Estimate',
                  value: dmMoney(booking.estimatedFare),
                  icon: Icons.currency_rupee_rounded,
                ),
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Car',
                  value: booking.vehicle == null
                      ? '—'
                      : '${booking.vehicle!.displayName} • ${booking.vehicle!.registration}',
                  icon: Icons.directions_car_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const DmStepRow(
            index: 1,
            icon: Icons.send_rounded,
            title: 'Request created',
            body: 'Done - the server stored it and told the online drivers.',
          ),
          const DmStepRow(
            index: 2,
            icon: Icons.person_search_rounded,
            title: 'Waiting for a driver',
            body: 'Open the booking to watch the status change when somebody accepts.',
          ),
          const DmStepRow(
            index: 3,
            icon: Icons.directions_car_filled_rounded,
            title: 'Start and finish',
            body: 'The assigned driver starts and completes the trip in their app.',
            last: true,
          ),
          const SizedBox(height: 16),
          DmPrimaryButton(
            label: 'Open my booking',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Back to home', style: dmCaption(size: 11.8)),
            ),
          ),
        ],
      ),
    );

    if (!mounted || open != true) {
      if (mounted) goBackOr(context);
      return;
    }
    await Navigator.of(context).pushReplacement(
      dmRoute(BookingDetailScreen(bookingId: booking.id, initial: booking)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      scroll: false,
      showBack: true,
      onBack: _back,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 14),
          Expanded(
            child: DmSlideSwitcher(
              child: KeyedSubtree(
                key: ValueKey<int>(_searching ? 99 : _step),
                child: _searching
                    ? _searchingView()
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _stepBody(),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_searching) _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STEP ${_step + 1} OF 5', style: dmSectionLabel()),
        const SizedBox(height: 7),
        Text(
          [
            'What do you need?',
            'When should the driver arrive?',
            'Where should they come?',
            'Which car?',
            'Review',
          ][_step],
          style: dmHeading(size: 22),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? red : panel3,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (i != 4) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(
          children: [
            if (_pricingError != null) ...[
              DmErrorState(
                title: 'Service pricing unavailable',
                message: _pricingError!,
                onRetry: _loadPricing,
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < _services.length; i++) ...[
              _serviceRow(_services[i], i),
              const SizedBox(height: 10),
            ],
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DmSectionLabel('Timing'),
            if (!_requiresSchedule)
              DmOptionRow(
                label: 'Now',
                caption: 'No guaranteed arrival time',
                icon: Icons.bolt_rounded,
                selected: !_scheduleLater,
                onTap: () => setState(() => _scheduleLater = false),
              ),
            if (!_requiresSchedule)
              DmOptionRow(
                label: 'Schedule for later',
                caption: 'Up to 60 days ahead',
                icon: Icons.event_outlined,
                selected: _scheduleLater,
                onTap: () => setState(() => _scheduleLater = true),
              ),
            if (_scheduleLater) ...[
              if (_requiresSchedule) const DmSectionLabel('Start date & time'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: dmSurface(
                    color: panel,
                    border: _when == null
                        ? red.withValues(alpha: 0.5)
                        : hairline,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 19, color: red),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          _whenLabel,
                          style: TextStyle(
                            fontSize: 13.6,
                            fontWeight: FontWeight.w700,
                            color: _when == null ? muted : softWhite,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: muted),
                    ],
                  ),
                ),
              ),
            ],
            if (_isGetaway) ...[
              const SizedBox(height: 12),
              DmOptionRow(
                label: 'Return date & time',
                caption: _when == null
                    ? 'Choose start date first'
                    : _formatWhen(_returnAt),
                icon: Icons.event_available,
                onTap: _when == null ? null : _pickReturnDateTime,
              ),
              const SizedBox(height: 12),
              DmField(
                controller: _getawayHours,
                hint: 'Total driver hours (1–744)',
                icon: Icons.timer_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                helper: 'Enter total driver hours for the whole trip. Not elapsed trip hours.',
              ),
              const SizedBox(height: 8),
              Text(
                'Return must be on a later day, within 31 days. Driver hours cannot exceed trip time.',
                style: dmCaption(size: 11),
              ),
            ],
            if (!_isGetaway) ...[
              const SizedBox(height: 20),
              const DmSectionLabel('How long do you need the driver?'),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (var i = 0; i < _durations.length; i++)
                    if (_durations[i] >= _minimumHours)
                      DmSelectChip(
                        label: '${_durations[i]} hours',
                        selected: _durationIndex == i,
                        onSelected: (_) => setState(() => _durationIndex = i),
                      ),
                ],
              ),
            ],
          ],
        );
      case 2:
        return Column(
          children: [
            DmOptionRow(
              label: 'Choose pickup on map',
              caption: _pickupPlace == null
                  ? 'Required: select a pin or use GPS'
                  : 'Pin selected • ${_pickupPlace!.latitude.toStringAsFixed(4)}, ${_pickupPlace!.longitude.toStringAsFixed(4)}',
              icon: Icons.map_outlined,
              onTap: () => _pickPlace(true),
            ),
            DmField(
              controller: _pickup,
              hint: 'Pickup address — house, sector, landmark',
              icon: Icons.my_location_rounded,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              validator: null,
            ),
            const SizedBox(height: 14),
            DmOptionRow(
              label: 'Choose destination on map',
              caption: (_service.key == 'OUTSTATION' || _isGetaway)
                  ? 'Required for outstation'
                  : 'Optional destination pin',
              icon: Icons.flag_outlined,
              onTap: () => _pickPlace(false),
            ),
            DmField(
              controller: _drop,
              hint: (_service.key == 'OUTSTATION' || _isGetaway)
                  ? 'Destination city'
                  : 'Destination (optional)',
              icon: Icons.place_outlined,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            DmField(
              controller: _notes,
              hint: 'Anything the driver should know (optional)',
              icon: Icons.sticky_note_2_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            const DmInfoBox(
              icon: Icons.location_searching_rounded,
              text: 'Choose pickup and destination on the map. If GPS is unavailable, place the pin manually and enter the address.',
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_vehiclesLoading)
              const Center(child: CircularProgressIndicator())
            else if (_vehicleError != null)
              DmErrorState(
                title: 'Garage not synced',
                message: _vehicleError!,
                onRetry: _loadVehicles,
              )
            else if (_vehicles.isEmpty)
              DmEmptyState(
                icon: Icons.directions_car_outlined,
                title: 'No car in your garage',
                body: 'Add the car a driver will drive. It is saved to your account and syncs across devices.',
                actionLabel: 'Add a car',
                onAction: () async {
                  await Navigator.of(context)
                      .push(dmRoute(const VehiclesScreen()));
                  await _loadVehicles();
                },
              )
            else ...[
              const DmSectionLabel('Choose the car'),
              for (final vehicle in _vehicles) ...[
                DmOptionRow(
                  label: vehicle.displayName,
                  caption:
                      '${vehicle.registration} • ${vehicle.fuelLabel} • ${vehicle.transmissionLabel}',
                  icon: Icons.directions_car_filled_rounded,
                  selected: _vehicle?.id == vehicle.id,
                  onTap: () => setState(() => _vehicle = vehicle),
                ),
              ],
              TextButton.icon(
                onPressed: () async {
                  await Navigator.of(context)
                      .push(dmRoute(const VehiclesScreen()));
                  await _loadVehicles();
                },
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Add another car'),
              ),
            ],
          ],
        );
      default:
        return _reviewBody();
    }
  }

  Widget _reviewBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_people.isNotEmpty) ...[
          DropdownButtonFormField<int>(
            initialValue: (_person?['id'] as int?) ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Who is travelling?'),
            items: [
              const DropdownMenuItem<int>(value: 0, child: Text('Myself')),
              for (final p in _people)
                DropdownMenuItem<int>(
                  value: p['id'] as int,
                  child: Text(
                    p['name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(
              () => _person = id == 0
                  ? null
                  : _people.firstWhere((p) => p['id'] == id),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_businesses.isNotEmpty) ...[
          DropdownButtonFormField<int>(
            initialValue: _businessId ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ride profile'),
            items: [
              const DropdownMenuItem<int>(value: 0, child: Text('Personal')),
              for (final b in _businesses)
                DropdownMenuItem<int>(
                  value: b['id'] as int,
                  child: Text(
                    b['company'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) =>
                setState(() => _businessId = id == 0 ? null : id),
          ),
          const SizedBox(height: 12),
        ],
        if (_promos.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _promo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Promotion'),
            items: [
              const DropdownMenuItem(value: '', child: Text('No promotion')),
              for (final p in _promos)
                DropdownMenuItem(
                  value: p['code'].toString(),
                  child: Text('${p['code']} • INR ${p['amount']} off'),
                ),
            ],
            onChanged: (code) => setState(() => _promo = code ?? ''),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: dmSurface(),
          child: Column(
            children: [
              DmInfoRow(
                label: 'Service',
                value: _service.label,
                icon: _service.icon,
              ),
              Divider(color: dividerSoft, height: 18),
              DmInfoRow(
                label: 'When',
                value: _whenLabel,
                icon: Icons.schedule_rounded,
              ),
              Divider(color: dividerSoft, height: 18),
              DmInfoRow(
                label: 'Driver hours',
                value: '$_hours hours',
                icon: Icons.timer_outlined,
              ),
              if (_isGetaway) ...[
                Divider(color: dividerSoft, height: 18),
                DmInfoRow(
                  label: 'Return',
                  value: _formatWhen(_returnAt),
                  icon: Icons.event_available,
                ),
              ],
              Divider(color: dividerSoft, height: 18),
              DmInfoRow(
                label: 'Pickup',
                value: _pickup.text.trim(),
                icon: Icons.my_location_rounded,
              ),
              Divider(color: dividerSoft, height: 18),
              DmInfoRow(
                label: 'Car',
                value: _vehicle == null
                    ? '—'
                    : '${_vehicle!.displayName} (${_vehicle!.registration})',
                icon: Icons.directions_car_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: dmGradientSurface(
            accent: red,
            radius: radiusCard,
            strength: 0.20,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated fare',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(_fareExplanation, style: dmCaption(size: 10.8)),
                  ],
                ),
              ),
              Text(
                _estimateLabel,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DmInfoBox(
          icon: Icons.info_outline_rounded,
          text: _isGetaway
              ? 'Estimate covers driver hours only. Fuel, tolls, parking and driver stay/food are paid separately by the customer.'
              : 'Estimate covers driver hours only. Fuel, tolls, parking and other extras are not included; confirm extras with support.',
        ),
      ],
    );
  }

  Widget _serviceRow(_BookingService service, int index) {
    final selected = _serviceIndex == index;
    return DmTapScale(
      onTap: () => setState(() {
        _serviceIndex = index;
        if (_requiresSchedule) _scheduleLater = true;
        _normaliseDuration();
      }),
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        height: MediaQuery.textScalerOf(context).scale(96),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(
            color: selected ? red.withValues(alpha: 0.7) : hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Image.asset(
                service.asset,
                fit: BoxFit.cover,
                cacheWidth: 300,
                errorBuilder: (_, __, ___) => Container(color: panel2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          service.icon,
                          size: 15,
                          color: selected ? red : muted,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            service.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      service.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dmCaption(size: 11),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _servicePriceLabel(service),
                      style: dmCaption(size: 10.6).copyWith(color: red),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 19,
                color: selected ? red : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final last = _step == 4;
    return Column(
      children: [
        if (_step == 4) ...[
          Row(
            children: [
              Expanded(
                child: Text('Total estimate', style: dmCaption(size: 12.4)),
              ),
              Text(
                _estimateLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        DmPrimaryButton(
          label: last ? 'Request a driver' : 'Continue',
          onPressed: _canContinue ? _next : null,
        ),
        if (!_canContinue)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              _step == 0
                  ? (_pricingRows.isEmpty
                        ? 'Reconnect to load pricing and continue'
                        : 'Service unavailable until admin enables its rate')
                  : _step == 2
                  ? (_pickupPlace == null
                        ? 'Choose a pickup pin on the map to continue'
                        : _pickup.text.trim().length < 4
                        ? 'Enter a pickup address to continue'
                        : 'Enter the outstation destination')
                  : _step == 3
                  ? 'Choose a car to continue'
                  : (_isGetaway
                        ? 'Choose valid start/return dates and driver hours (1–744)'
                        : 'Choose a future date and time to continue'),
              style: dmCaption(size: 11).copyWith(color: warning),
            ),
          ),
      ],
    );
  }

  Widget _searchingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DmPulse(color: red, size: 14),
          const SizedBox(height: 20),
          Text('Sending your request…', style: dmHeading(size: 20)),
          const SizedBox(height: 8),
          Text(
            'Preparing your request for ${_service.label.toLowerCase()} at ${_pickup.text.trim()}',
            textAlign: TextAlign.center,
            style: dmSubtitle(size: 12.6),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 150,
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: panel3,
            ),
          ),
        ],
      ),
    );
  }
}
