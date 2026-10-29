import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/policy_sheet.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';

class HubCollectionScreen extends StatefulWidget {
  final String kind;
  const HubCollectionScreen({super.key, required this.kind});
  @override
  State<HubCollectionScreen> createState() => _HubCollectionScreenState();
}

class _HubCollectionScreenState extends State<HubCollectionScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String get title => switch (widget.kind) {
        'places' => dmLocal('Saved places', 'पसंदीदा स्थान'),
        'contacts' => dmLocal('People & family', 'परिवार और संपर्क'),
        _ => dmLocal('Business profiles', 'व्यावसायिक प्रोफ़ाइल')
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await HubService.list(widget.kind);
      if (mounted) {
        setState(() {
          _items = rows;
          _loading = false;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final saved = await dmShowSheet<bool>(context,
        title: item == null
            ? 'Add ${widget.kind == 'places' ? 'place' : widget.kind == 'contacts' ? 'person' : 'business'}'
            : 'Edit details',
        child: _CollectionForm(kind: widget.kind, item: item));
    if (saved == true && mounted) await _load();
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Remove this item?'),
                content: const Text(
                    'This removes it from your account. Existing trip snapshots stay unchanged.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove'))
                ]));
    if (yes != true) return;
    try {
      await HubService.remove(widget.kind, item['id'] as int);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: dmHeading(size: 28)),
          const SizedBox(height: 8),
          Text(
              widget.kind == 'places'
                  ? 'Home, work and places you can use in booking.'
                  : widget.kind == 'contacts'
                      ? 'Trusted contacts you can call or choose when booking for someone else.'
                      : 'Separate personal and work travel on your receipts.',
              style: dmSubtitle(size: 13)),
          const SizedBox(height: 20),
          DmPrimaryButton(
              label:
                  'Add ${widget.kind == 'places' ? 'place' : widget.kind == 'contacts' ? 'person' : 'business profile'}',
              onPressed: () => _edit(),
              icon: Icons.add_rounded),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            DmErrorState(
                title: 'Could not load', message: _error!, onRetry: _load)
          else if (_items.isEmpty)
            const DmEmptyState(
                icon: Icons.bookmarks_outlined,
                title: 'Nothing saved yet',
                body:
                    'Add an item above to save it to your account.')
          else
            for (final item in _items)
              Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: dmSurface(),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  (item['label'] ??
                                          item['name'] ??
                                          item['company'])
                                      .toString(),
                                  style: dmHeading(size: 17))),
                          IconButton(
                              onPressed: () => _edit(item),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit'),
                          IconButton(
                              onPressed: () => _remove(item),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: danger),
                              tooltip: 'Remove')
                        ]),
                        Text(
                            (item['address'] ??
                                    item['phone'] ??
                                    '${item['department']} • ${item['employee_id']}')
                                .toString(),
                            style: dmSubtitle(size: 12)),
                        if (widget.kind == 'contacts') ...[
                          const SizedBox(height: 8),
                          Text(
                              item['emergency'] == true
                                  ? 'Emergency contact'
                                  : 'Family / guest contact',
                              style: dmCaption()),
                          TextButton.icon(
                              onPressed: () async {
                                try {
                                  await HubService.dial(
                                      item['phone'].toString());
                                } on ApiException catch (e) {
                                  if (context.mounted) {
                                    showDmMessage(context, e.message,
                                        error: true);
                                  }
                                }
                              },
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Open dialer'))
                        ],
                      ])),
        ]));
  }
}

class _CollectionForm extends StatefulWidget {
  final String kind;
  final Map<String, dynamic>? item;
  const _CollectionForm({required this.kind, this.item});
  @override
  State<_CollectionForm> createState() => _CollectionFormState();
}

