import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/direct_upi_service.dart';
import '../services/foreground_refresh.dart';
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
import 'payments_support_screen.dart';

/// Fare-prefilled personal QR. A scan / app return / customer claim NEVER
/// becomes a bank-verified payment. Only assigned-driver manual review records it.
class DirectUPIPaymentScreen extends StatefulWidget {
  final int bookingId;
  final bool isDriver;
  const DirectUPIPaymentScreen(
      {super.key, required this.bookingId, this.isDriver = false});
  @override
  State<DirectUPIPaymentScreen> createState() => _DirectUPIPaymentScreenState();
}

class _DirectUPIPaymentScreenState extends State<DirectUPIPaymentScreen>
    with ForegroundRefresh<DirectUPIPaymentScreen> {
  Map<String, dynamic>? _data;
  Uint8List? _qr;
  bool _busy = false, _refreshing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(create: true);
    startForegroundRefresh(_load);
  }

  Future<void> _load({bool create = false}) async {
    if (!mounted || _refreshing || _busy) return;
    _refreshing = true;
    try {
      final data = create
          ? await DirectUPIService.create(widget.bookingId)
          : await DirectUPIService.get(widget.bookingId);
      Uint8List? image;
      if (['CREATED', 'REJECTED'].contains(data['status'])) {
        image = _qr ?? await DirectUPIService.qrImage(widget.bookingId);
      }
      if (mounted) {
        setState(() {
          _data = data;
          _qr = image;
          _error = null;
        });
      }
      if (['CONFIRMED', 'CANCELLED'].contains(data['status'])) {
        stopForegroundRefresh();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _apply(Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await action();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          if (['REPORTED', 'CONFIRMED', 'CANCELLED'].contains(data['status'])) {
            _qr = null;
          }
        });
      }
      if (['CONFIRMED', 'CANCELLED'].contains(data['status'])) {
        stopForegroundRefresh();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        showDmMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    final data = _data;
    if (data == null) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Check before paying'),
                content: Text(
                    'Final fare: INR ${data['amount']}\nReceiver: ${data['receiver_name']}\nUPI ID: ${data['receiver_upi_id']}\n\nYour UPI app may allow edits: pay the exact fare only. Check the actual recipient in that app and authorize there. If a previous attempt debited your account, do NOT pay again—ask the driver to check credit.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Open UPI app'))
                ]));
    if (yes != true) return;
    try {
      await DirectUPIService.openUPI(data['qr_payload'].toString());
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  Future<void> _report() async {
    final ref = await dmShowSheet<String>(context,
        title: 'Report payment to your driver',
        subtitle:
            'Only after your UPI app shows a successful debit. A report is NOT bank verification or a paid receipt.',
        child: const _ReportForm());
    if (ref != null) {
      await _apply(() => DirectUPIService.report(widget.bookingId, ref));
    }
  }

  Future<void> _confirm() async {
    final result = await dmShowSheet<Map<String, dynamic>>(context,
        title: 'Check your actual bank credit',
        subtitle:
            'Expected INR ${_data?['amount']}. Customer screenshots/references are not proof. Verify your own bank/UPI ledger.',
        child: _ConfirmForm(
            expected: (_data?['amount'] ?? '').toString(),
            reportedReference:
                (_data?['customer_reference'] ?? '').toString()));
    if (result == null) return;
    await _apply(() => DirectUPIService.confirm(widget.bookingId,
        receivedAmount: result['amount'].toString(),
        bankReference: result['reference'].toString(),
        checkedBank: result['checked'] == true));
  }

  Future<void> _reject() async {
    final reason = await dmShowSheet<String>(context,
        title: 'Could not confirm credit',
        subtitle:
            'Explain what you checked. Tell the customer not to pay twice if their app already shows a debit.',
        child: const _RejectForm());
    if (reason != null) {
      await _apply(() => DirectUPIService.reject(widget.bookingId, reason));
    }
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Close unpaid request in app?'),
                content: const Text(
                    'First check that no payment was made/received. This only closes the record in DriveMate. It CANNOT cancel a bank transfer or make old personal QR screenshots unpayable. Do not collect cash as well if UPI is pending/credited.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep open')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Checked: no payment'))
                ]));
    if (yes == true) {
      await _apply(() => DirectUPIService.cancel(widget.bookingId));
    }
  }

  Future<void> _receipt() async {
    try {
      final booking = await RidesService.booking(widget.bookingId);
      if (mounted) {
        await Navigator.of(context).push(dmRoute(
            ReceiptScreen(booking: booking, isDriver: widget.isDriver)));
      }
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  Future<void> _share() async {
    try {
      await DirectUPIService.shareQR(widget.bookingId);
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showDmMessage(context, 'Could not open the phone share/save sheet.',
            error: true);
      }
    }
  }

  String _time(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    return date == null
        ? '—'
        : '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final data = _data;
    final state = data?['status'];
    final pending = state == 'REPORTED';
    final done = state == 'CONFIRMED';
    final closed = state == 'CANCELLED';
    return DmScreen(
        showBack: true,
        scroll: false,
        padding: EdgeInsets.zero,
        child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text('Trip #${widget.bookingId} • UPI',
                      style: dmHeading(size: 27)),
                  const SizedBox(height: 14),
                  const DmInfoBox(
                      icon: Icons.info_outline_rounded,
                      text:
                          'Personal direct UPI • manual driver confirmation. Scan/app return/typed UTR is NOT bank verification. DriveMate cannot force another UPI app’s amount-edit controls.'),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    DmErrorState(
                        title: 'Payment action not ready',
                        message: _error!,
                        onRetry: () => _load(create: data == null))
                  ],
                  if (data == null && _error == null)
                    const Padding(
                        padding: EdgeInsets.all(45),
                        child: Center(child: CircularProgressIndicator()))
                  else if (data != null) ...[
                    const SizedBox(height: 20),
                    Container(
                        padding: const EdgeInsets.all(18),
                        decoration: dmSurface(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FINAL FARE • SET BY SERVER',
                                  style: dmSectionLabel()),
                              const SizedBox(height: 10),
                              SelectableText('₹${data['amount']}',
                                  style: TextStyle(
                                      color: softWhite,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 10),
                              DmPill(
                                  label: data['status_label'].toString(),
                                  color: done
                                      ? success
                                      : closed
                                          ? muted
                                          : warning),
                              const SizedBox(height: 16),
                              DmInfoRow(
                                  label: 'Receiver',
                                  value: data['receiver_name'].toString()),
                              Row(children: [
                                Expanded(
                                    child: SelectableText(
                                        data['receiver_upi_id'].toString(),
                                        style: TextStyle(
                                            color: softWhite,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700))),
                                IconButton(
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(
                                          text: data['receiver_upi_id']
                                              .toString()));
                                      if (mounted) {
                                        showDmMessage(this.context,
                                            'Receiving UPI ID copied.');
                                      }
                                    },
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 17),
                                    tooltip: 'Copy receiving UPI ID')
                              ]),
                            ])),
                    if (_qr != null && !done && !closed && !pending) ...[
                      const SizedBox(height: 18),
                      Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: hairline)),
                          child: Image.memory(_qr!,
                              fit: BoxFit.contain,
                              semanticLabel:
                                  'Fare-prefilled UPI QR for trip ${widget.bookingId}')),
                      const SizedBox(height: 9),
                      Text(
                          'QR contains INR ${data['amount']} and the receiving ID above. In-app amount has no edit field. Confirm the exact fare and actual recipient in your UPI app.',
                          style: dmCaption(size: 11)),
                      const SizedBox(height: 14),
                      if (!widget.isDriver)
                        DmPrimaryButton(
                            label: 'Open UPI app with this fare',
                            onPressed: _busy ? null : _pay,
                            icon: Icons.open_in_new_rounded),
                      const SizedBox(height: 10),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              onPressed: _busy ? null : _share,
                              icon: const Icon(Icons.ios_share_rounded),
                              label: const Text('Share / save fare QR'))),
                      const SizedBox(height: 7),
                      Text(
                          'Same phone? Use Open UPI app, or a gallery scanner if your UPI app supports it. Do not repeatedly scan/pay after an account debit.',
                          style: dmCaption(size: 10.5)),
                    ],
                    if (pending) ...[
                      const SizedBox(height: 18),
                      DmListCard(
                          icon: Icons.hourglass_top_rounded,
                          title: widget.isDriver
                              ? 'Customer reported a payment'
                              : 'Waiting for driver bank check',
                          body:
                              'Reported reference: ${data['customer_reference']}\nThe record is not paid yet. Do not pay again if your account was debited.',
                          accent: warning)
                    ],
                    if (state == 'REJECTED') ...[
                      const SizedBox(height: 14),
                      DmInfoBox(
                          text:
                              'Driver could not confirm: ${data['review_note']}\nCheck your UPI/bank status before attempting another payment. No automatic refund is performed.',
                          color: danger)
                    ],
                    if (done) ...[
                      const SizedBox(height: 18),
                      DmInfoBox(
                          icon: Icons.person_outline_rounded,
                          color: success,
                          text:
                              'Assigned driver manually confirmed INR ${data['amount']} received at ${_time(data['confirmed_at'])}.\nBank reference: ${data['bank_reference']}\nThis is NOT independent gateway/bank verification.'),
                      const SizedBox(height: 16),
                      DmPrimaryButton(
                          label: 'Open updated receipt',
                          onPressed: _receipt,
                          icon: Icons.receipt_long_outlined),
                    ],
                    if (closed) ...[
                      const SizedBox(height: 16),
                      const DmInfoBox(
                          text:
                              'Closed in DriveMate only. This is not a bank cancellation/refund. Old QR screenshots can still be paid; do not use them. Cash can be recorded only after actual collection.')
                    ],
                    if (!widget.isDriver && data['can_report'] == true) ...[
                      const SizedBox(height: 18),
                      DmPrimaryButton(
                          label: state == 'REPORTED'
                              ? 'Update reported reference'
                              : 'I paid — send reference to driver',
                          loading: _busy,
                          onPressed: _report,
                          icon: Icons.send_outlined)
                    ],
                    if (widget.isDriver && data['can_confirm'] == true) ...[
                      const SizedBox(height: 18),
                      DmPrimaryButton(
                          label: 'Record actual UPI credit',
                          loading: _busy,
                          onPressed: _confirm,
                          icon: Icons.fact_check_outlined),
                      if (data['can_reject'] == true)
                        TextButton(
                            onPressed: _busy ? null : _reject,
                            child:
                                const Text('Could not confirm / reject report'))
                    ],
                    if (data['can_cancel'] == true) ...[
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: const Text('Close unpaid request before cash'))
                    ],
                    const SizedBox(height: 18),
                    DmListCard(
                        icon: Icons.help_outline_rounded,
                        title: 'Payment issue / wrong amount?',
                        body:
                            'Open a linked support ticket. A typed reference or screenshot never automatically marks this trip paid.',
                        onTap: () => Navigator.of(context).push(dmRoute(
                            SupportScreen(bookingId: widget.bookingId)))),
                    const SizedBox(height: 16),
                    Text(
                        'Updates refresh every 8 seconds while visible. No bank API, automatic debit, single-use bank QR, settlement or automatic refund is connected in personal mode.',
                        style: dmCaption(size: 10.5)),
                  ],
                ])));
  }
}

