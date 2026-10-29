import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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
import 'direct_upi_payment_screen.dart';
import 'driver_upi_screen.dart';

class PaymentsScreen extends StatefulWidget {
  final bool isDriver;
  const PaymentsScreen({super.key, this.isDriver = false});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List<BookingModel> _trips = [];
  bool _loading = true;
  String? _error;
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
          _trips = data.past.where((b) => b.status == 'COMPLETED').toList();
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

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final received = _trips
        .where((b) => b.paymentReceived)
        .fold<double>(0, (sum, b) => sum + (b.finalFare ?? b.estimatedFare));
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dmLocal('Payments & receipts', 'भुगतान और रसीद'),
              style: dmHeading(size: 28)),
          if (widget.isDriver) ...[
            const SizedBox(height: 16),
            DmListCard(
                icon: Icons.qr_code_rounded,
                title: 'Receiving UPI & QR settings',
                body:
                    'Save your own receiving ID and matching QR image. Fare QRs are generated automatically from the server amount.',
                onTap: () => Navigator.of(context)
                    .push(dmRoute(const DriverUPIScreen())))
          ],
          const SizedBox(height: 18),
          Container(
              padding: const EdgeInsets.all(20),
              decoration: dmSurface(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.payments_outlined, size: 32),
                    const SizedBox(height: 14),
                    Text('Pay after trip', style: dmHeading(size: 22)),
                    const SizedBox(height: 7),
                    Text(
                        'Cash or personal UPI • no card wallet or automatic bank charge',
                        style: dmCaption(size: 12)),
                    const SizedBox(height: 16),
                    Text(dmMoney(received), style: dmHeading(size: 30)),
                    Text(
                        'Payments manually recorded as received across completed trips',
                        style: dmCaption())
                  ])),
          const SizedBox(height: 18),
          const DmInfoBox(
              text:
                  'Cash/direct UPI is manually confirmed by the assigned driver after checking actual receipt. A QR scan, app return, typed reference or screenshot is not bank verification. This is not a wallet balance.'),
          const SizedBox(height: 22),
          DmSectionHeader(
              title: 'Trip receipts', action: 'Refresh', onAction: _load),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            DmErrorState(
                title: 'Could not load payments',
                message: _error!,
                onRetry: _load)
          else if (_trips.isEmpty)
            const DmEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No completed trips',
                body:
                    'Your completed-trip receipts and cash status appear here.')
          else
            for (final b in _trips) ...[
              DmListCard(
                  icon: Icons.receipt_long_outlined,
                  title: '#${b.id} • ${b.serviceLabel}',
                  body:
                      '${dmMoney(b.finalFare ?? b.estimatedFare)} • ${b.paymentLabel}',
                  accent: b.paymentReceived ? success : warning,
                  onTap: () async {
                    await Navigator.of(context).push(dmRoute(
                        ReceiptScreen(booking: b, isDriver: widget.isDriver)));
                    await _load();
                  }),
              const SizedBox(height: 11)
            ],
        ]));
  }
}