class _CollectionFormState extends State<_CollectionForm> {
  final _key = GlobalKey<FormState>();
  late TextEditingController _name, _second, _third;
  ChosenPlace? _place;
  String _placeKind = 'OTHER';
  bool _emergency = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final d = widget.item ?? {};
    _name = TextEditingController(
        text: (d['label'] ?? d['name'] ?? d['company'] ?? '').toString());
    _second = TextEditingController(
        text: (d['address'] ?? d['phone'] ?? d['department'] ?? '').toString());
    _third = TextEditingController(
        text: (d['relationship'] ?? d['employee_id'] ?? '').toString());
    _placeKind = (d['kind'] ?? 'OTHER').toString();
    _emergency = d['emergency'] != false;
    if (d['latitude'] != null) {
      _place = ChosenPlace(
          address: _second.text,
          latitude: double.parse(d['latitude'].toString()),
          longitude: double.parse(d['longitude'].toString()));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _second.dispose();
    _third.dispose();
    super.dispose();
  }

  Future<void> _map() async {
    final p = await Navigator.of(context).push<ChosenPlace>(
        dmRoute(MapPickerScreen(title: 'Save a place', initial: _place)));
    if (p != null && mounted) {
      setState(() {
        _place = p;
        _second.text = p.address;
      });
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate() || _busy) return;
    if (widget.kind == 'places' && _place == null) {
      setState(() => _error = 'Choose a map pin first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> data = switch (widget.kind) {
      'places' => {
          'label': _name.text.trim(),
          'address': _second.text.trim(),
          'latitude': _place!.latitude.toStringAsFixed(7),
          'longitude': _place!.longitude.toStringAsFixed(7),
          'kind': _placeKind
        },
      'contacts' => {
          'name': _name.text.trim(),
          'phone': _second.text.trim(),
          'relationship': _third.text.trim(),
          'emergency': _emergency
        },
      _ => {
          'company': _name.text.trim(),
          'department': _second.text.trim(),
          'employee_id': _third.text.trim()
        }
    };
    try {
      await HubService.save(widget.kind, data, id: widget.item?['id'] as int?);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Form(
        key: _key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DmField(
              controller: _name,
              hint: widget.kind == 'places'
                  ? 'Label — Home / Work'
                  : widget.kind == 'contacts'
                      ? 'Full name'
                      : 'Company name',
              icon: Icons.badge_outlined,
              validator: (v) => (v ?? '').trim().length < 2
                  ? 'Enter at least two characters'
                  : null),
          const SizedBox(height: 14),
          if (widget.kind == 'places') ...[
            DmPrimaryButton(
                label: _place == null
                    ? 'Choose location on map'
                    : 'Change map location',
                onPressed: _map,
                icon: Icons.map_outlined),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final k in ['HOME', 'WORK', 'OTHER'])
                ChoiceChip(
                    label: Text(k),
                    selected: _placeKind == k,
                    onSelected: (_) => setState(() => _placeKind = k))
            ]),
            const SizedBox(height: 12)
          ],
          DmField(
              controller: _second,
              hint: widget.kind == 'places'
                  ? 'Address / landmark'
                  : widget.kind == 'contacts'
                      ? 'Mobile number'
                      : 'Department (optional)',
              icon: widget.kind == 'contacts'
                  ? Icons.call_outlined
                  : Icons.location_on_outlined,
              keyboardType: widget.kind == 'contacts'
                  ? TextInputType.phone
                  : TextInputType.text,
              validator: (v) => widget.kind == 'business'
                  ? null
                  : (widget.kind == 'contacts'
                          ? (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                          : (v ?? '').trim().length < 4)
                      ? 'Enter valid details'
                      : null),
          if (widget.kind != 'places') ...[
            const SizedBox(height: 14),
            DmField(
                controller: _third,
                hint: widget.kind == 'contacts'
                    ? 'Relationship (optional)'
                    : 'Employee ID (optional)',
                icon: Icons.notes_outlined)
          ],
          if (widget.kind == 'contacts')
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency contact'),
                value: _emergency,
                onChanged: (v) => setState(() => _emergency = v)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            DmInfoBox(text: _error!, color: danger)
          ],
          const SizedBox(height: 18),
          DmPrimaryButton(
              label: 'Save to account', loading: _busy, onPressed: _save),
        ]));
  }
}

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  Future<void> _sync(Map<String, dynamic> values) async {
    try {
      await HubService.preferences(values);
    } on ApiException {
      if (mounted) {
        showDmMessage(
            context, 'Saved on this phone. Server preferences could not sync.',
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final a = DmAppearance.instance;
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dmLocal('Appearance & accessibility', 'थीम और सुविधा'),
              style: dmHeading(size: 27)),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(dmLocal('Dark mode', 'डार्क मोड')),
              subtitle: const Text(
                  'Applies across Home, Services, Activity, Account and registration.'),
              value: a.dark,
              onChanged: (v) async {
                await a.setDark(v);
                if (mounted) setState(() {});
                await _sync({'theme': v ? 'dark' : 'light'});
              }),
          const Divider(),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(dmLocal('Larger text', 'बड़ा टेक्स्ट')),
              value: a.largeText,
              onChanged: (v) async {
                await a.setLargeText(v);
                if (mounted) setState(() {});
                await _sync({'large_text': v});
              }),
          const SizedBox(height: 20),
          Text(dmLocal('App language', 'ऐप भाषा'), style: dmHeading(size: 18)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'hi', label: Text('हिन्दी'))
              ],
              selected: {
                a.language
              },
              onSelectionChanged: (v) async {
                await a.setLanguage(v.first);
                if (mounted) setState(() {});
                await _sync({'language': v.first});
              }),
          const SizedBox(height: 22),
          DmListCard(
              icon: Icons.settings_outlined,
              title: 'Phone permissions',
              body:
                  'Manage location, notifications and camera permissions in Android settings.',
              onTap: () => Geolocator.openAppSettings()),
        ]));
  }
}

