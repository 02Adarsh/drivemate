import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';
import '../services/foreground_refresh.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../services/rides_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/dm_ui.dart';
import 'map_picker_screen.dart';
import 'payments_support_screen.dart';
import 'direct_upi_payment_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  final int bookingId;
  final BookingModel? initial;
  final bool isDriver;
  const BookingDetailScreen(
      {super.key,
      required this.bookingId,
      this.initial,
      this.isDriver = false});
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen>
    with ForegroundRefresh<BookingDetailScreen> {
  Uint8List? _personPhoto;
  BookingModel? _booking;
  Map<String, dynamic>? _code;
  bool _busy = false,
      _refreshing = false,
      _customer = false,
      _postingLocation = false;
  int _revision = 0;
  String? _error, _locationError;
  StreamSubscription<Position>? _positions;
  DateTime? _lastPost;
  @override
  void initState() {
    super.initState();
    _booking = widget.initial;
    _load();
    startForegroundRefresh(_load);
  }

  @override
  void dispose() {
    _positions?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing || _busy || !mounted) return;
    _refreshing = true;
    final version = _revision;
    try {
      final b = await RidesService.booking(widget.bookingId);
      final u = await AuthService.cachedUser();
      Map<String, dynamic>? code;
      final owner = u?['role'] == 'CUSTOMER' && u?['id'] == b.customer?.id;
      if (owner && b.status == 'ACCEPTED') {
        code = await HubService.startCode(b.id);
      }
      if (_personPhoto == null &&
          (widget.isDriver ? b.customer?.hasPhoto : b.driver?.hasPhoto) ==
              true) {
        try {
          _personPhoto = await AuthService.getPrivateBytes(
              'rides/bookings/${b.id}/photo/?person=${widget.isDriver ? "customer" : "driver"}');
        } on ApiException {/* Avatar initials remain available. */}
      }
      if (!mounted || version != _revision) return;
      setState(() {
        _booking = b;
        _code = code;
        _customer = owner;
        _error = null;
      });
      if (b.isFinished) {
        await _stopLocation();
        if (b.paymentReceived || b.status != 'COMPLETED') {
          stopForegroundRefresh();
        }
      }
    } on ApiException catch (e) {
      if (mounted && version == _revision) setState(() => _error = e.message);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    String otp = '';
    if (action == 'start') {
      final entered = await dmShowSheet<String>(context,
          title: 'Verify customer’s trip code',
          subtitle:
              'Ask the customer for the code in their trip screen/email. Do not start driving before successful verification.',
          child: const _TripCodeForm());
      if (entered == null || !mounted) return;
      otp = entered;
    }
    if (action == 'complete') {
      final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Complete this trip?'),
                  content: const Text(
                      'Confirm only when the drive is finished. Cash is recorded separately after you actually collect it.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Not yet')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Trip is finished'))
                  ]));
      if (yes != true || !mounted) return;
    }
    _revision++;
    setState(() => _busy = true);
    try {
      final b = action == 'accept'
          ? await RidesService.acceptRequest(widget.bookingId)
          : action == 'start'
              ? await RidesService.startTrip(widget.bookingId, otp: otp)
              : await RidesService.completeTrip(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = b;
        _code = null;
      });
      if (b.isFinished) await _stopLocation();
      if (mounted) {
        showDmMessage(
            context,
            action == 'start'
                ? 'Code verified. Trip started.'
                : action == 'complete'
                    ? 'Trip completed. Record cash only after collection.'
                    : 'Request accepted. Ask for the customer’s trip code when you meet.');
      }
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Cancel booking?'),
                content: TextField(
                    controller: reason,
                    maxLength: 240,
                    decoration: const InputDecoration(
                        labelText: 'Reason (at least 3 characters)')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep booking')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Cancel booking'))
                ]));
    final text = reason.text.trim();
    reason.dispose();
    if (yes != true) return;
    if (text.length < 3) {
      if (mounted) {
        showDmMessage(context, 'Enter a cancellation reason.', error: true);
      }
      return;
    }
    _revision++;
    setState(() => _busy = true);
    try {
      final b =
          await RidesService.cancelBooking(widget.bookingId, reason: text);
      if (mounted) setState(() => _booking = b);
      await _stopLocation();
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final value =
          await HubService.startCode(widget.bookingId, regenerate: true);
      if (mounted) setState(() => _code = value);
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dial(String phone) async {
    try {
      await HubService.dial(phone);
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  Future<void> _stopLocation() async {
    await _positions?.cancel();
    _positions = null;
    if (mounted) setState(() {});
  }

  Future<void> _shareLocation() async {
    if (_positions != null) {
      await _stopLocation();
      return;
    }
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Share trip location?'),
                content: const Text(
                    'Your customer can see your GPS updates during this assigned trip. Android shows a foreground-service notification. Sharing stops when the trip ends or you leave this trip screen. Keep the app active for reliable updates; the OS may stop background work.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Not now')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Share location'))
                ]));
    if (yes != true || !mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiException('Turn on phone Location first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiException(
            'Location permission was not granted. Use phone settings to enable it.');
      }
      final LocationSettings settings = defaultTargetPlatform ==
              TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 8),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'DriveMate trip location',
                  notificationText:
                      'Sharing with your assigned customer while this trip screen is active',
                  setOngoing: true))
          : const LocationSettings(
              accuracy: LocationAccuracy.high, distanceFilter: 10);
      _positions = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) async {
        if (_postingLocation || _booking?.isFinished == true) return;
        final now = DateTime.now();
        if (_lastPost != null && now.difference(_lastPost!).inSeconds < 5) {
          return;
        }
        _postingLocation = true;
        try {
          await HubService.location(widget.bookingId, p.latitude, p.longitude);
          _lastPost = now;
          if (mounted) setState(() => _locationError = null);
        } on ApiException catch (e) {
          if (mounted) setState(() => _locationError = e.message);
        } finally {
          _postingLocation = false;
        }
      }, onError: (Object e) {
        if (mounted) {
          setState(() => _locationError =
              'GPS updates stopped. Check location permission/settings.');
        }
      });
      if (mounted) setState(() => _locationError = null);
    } catch (e) {
      if (mounted) {
        setState(() => _locationError = e is ApiException
            ? e.message
            : 'Could not start location sharing.');
      }
    }
  }

  Future<void> _rate() async {
    final b = _booking!;
    final result = await dmShowSheet<Map<String, dynamic>>(context,
        title: 'Rate this trip', child: _RatingForm(initial: b.myRating));
    if (result == null) return;
    try {
      await HubService.rate(
          b.id, result['score'] as int, result['comment'].toString());
      await _load();
      if (mounted) showDmMessage(context, 'Rating saved.');
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  String _time(DateTime? value) {
    if (value == null) return '—';
    final t = value.toLocal();
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final b = _booking;
    return DmScreen(
        showBack: true,
        scroll: false,
        padding: EdgeInsets.zero,
        child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (b == null) ...[
                    if (_error != null)
                      DmErrorState(
                          title: 'Could not load this booking',
                          message: _error!,
                          onRetry: _load)
                    else
                      const Padding(
                          padding: EdgeInsets.all(50),
                          child: Center(child: CircularProgressIndicator()))
                  ] else ...[
                    Row(children: [
                      Expanded(
                          child: Text('Trip #${b.id}',
                              style: dmHeading(size: 28))),
                      DmPill(label: b.serviceLabel, color: info)
                    ]),
                    const SizedBox(height: 14),
                    Container(
                        padding: const EdgeInsets.all(18),
                        decoration: dmSurface(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(b.statusIcon,
                                    color: b.statusColor, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(b.statusLabel,
                                        style: dmHeading(size: 23)))
                              ]),
                              const SizedBox(height: 10),
                              Text(b.statusHint, style: dmSubtitle(size: 12.5)),
                              const SizedBox(height: 16),
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        dmMoney(b.finalFare ?? b.estimatedFare),
                                        style: dmHeading(size: 30))),
                                Text('${b.durationHours} hours',
                                    style: dmCaption(size: 13))
                              ]),
                            ])),
                    if (b.isDemo) ...[
                      const SizedBox(height: 10),
                      const DmDemoBadge(text: 'SAMPLE BOOKING • NOT A REAL TRIP')
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      DmListCard(
                          icon: Icons.cloud_off_outlined,
                          title: 'Last known state',
                          body: _error!,
                          accent: warning,
                          onTap: _load)
                    ],
                    if (_customer && b.status == 'ACCEPTED') ...[
                      const SizedBox(height: 16),
                      Container(
                          padding: const EdgeInsets.all(20),
                          decoration: dmSurface(border: info),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('YOUR TRIP-START CODE',
                                    style: dmSectionLabel()),
                                const SizedBox(height: 10),
                                SelectableText(
                                    (_code?['otp'] ?? 'Loading…').toString(),
                                    style: TextStyle(
                                        color: softWhite,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 6)),
                                const SizedBox(height: 8),
                                Text(
                                    'Share only with your assigned driver when you meet. The driver cannot start the app trip without this code.',
                                    style: dmCaption(size: 12)),
                                if (_code?['expired'] == true)
                                  const Text(
                                      'Expired — regenerate before starting',
                                      style: TextStyle(color: danger)),
                                if (_code?['email_sent'] == true)
                                  Text('Code emailed to your account.',
                                      style: dmCaption(size: 11))
                                else
                                  Text(
                                      'Code is available here; email delivery is not confirmed yet.',
                                      style: dmCaption(size: 11)),
                                TextButton(
                                    onPressed: _busy ? null : _regenerate,
                                    child:
                                        const Text('Regenerate / resend code')),
                              ])),
                    ],
                    if (widget.isDriver && !b.isFinished) ...[
                      const SizedBox(height: 16),
                      if (b.canAccept)
                        DmPrimaryButton(
                            label: 'Accept request',
                            loading: _busy,
                            onPressed: () => _action('accept')),
                      if (b.canStart)
                        DmPrimaryButton(
                            label: 'Start trip',
                            loading: _busy,
                            onPressed: () => _action('start')),
                      if (b.canComplete)
                        DmPrimaryButton(
                            label: 'Complete trip',
                            loading: _busy,
                            onPressed: () => _action('complete')),
                      if (b.hasDriver) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                                onPressed: _shareLocation,
                                icon: Icon(_positions == null
                                    ? Icons.location_searching_rounded
                                    : Icons.location_disabled_outlined),
                                label: Text(_positions == null
                                    ? 'Share live location'
                                    : 'Stop location sharing')))
                      ],
                      if (_locationError != null) ...[
                        const SizedBox(height: 10),
                        DmInfoBox(text: _locationError!, color: warning)
                      ],
                    ],
                    if (b.pickupLatitude != null &&
                        b.pickupLongitude != null) ...[
                      const SizedBox(height: 18),
                      TripMapPanel(
                          latitude: b.pickupLatitude!,
                          longitude: b.pickupLongitude!,
                          driverLatitude:
                              (b.driverLocation?['latitude'] as num?)
                                  ?.toDouble(),
                          driverLongitude:
                              (b.driverLocation?['longitude'] as num?)
                                  ?.toDouble()),
                      const SizedBox(height: 7),
                      Text(
                          b.driverLocation == null
                              ? 'Pickup pin • no driver GPS update shared yet'
                              : 'Driver location last updated ${_time(DateTime.tryParse(b.driverLocation!['updated_at'].toString()))}. Check the time; stale positions are not live movement.',
                          style: dmCaption(size: 10.5)),
                      if (widget.isDriver)
                        TextButton.icon(
                            onPressed: () => HubService.navigate(
                                b.pickupLatitude!, b.pickupLongitude!),
                            icon: const Icon(Icons.navigation_outlined),
                            label: const Text('Open pickup navigation')),
                    ],
                    const SizedBox(height: 20),
                    const DmSectionHeader(title: 'Trip details'),
                    Container(
                        padding: const EdgeInsets.all(15),
                        decoration: dmSurface(),
                        child: Column(children: [
                          DmInfoRow(
                              label: 'Pickup',
                              value: b.pickup,
                              icon: Icons.my_location_rounded),
                          if (b.dropAddress.isNotEmpty)
                            DmInfoRow(
                                label: 'Destination',
                                value: b.dropAddress,
                                icon: Icons.flag_outlined),
                          DmInfoRow(
                              label: 'When',
                              value: b.scheduledAt == null
                                  ? 'As soon as available'
                                  : _time(b.scheduledAt)),
                          if (b.vehicle != null)
                            DmInfoRow(
                                label: 'Your car',
                                value:
                                    '${b.vehicle!.displayName} • ${b.vehicle!.registration}'),
                          if (b.passengerName.isNotEmpty)
                            DmInfoRow(
                                label: 'Traveller', value: b.passengerName),
                          if (b.businessLabel.isNotEmpty)
                            DmInfoRow(label: 'Profile', value: b.businessLabel),
                          if (b.notes.isNotEmpty)
                            DmInfoRow(label: 'Notes', value: b.notes),
                        ])),
                    if (widget.isDriver
                        ? b.customer != null && b.hasDriver
                        : b.driver != null) ...[
                      const SizedBox(height: 20),
                      DmSectionHeader(
                          title: widget.isDriver
                              ? 'Your customer'
                              : 'Your driver'),
                      _person(widget.isDriver ? b.customer! : b.driver!),
                      if (widget.isDriver && b.passengerPhone.isNotEmpty)
                        TextButton.icon(
                            onPressed: () => _dial(b.passengerPhone),
                            icon: const Icon(Icons.call_outlined),
                            label: Text('Call traveller ${b.passengerPhone}')),
                    ],
                    const SizedBox(height: 20),
                    const DmSectionHeader(title: 'Fare & cash'),
                    Container(
                        padding: const EdgeInsets.all(15),
                        decoration: dmSurface(),
                        child: Column(children: [
                          DmInfoRow(
                              label: b.finalFare == null
                                  ? 'Estimated fare'
                                  : 'Final fare',
                              value: dmMoney(b.finalFare ?? b.estimatedFare)),
                          if (b.discountAmount > 0)
                            DmInfoRow(
                                label: 'Promotion',
                                value: '− ${dmMoney(b.discountAmount)}'),
                          DmInfoRow(label: 'Payment', value: b.paymentLabel),
                          DmInfoRow(
                              label: 'Platform share',
                              value: '${b.platformFeePercent}%'),
                          if (widget.isDriver)
                            DmInfoRow(
                                label: 'Net trip ledger',
                                value: dmMoney(b.driverPayout)),
                        ])),
                    if (b.status == 'COMPLETED') ...[
                      if (b.canPayUPI ||
                          (b.canViewUPI && b.upiPayment != null)) ...[
                        const SizedBox(height: 14),
                        DmPrimaryButton(
                            label: widget.isDriver
                                ? 'Show fare QR / review UPI'
                                : 'Pay / view UPI QR',
                            icon: Icons.qr_code_rounded,
                            onPressed: () async {
                              await Navigator.of(context).push(dmRoute(
                                  DirectUPIPaymentScreen(
                                      bookingId: b.id,
                                      isDriver: widget.isDriver)));
                              if (mounted) await _load();
                            })
                      ],
                      const SizedBox(height: 16),
                      DmPrimaryButton(
                          label: b.canConfirmCash
                              ? 'Record cash / open receipt'
                              : 'Open trip receipt',
                          onPressed: () => Navigator.of(context).push(dmRoute(
                              ReceiptScreen(
                                  booking: b, isDriver: widget.isDriver))),
                          icon: Icons.receipt_long_outlined),
                      if (b.canRate) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                                onPressed: _rate,
                                icon: const Icon(Icons.star_outline_rounded),
                                label: Text(b.myRating == null
                                    ? 'Rate this trip'
                                    : 'Edit my rating')))
                      ],
                    ],
                    const SizedBox(height: 20),
                    const DmSectionHeader(title: 'Timeline'),
                    Container(
                        padding: const EdgeInsets.all(15),
                        decoration: dmSurface(),
                        child: Column(children: [
                          for (var i = 0; i < b.events.length; i++)
                            DmStepRow(
                                index: i + 1,
                                icon: b.events[i].icon,
                                title: b.events[i].label,
                                body:
                                    '${_time(b.events[i].at)} • ${b.events[i].note}',
                                last: i == b.events.length - 1),
                        ])),
                    const SizedBox(height: 16),
                    DmListCard(
                        icon: Icons.share_outlined,
                        title: 'Share trip details',
                        body:
                            'Choose who receives the trip number, route and assigned-driver name.',
                        onTap: () => HubService.shareText(
                            'DriveMate trip #${b.id} • ${b.statusLabel}\nDriver: ${b.driver?.name ?? "Not assigned"}\nPickup: ${b.pickup}\nDestination: ${b.dropAddress}\nCar: ${b.vehicle?.displayName ?? "Customer car"}')),
                    const SizedBox(height: 16),
                    DmListCard(
                        icon: Icons.help_outline_rounded,
                        title: 'Help with this trip',
                        body:
                            'Create a support ticket linked to booking #${b.id}.',
                        onTap: () => Navigator.of(context)
                            .push(dmRoute(SupportScreen(bookingId: b.id)))),
                    if (b.canCancel) ...[
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: const Text('Cancel booking',
                              style: TextStyle(color: danger)))
                    ],
                    if (!b.isFinished) ...[
                      const SizedBox(height: 10),
                      const DmInfoBox(
                          text:
                              'Status refreshes every 8 seconds while this screen is visible. No automatic nearest-driver dispatch or guaranteed ETA is claimed.')
                    ],
                  ],
                ])));
  }

  Widget _person(BookingPerson person) => Container(
      padding: const EdgeInsets.all(16),
      decoration: dmSurface(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _personPhoto == null
              ? DmAvatar(name: person.name, size: 46)
              : ClipOval(
                  child: Image.memory(_personPhoto!,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      cacheWidth: 120)),
          const SizedBox(width: 12),
          Expanded(child: Text(person.name, style: dmHeading(size: 18)))
        ]),
        if (person.phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
              onTap: () => _dial(person.phone),
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.call_outlined, color: info),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(person.phone,
                            style: const TextStyle(
                                color: info,
                                fontWeight: FontWeight.w700,
                                fontSize: 17))),
                    const Icon(Icons.open_in_new_rounded, size: 18, color: info)
                  ]))),
          TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: person.phone));
                if (mounted) showDmMessage(context, 'Phone number copied.');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy number'))
        ],
      ]));
}