class ReceiptScreen extends StatefulWidget {
  final BookingModel booking;
  final bool isDriver;
  const ReceiptScreen(
      {super.key, required this.booking, this.isDriver = false});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late BookingModel _booking;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  Future<void> _action(
      Future<void> Function() action, String successMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      final b = await RidesService.booking(_booking.id);
      if (mounted) {
        setState(() => _booking = b);
        showDmMessage(context, successMessage);
      }
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showDmMessage(
            context, 'The phone could not open the share sheet. Please retry.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upi() async {
    await Navigator.of(context).push(dmRoute(DirectUPIPaymentScreen(
        bookingId: _booking.id, isDriver: widget.isDriver)));
    if (!mounted) return;
    try {
      final b = await RidesService.booking(_booking.id);
      if (mounted) setState(() => _booking = b);
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  Future<void> _cash() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Cash actually received?'),
                content: Text(
                    'Confirm only after collecting ${dmMoney(_booking.finalFare ?? _booking.estimatedFare)}. Your customer is notified and the receipt records your confirmation.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Not yet')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('I received cash'))
                ]));
    if (yes == true) {
      await _action(
          () => HubService.cashReceived(_booking.id), 'Cash receipt recorded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final b = _booking;
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trip receipt', style: dmHeading(size: 28)),
          const SizedBox(height: 7),
          Text('DriveMate #${b.id}', style: dmCaption(size: 13)),
          const SizedBox(height: 22),
          Text(dmMoney(b.finalFare ?? b.estimatedFare),
              style: dmHeading(size: 42)),
          const SizedBox(height: 10),
          DmPill(
              label: b.paymentBadge,
              color: b.paymentReceived ? success : warning),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: dmSurface(),
              child: Column(children: [
                DmInfoRow(label: 'Service', value: b.serviceLabel),
                DmInfoRow(label: 'Duration', value: '${b.durationHours} hours'),
                DmInfoRow(label: 'Pickup', value: b.pickup),
                DmInfoRow(label: 'Driver', value: b.driver?.name ?? '—'),
                DmInfoRow(
                    label: 'Car',
                    value: b.vehicle?.displayName ?? 'Customer car'),
                DmInfoRow(label: 'Discount', value: dmMoney(b.discountAmount)),
                if (b.businessLabel.isNotEmpty)
                  DmInfoRow(label: 'Business', value: b.businessLabel)
              ])),
          const SizedBox(height: 20),
          if (b.canPayUPI || (b.canViewUPI && b.upiPayment != null)) ...[
            DmPrimaryButton(
                label: widget.isDriver
                    ? 'Show fare QR / review UPI'
                    : 'Pay / view UPI QR',
                onPressed: _upi,
                icon: Icons.qr_code_rounded),
            const SizedBox(height: 12)
          ],
          if (widget.isDriver && b.canConfirmCash) ...[
            DmPrimaryButton(
                label: 'Confirm cash received',
                loading: _busy,
                onPressed: _cash),
            const SizedBox(height: 12)
          ],
          DmPrimaryButton(
              label: 'Share / save PDF receipt',
              loading: _busy,
              onPressed: () => _action(() => HubService.shareReceipt(b.id),
                  'Receipt opened in your phone share sheet.'),
              icon: Icons.ios_share_rounded),
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _action(() => HubService.emailReceipt(b.id),
                          'Receipt sent to your verified email.'),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Email my receipt'))),
          const SizedBox(height: 12),
          DmListCard(
              icon: Icons.help_outline_rounded,
              title: 'Payment issue?',
              body: 'Create a ticket linked to this trip.',
              onTap: () => Navigator.of(context)
                  .push(dmRoute(SupportScreen(bookingId: b.id)))),
          const SizedBox(height: 18),
          const DmInfoBox(
              text:
                  'This is a trip/manual payment record, not a GST tax invoice or independent bank/gateway verification. A driver-confirmed personal UPI receipt is a human assertion; no automatic debit/refund is performed.'),
        ]));
  }
}

class SupportScreen extends StatefulWidget {
  final int? bookingId;
  const SupportScreen({super.key, this.bookingId});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<Map<String, dynamic>> _tickets = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await HubService.tickets();
      if (mounted) {
        setState(() {
          _tickets = HubService.rows(data);
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

  Future<void> _create() async {
    final created = await dmShowSheet<bool>(context,
        title: 'How can we help?',
        subtitle: widget.bookingId == null
            ? 'Your message is saved for the platform team.'
            : 'Linked to booking #${widget.bookingId}',
        child: _TicketForm(bookingId: widget.bookingId));
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dmLocal('Help & support', 'सहायता'), style: dmHeading(size: 29)),
          const SizedBox(height: 8),
          Text('Real support tickets and replies from your platform staff.',
              style: dmSubtitle(size: 13)),
          const SizedBox(height: 18),
          DmPrimaryButton(
              label: 'Create a support ticket',
              onPressed: _create,
              icon: Icons.add_comment_outlined),
          const SizedBox(height: 20),
          const DmInfoBox(
              icon: Icons.emergency_outlined,
              color: danger,
              text:
                  'For an immediate emergency, use your phone dialer and call 112. Support tickets are not an emergency dispatch service.'),
          const SizedBox(height: 20),
          DmSectionHeader(title: 'Tickets', action: 'Refresh', onAction: _load),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            DmErrorState(
                title: 'Could not load tickets',
                message: _error!,
                onRetry: _load)
          else if (_tickets.isEmpty)
            const DmEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No tickets',
                body:
                    'Create a ticket above. Staff replies appear here and in your notification inbox.')
          else
            for (final t in _tickets) ...[
              DmListCard(
                  icon: Icons.chat_outlined,
                  title: '#${t['id']} • ${t['subject']}',
                  body: '${t['category']} • ${t['status']}',
                  accent: t['status'] == 'CLOSED' ? success : info,
                  onTap: () async {
                    await Navigator.of(context)
                        .push(dmRoute(TicketDetailScreen(id: t['id'] as int)));
                    await _load();
                  }),
              const SizedBox(height: 11)
            ],
        ]));
  }
}

class _TicketForm extends StatefulWidget {
  final int? bookingId;
  const _TicketForm({this.bookingId});
  @override
  State<_TicketForm> createState() => _TicketFormState();
}