class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key});
  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final _name = TextEditingController(), _phone = TextEditingController();
  Uint8List? _photoBytes;
  String _email = '';
  bool _busy = false, _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await HubService.account();
      final u = (data['user'] as Map);
      if (u['has_profile_photo'] == true) {
        try {
          _photoBytes =
              await AuthService.getPrivateBytes('auth/profile/photo/');
        } on ApiException {/* Optional image can be retried. */}
      }
      if (mounted) {
        setState(() {
          _name.text = u['name'].toString();
          _phone.text = u['phone'].toString();
          _email = u['email'].toString();
          _loading = false;
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

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final data =
          await HubService.updateProfile(_name.text.trim(), _phone.text.trim());
      await AuthService.saveSession({'user': data['user']});
      if (mounted) showDmMessage(context, 'Profile saved.');
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final source = await showDialog<ImageSource>(
        context: context,
        builder: (c) =>
            SimpleDialog(title: const Text('Profile photo'), children: [
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, ImageSource.camera),
                  child: const Text('Take a photo')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, ImageSource.gallery),
                  child: const Text('Choose from gallery'))
            ]));
    if (source == null) return;
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (file == null) return;
      await AuthService.uploadProfilePhoto(file.path);
      await _load();
      if (mounted) showDmMessage(context, 'Profile photo uploaded.');
    } catch (e) {
      if (mounted) {
        showDmMessage(
            context,
            e is ApiException
                ? e.message
                : 'Camera/gallery could not open. Check phone permissions.',
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dmLocal('Edit profile', 'प्रोफ़ाइल बदलें'),
              style: dmHeading(size: 28)),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            DmErrorState(
                title: 'Profile unavailable', message: _error!, onRetry: _load)
          else ...[
            if (_photoBytes != null) ...[
              Center(
                  child: ClipOval(
                      child: Image.memory(_photoBytes!,
                          height: 90,
                          width: 90,
                          fit: BoxFit.cover,
                          cacheWidth: 240))),
              const SizedBox(height: 16)
            ],
            DmListCard(
                icon: Icons.add_a_photo_outlined,
                title: 'Profile photo',
                body: 'Camera or gallery; uploaded privately to your account.',
                onTap: _photo),
            const SizedBox(height: 18),
            DmField(
                controller: _name,
                hint: 'Full name',
                icon: Icons.person_outline_rounded),
            const SizedBox(height: 14),
            DmField(
                controller: _phone,
                hint: 'Mobile number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 14),
            DmInfoBox(text: 'Verified email: $_email'),
            const SizedBox(height: 18),
            DmPrimaryButton(
                label: 'Save profile', loading: _busy, onPressed: _save),
            const SizedBox(height: 12),
            DmListCard(
                icon: Icons.mail_outline_rounded,
                title: 'Change email',
                body:
                    'Verify the new address with an emailed OTP before it replaces your current email.',
                onTap: () => Navigator.of(context)
                    .push(dmRoute(const EmailChangeScreen()))),
            const SizedBox(height: 12),
            DmListCard(
                icon: Icons.password_rounded,
                title: 'Change password',
                body: 'Receive a reset code at your account email.',
                onTap: () => Navigator.of(context)
                    .push(dmRoute(const ForgotPasswordScreen()))),
          ],
        ]));
  }
}