class _TripCodeForm extends StatefulWidget {
  const _TripCodeForm();
  @override
  State<_TripCodeForm> createState() => _TripCodeFormState();
}

class _TripCodeFormState extends State<_TripCodeForm> {
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(children: [
      DmField(
          controller: _code,
          hint: 'Customer’s 6-digit trip code',
          icon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {})),
      const SizedBox(height: 18),
      DmPrimaryButton(
          label: 'Verify code & start trip',
          onPressed: _code.text.length == 6
              ? () => Navigator.pop(context, _code.text)
              : null),
      const SizedBox(height: 10),
      const DmInfoBox(
          text:
              'Five incorrect guesses lock the code temporarily. The customer can regenerate an expired code. The code is checked on the server, not just in the button.'),
    ]);
  }
}

class _RatingForm extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _RatingForm({this.initial});
  @override
  State<_RatingForm> createState() => _RatingFormState();
}

class _RatingFormState extends State<_RatingForm> {
  late int _score;
  late TextEditingController _comment;
  @override
  void initState() {
    super.initState();
    _score = (widget.initial?['score'] as num?)?.toInt() ?? 5;
    _comment = TextEditingController(
        text: (widget.initial?['comment'] ?? '').toString());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
              onPressed: () => setState(() => _score = i),
              icon: Icon(
                  i <= _score ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: warning,
                  size: 30))
      ]),
      const SizedBox(height: 12),
      DmField(
          controller: _comment,
          hint: 'Feedback (optional)',
          icon: Icons.rate_review_outlined,
          maxLines: 3,
          maxLength: 500),
      const SizedBox(height: 18),
      DmPrimaryButton(
          label: 'Save rating',
          onPressed: () => Navigator.pop(
              context, {'score': _score, 'comment': _comment.text.trim()}))
    ]);
  }
}