class _TicketFormState extends State<_TicketForm> {
  final _subject = TextEditingController(), _body = TextEditingController();
  String _category = 'GENERAL';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await HubService.createTicket({
        'subject': _subject.text.trim(),
        'description': _body.text.trim(),
        'category': _category,
        if (widget.bookingId != null) 'booking_id': widget.bookingId
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(children: [
      DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final c in ['GENERAL', 'TRIP', 'PAYMENT', 'SAFETY', 'ACCOUNT'])
              DropdownMenuItem(value: c, child: Text(c))
          ],
          onChanged: (v) => setState(() => _category = v!)),
      const SizedBox(height: 12),
      DmField(
          controller: _subject,
          hint: 'Subject',
          icon: Icons.subject_rounded,
          maxLength: 120),
      const SizedBox(height: 12),
      DmField(
          controller: _body,
          hint: 'Describe what happened (at least 10 characters)',
          icon: Icons.notes_outlined,
          maxLines: 5,
          maxLength: 2000),
      if (_error != null) ...[
        const SizedBox(height: 12),
        DmInfoBox(text: _error!, color: danger)
      ],
      const SizedBox(height: 18),
      DmPrimaryButton(
          label: 'Send to support', loading: _busy, onPressed: _save),
    ]);
  }
}

class TicketDetailScreen extends StatefulWidget {
  final int id;
  const TicketDetailScreen({super.key, required this.id});
  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  bool _staff = false, _busy = false;
  String? _error;
  final _reply = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await HubService.ticket(widget.id);
      final u = await AuthService.cachedUser();
      if (mounted) {
        setState(() {
          _ticket = t;
          _staff = u?['role'] == 'ADMIN';
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send({String? status}) async {
    setState(() => _busy = true);
    try {
      await HubService.reply(
          widget.id,
          _reply.text.trim().isEmpty
              ? (status == 'CLOSED' ? 'Ticket closed.' : 'Ticket reopened.')
              : _reply.text.trim(),
          status: status);
      _reply.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final t = _ticket;
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ticket #${widget.id}', style: dmHeading(size: 28)),
          const SizedBox(height: 18),
          if (_error != null)
            DmErrorState(
                title: 'Could not load ticket',
                message: _error!,
                onRetry: _load)
          else if (t == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(t['subject'].toString(), style: dmHeading(size: 20)),
            const SizedBox(height: 10),
            DmPill(
                label: t['status'].toString(),
                color: t['status'] == 'CLOSED' ? success : info),
            const SizedBox(height: 14),
            Text(t['description'].toString(), style: dmSubtitle(size: 14)),
            const SizedBox(height: 20),
            for (final raw in (t['messages'] as List)) ...[
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: dmSurface(),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            (raw as Map)['staff'] == true
                                ? 'Platform support'
                                : 'Account holder',
                            style: dmCaption()),
                        const SizedBox(height: 6),
                        Text(raw['text'].toString())
                      ])),
              const SizedBox(height: 10)
            ],
            const SizedBox(height: 12),
            if (t['status'] != 'CLOSED') ...[
              DmField(
                  controller: _reply,
                  hint: 'Reply',
                  icon: Icons.chat_outlined,
                  maxLines: 3,
                  maxLength: 2000),
              const SizedBox(height: 12),
              DmPrimaryButton(
                  label: 'Send reply',
                  loading: _busy,
                  onPressed: () => _send()),
              TextButton(
                  onPressed: _busy ? null : () => _send(status: 'CLOSED'),
                  child: const Text('Close ticket')),
            ] else if (_staff)
              TextButton(
                  onPressed: () => _send(status: 'OPEN'),
                  child: const Text('Reopen ticket')),
            TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh replies')),
          ],
        ]));
  }
}

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _code = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await HubService.promotions();
      if (mounted) setState(() => _rows = HubService.rows(data));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      await HubService.claim(_code.text.trim().toUpperCase());
      _code.clear();
      if (mounted) setState(() => _error = null);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dmLocal('Promotions', 'प्रोमोशन'), style: dmHeading(size: 28)),
          const SizedBox(height: 8),
          Text(
              'Only operator-created, valid codes are accepted. Choose a claimed code on booking review.',
              style: dmSubtitle(size: 13)),
          const SizedBox(height: 20),
          DmField(
              controller: _code,
              hint: 'Promotion code',
              icon: Icons.local_offer_outlined),
          const SizedBox(height: 12),
          DmPrimaryButton(label: 'Add code', loading: _busy, onPressed: _claim),
          if (_error != null) ...[
            const SizedBox(height: 14),
            DmInfoBox(text: _error!, color: danger)
          ],
          const SizedBox(height: 20),
          if (_rows.isEmpty)
            const DmEmptyState(
                icon: Icons.local_offer_outlined,
                title: 'No promotions saved',
                body:
                    'Add a code supplied by your platform operator. No fake discounts are preloaded.')
          else
            for (final p in _rows) ...[
              DmListCard(
                  icon: Icons.confirmation_number_outlined,
                  title: p['code'].toString(),
                  body:
                      '${p['description']} • INR ${p['amount']} off • ${p['used'] == true ? 'Used' : p['active'] == true ? 'Available' : 'Expired/inactive'}',
                  accent: p['active'] == true ? info : muted),
              const SizedBox(height: 10)
            ],
        ]));
  }
}