class _ReportForm extends StatefulWidget {
  const _ReportForm();
  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final _ref = TextEditingController();
  bool _checked = false;
  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        DmField(
            controller: _ref,
            hint: 'UPI reference / UTR from your payment app',
            icon: Icons.receipt_long_outlined,
            maxLength: 64,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _checked,
            onChanged: (v) => setState(() => _checked = v == true),
            title: const Text(
                'My UPI app shows a successful debit. I understand the driver must check actual credit.',
                style: TextStyle(fontSize: 12.5))),
        const SizedBox(height: 14),
        DmPrimaryButton(
            label: 'Report — not verified payment',
            onPressed: _checked && _ref.text.trim().length >= 6
                ? () => Navigator.pop(context, _ref.text.trim())
                : null),
      ]);
}

class _ConfirmForm extends StatefulWidget {
  final String expected, reportedReference;
  const _ConfirmForm({required this.expected, required this.reportedReference});
  @override
  State<_ConfirmForm> createState() => _ConfirmFormState();
}

class _ConfirmFormState extends State<_ConfirmForm> {
  final _amount = TextEditingController(), _ref = TextEditingController();
  bool _checked = false;
  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Final fare is fixed: INR ${widget.expected}',
            style: dmHeading(size: 19)),
        const SizedBox(height: 10),
        if (widget.reportedReference.isNotEmpty)
          Text(
              'Customer reported: ${widget.reportedReference}\nUse the actual bank record below, not the screenshot alone.',
              style: dmCaption()),
        const SizedBox(height: 12),
        DmField(
            controller: _amount,
            hint: 'Actual amount credited in your bank (INR)',
            icon: Icons.currency_rupee_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        DmField(
            controller: _ref,
            hint: 'Actual bank/UPI transaction reference',
            icon: Icons.receipt_long_outlined,
            maxLength: 64,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _checked,
            onChanged: (v) => setState(() => _checked = v == true),
            title: const Text(
                'I checked my own bank/UPI app and actually received this exact fare. This is my manual confirmation, not bank/API verification.',
                style: TextStyle(fontSize: 12.5))),
        const SizedBox(height: 14),
        DmPrimaryButton(
            label: 'Manually confirm actual receipt',
            onPressed: _checked &&
                    _ref.text.trim().length >= 6 &&
                    _amount.text.trim().isNotEmpty
                ? () => Navigator.pop(context, {
                      'amount': _amount.text.trim(),
                      'reference': _ref.text.trim(),
                      'checked': _checked
                    })
                : null),
      ]);
}

class _RejectForm extends StatefulWidget {
  const _RejectForm();
  @override
  State<_RejectForm> createState() => _RejectFormState();
}

class _RejectFormState extends State<_RejectForm> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        DmField(
            controller: _reason,
            hint: 'What did you check / reason?',
            icon: Icons.notes_outlined,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        DmPrimaryButton(
            label: 'Report not confirmed',
            onPressed: _reason.text.trim().length >= 3
                ? () => Navigator.pop(context, _reason.text.trim())
                : null)
      ]);
}