class EmailChangeScreen extends StatefulWidget {
  const EmailChangeScreen({super.key});
  @override
  State<EmailChangeScreen> createState() => _EmailChangeScreenState();
}

class _EmailChangeScreenState extends State<EmailChangeScreen> {
  final _email = TextEditingController(),
      _code = TextEditingController(),
      _currentPassword = TextEditingController();
  bool _sent = false, _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_sent) {
        await HubService.requestEmailChange(
            _email.text.trim(), _currentPassword.text);
        if (mounted) setState(() => _sent = true);
      } else {
        final data = await HubService.confirmEmail(_code.text.trim());
        await AuthService.saveSession({'user': data['user']});
        if (mounted) {
          showDmMessage(context, 'Email verified and changed.');
          Navigator.pop(context);
        }
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
          Text('Change email', style: dmHeading(size: 28)),
          const SizedBox(height: 18),
          DmField(
              controller: _email,
              hint: 'New email address',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              readOnly: _sent),
          if (!_sent) ...[
            const SizedBox(height: 14),
            DmField(
                controller: _currentPassword,
                hint: 'Current password',
                icon: Icons.lock_outline_rounded,
                obscure: true)
          ],
          if (_sent) ...[
            const SizedBox(height: 14),
            DmField(
                controller: _code,
                hint: '6-digit email code',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6)
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            DmInfoBox(text: _error!, color: danger)
          ],
          const SizedBox(height: 20),
          DmPrimaryButton(
              label: _sent ? 'Verify new email' : 'Send verification code',
              loading: _busy,
              onPressed: _submit),
        ]));
  }
}

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _busy = false;
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await HubService.exportData();
      await HubService.shareText(
          const JsonEncoder.withIndent('  ').convert(data));
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Deactivate account?'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Active trips must be finished/cancelled. This signs you out and disables login. History is retained for support/legal records; contact the operator for a data-erasure request.'),
                  const SizedBox(height: 14),
                  TextField(
                      controller: password,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'Current password'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep account')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Deactivate'))
                ]));
    final value = password.text;
    password.dispose();
    if (confirmed != true) return;
    try {
      await HubService.deactivate(value);
      await AuthService.clearSession();
      if (mounted) pushClean(context, const LoginScreen());
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Privacy & security', style: dmHeading(size: 28)),
          const SizedBox(height: 16),
          const DmInfoBox(
              icon: Icons.verified_user_outlined,
              text:
                  'Trip-start OTP is always required. Only your assigned driver sees contact details. Location is shared only during an active assigned trip; it is hidden from trip-history responses.'),
          const SizedBox(height: 18),
          DmListCard(
              icon: Icons.description_outlined,
              title: 'Terms & Conditions',
              body: 'Read the terms for using DriveMate.',
              onTap: () => showPolicySheet(context, PolicyDoc.terms)),
          const SizedBox(height: 14),
          DmListCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              body: 'Learn how your information is handled.',
              onTap: () => showPolicySheet(context, PolicyDoc.privacy)),
          const SizedBox(height: 14),
          DmListCard(
              icon: Icons.download_outlined,
              title: 'Export my account data',
              body:
                  'Share an export of your profile, preferences, saved places, contacts and latest trips. Authentication secrets/private documents are excluded.',
              onTap: _busy ? null : _export),
          const SizedBox(height: 14),
          DmListCard(
              icon: Icons.person_off_outlined,
              title: 'Deactivate account',
              body:
                  'Requires your password and no active trip. This is not an instant deletion of legally retained records.',
              accent: danger,
              onTap: _deactivate),
        ]));
  }
}
