import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/direct_upi_service.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';

/// Driver-owned receiving details. A QR/ID match is not bank ownership KYC.
class DriverUPIScreen extends StatefulWidget {
  const DriverUPIScreen({super.key});
  @override
  State<DriverUPIScreen> createState() => _DriverUPIScreenState();
}

class _DriverUPIScreenState extends State<DriverUPIScreen> {
  final _upi = TextEditingController(), _password = TextEditingController();
  Map<String, dynamic>? _profile;
  Uint8List? _savedImage;
  String? _newImage, _error;
  bool _loading = true, _busy = false, _attest = false, _active = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _upi.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await DirectUPIService.profile();
      Uint8List? image;
      if (data['qr_uploaded'] == true) {
        try {
          image = await DirectUPIService.profileImage();
        } on ApiException {/* Optional preview can be retried. */}
      }
      if (mounted) {
        setState(() {
          _profile = data;
          _upi.text = (data['upi_id'] ?? '').toString();
          _active = data['active'] != false;
          _savedImage = image;
          _newImage = null;
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

  Future<void> _pick() async {
    final source = await showDialog<ImageSource>(
        context: context,
        builder: (c) =>
            SimpleDialog(title: const Text('Receiving UPI QR'), children: [
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, ImageSource.gallery),
                  child: const Text('Upload from gallery')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, ImageSource.camera),
                  child: const Text('Photograph a printed QR'))
            ]));
    if (source == null) return;
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1800, imageQuality: 100);
      if (file != null && mounted) {
        setState(() {
          _newImage = file.path;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Gallery/camera could not open. Check phone permissions.');
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_newImage == null && _profile?['qr_uploaded'] != true) {
      setState(() => _error = 'Upload your own receiving UPI QR image.');
      return;
    }
    if (!_attest) {
      setState(
          () => _error = 'Confirm the receiving UPI ID and QR belong to you.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() =>
          _error = 'Enter your DriveMate account password, not your UPI PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DirectUPIService.saveProfile(
          upiId: _upi.text.trim(),
          password: _password.text,
          attested: _attest,
          active: _active,
          imagePath: _newImage);
      _password.clear();
      await _load();
      if (mounted) {
        setState(() => _attest = false);
        showDmMessage(context,
            'Receiving details saved. Fare-specific QRs use the server final amount.');
      }
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
          Text('Receiving UPI & QR', style: dmHeading(size: 28)),
          const SizedBox(height: 9),
          Text(
              'Your receiving details for completed trips. No bank password or UPI PIN is collected.',
              style: dmSubtitle(size: 13)),
          const SizedBox(height: 18),
          const DmInfoBox(
              icon: Icons.info_outline_rounded,
              text:
                  'Personal direct UPI • manual confirmation. Matching a QR with an ID does not verify bank ownership. The customer authorizes in their UPI app; you must check actual bank credit before confirming.'),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_profile?['configured'] == true) ...[
              Text('Driver: ${_profile?['payee_name'] ?? ''}',
                  style: dmHeading(size: 18)),
              const SizedBox(height: 6),
              Text(
                  'QR name hint: ${_profile?['uploaded_payee_hint'] ?? 'Not present'}',
                  style: dmCaption()),
              const SizedBox(height: 14)
            ],
            DmField(
                controller: _upi,
                hint: 'Your receiving UPI ID',
                icon: Icons.account_balance_outlined,
                maxLength: 256,
                helper:
                    'If left blank on first upload, the server extracts the ID from a readable UPI QR. A typed ID must match that QR.'),
            const SizedBox(height: 16),
            if (_newImage != null || _savedImage != null)
              Container(
                  width: double.infinity,
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: hairline)),
                  child: _newImage != null
                      ? Image.file(File(_newImage!), fit: BoxFit.contain)
                      : Image.memory(_savedImage!, fit: BoxFit.contain)),
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('Upload / replace receiving QR'))),
            const SizedBox(height: 8),
            Text(
                'The uploaded QR is a reference for your receiving ID. Payment uses a NEW QR with the final trip fare, not the uploaded image’s old amount/reference.',
                style: dmCaption(size: 11)),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept new direct-UPI requests'),
                subtitle: const Text(
                    'Pausing does not change existing trip QR snapshots or cancel old QR images at the bank.'),
                value: _active,
                onChanged: _busy ? null : (v) => setState(() => _active = v)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                    'I confirm this is my own receiving UPI ID and QR.',
                    style: TextStyle(fontSize: 13)),
                value: _attest,
                onChanged:
                    _busy ? null : (v) => setState(() => _attest = v == true)),
            const SizedBox(height: 12),
            DmField(
                controller: _password,
                hint: 'Current DriveMate password (not UPI PIN)',
                icon: Icons.lock_outline_rounded,
                obscure: true),
            if (_error != null) ...[
              const SizedBox(height: 14),
              DmInfoBox(text: _error!, color: danger)
            ],
            const SizedBox(height: 18),
            DmPrimaryButton(
                label: 'Save receiving details',
                loading: _busy,
                onPressed: _save),
            const SizedBox(height: 16),
            const DmInfoBox(
                icon: Icons.lock_outline_rounded,
                text:
                    'Existing trip payment requests keep the original recipient and amount. Changing your profile never silently redirects a QR already issued to a customer.'),
          ],
        ]));
  }
}
