import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_ui.dart';
import 'account_tools_screen.dart';
import 'payments_support_screen.dart';
import 'driver_application_status_screen.dart';
import 'driver_documents_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'safety_screen.dart';
import 'vehicles_screen.dart';
import 'driver_upi_screen.dart';

/// V9 account hub: every displayed entry opens an implemented action, not a
/// placeholder toast. Cash-only scope deliberately excludes fake wallet top-up.
class AccountScreen extends StatefulWidget {
  final String role;
  final String name;
  final Map<String, dynamic>? progress;
  const AccountScreen(
      {super.key, required this.role, required this.name, this.progress});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool get _driver => widget.role == 'Driver';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await HubService.account();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(dmRoute(page));
    if (mounted) await _load();
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                    'Your cars, trips and documents stay on the server. This signs out this phone only.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Stay')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Sign out'))
                ]));
    if (yes != true) return;
    await AuthService.clearSession();
    if (mounted) {
      pushClean(context, LoginScreen(role: widget.role.toUpperCase()));
    }
  }

  Future<void> _invite() async {
    final code = (_data?['invite_code'] ?? '').toString();
    if (code.isEmpty) {
      showDmMessage(context, 'Reconnect to load your invitation code.',
          error: true);
      return;
    }
    await HubService.shareText(
        'DriveMate: book a professional driver for your own car. Use my invitation code $code when creating your account. This code records the referral; no automatic cash reward is promised.');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final user = (_data?['user'] as Map?) ?? {};
    final name = (user['name'] ?? widget.name).toString();
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            children: [
              Row(children: [
                Expanded(
                    child: Text(dmLocal('Account', 'अकाउंट'),
                        style: dmHeading(size: 32))),
                IconButton(
                    onPressed: () => _open(const AppearanceScreen()),
                    icon: Icon(DmAppearance.instance.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined),
                    tooltip: 'Appearance')
              ]),
              const SizedBox(height: 18),
              GestureDetector(
                  onTap: () => _open(const ProfileEditorScreen()),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name, style: dmHeading(size: 26)),
                          const SizedBox(height: 7),
                          Text((user['email'] ?? 'Signed in').toString(),
                              style: dmCaption(size: 12)),
                          const SizedBox(height: 9),
                          DmPill(label: widget.role.toUpperCase(), color: info)
                        ])),
                    const SizedBox(width: 14),
                    DmAvatar(name: name, size: 68)
                  ])),
              const SizedBox(height: 23),
              Row(children: [
                _quick(Icons.help_outline_rounded, dmLocal('Help', 'सहायता'),
                    () => _open(const SupportScreen())),
                const SizedBox(width: 10),
                _quick(Icons.payments_outlined, dmLocal('Payments', 'भुगतान'),
                    () => _open(PaymentsScreen(isDriver: _driver))),
                const SizedBox(width: 10),
                _quick(Icons.shield_outlined, dmLocal('Safety', 'सुरक्षा'),
                    () => _open(const SafetyScreen()))
              ]),
              const SizedBox(height: 20),
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: dmSurface(),
                  child: Row(children: [
                    Expanded(
                        child: _stat('${_data?['completed_trips'] ?? '—'}',
                            dmLocal('Completed trips', 'पूरी यात्राएं'))),
                    Expanded(
                        child: _stat('${_data?['saved_places'] ?? '—'}',
                            dmLocal('Saved places', 'पसंदीदा स्थान'))),
                    Expanded(
                        child: _stat('${_data?['referral_count'] ?? '—'}',
                            dmLocal('Invites joined', 'जुड़े आमंत्रण')))
                  ])),
              if (_error != null) ...[
                const SizedBox(height: 12),
                DmListCard(
                    icon: Icons.cloud_off_outlined,
                    title: 'Account not synced',
                    body: _error!,
                    accent: warning,
                    onTap: _load)
              ],
              const SizedBox(height: 24),
              const DmSectionHeader(title: 'Your account'),
              _row(
                  Icons.person_outline_rounded,
                  dmLocal('Edit profile', 'प्रोफ़ाइल बदलें'),
                  'Name, mobile, photo and verified email',
                  () => _open(const ProfileEditorScreen())),
              if (widget.role == 'Customer')
                _row(
                    Icons.garage_outlined,
                    dmLocal('Your vehicles', 'आपकी गाड़ियां'),
                    'Add, edit and select your default car',
                    () => _open(const VehiclesScreen())),
              _row(
                  Icons.bookmark_border_rounded,
                  dmLocal('Saved places', 'पसंदीदा स्थान'),
                  'Home, work and your map pins',
                  () => _open(const HubCollectionScreen(kind: 'places'))),
              _row(
                  Icons.people_outline_rounded,
                  dmLocal('People & family', 'परिवार और संपर्क'),
                  'Trusted contacts and booking for someone else',
                  () => _open(const HubCollectionScreen(kind: 'contacts'))),
              _row(
                  Icons.business_center_outlined,
                  dmLocal('Business profiles', 'व्यावसायिक प्रोफ़ाइल'),
                  'Separate work travel on your receipts',
                  () => _open(const HubCollectionScreen(kind: 'business'))),
              if (widget.role == 'Customer')
                _row(
                    Icons.local_offer_outlined,
                    dmLocal('Promotions', 'प्रोमोशन'),
                    'Claim and use operator-issued discounts',
                    () => _open(const PromotionsScreen())),
              _row(
                  Icons.redeem_outlined,
                  dmLocal('Invite friends', 'दोस्तों को आमंत्रित करें'),
                  'Code ${_data?['invite_code'] ?? '—'} • no automatic cash rewards',
                  _invite),
              if (_driver) ...[
                _row(
                    Icons.qr_code_rounded,
                    'Receiving UPI & QR',
                    'Upload your own receiving QR and save the matching ID',
                    () => _open(const DriverUPIScreen())),
                const SizedBox(height: 18),
                const DmSectionHeader(title: 'Driver account'),
                _row(
                    Icons.verified_user_outlined,
                    'Application status',
                    'Verification, consents and training',
                    () => _open(DriverApplicationStatusScreen(name: name))),
                _row(
                    Icons.folder_shared_outlined,
                    'Documents & training',
                    'Update your licence and required documents',
                    () => _open(DriverDocumentsScreen(name: name)))
              ],
              const SizedBox(height: 18),
              const DmSectionHeader(title: 'Safety & support'),
              _row(
                  Icons.notifications_none_rounded,
                  dmLocal('Notifications', 'सूचनाएं'),
                  'Real trip and support updates',
                  () => _open(NotificationsScreen(role: widget.role))),
              _row(
                  Icons.forum_outlined,
                  dmLocal('Help & support', 'सहायता'),
                  'Tickets, staff replies and trip/payment issues',
                  () => _open(const SupportScreen())),
              _row(
                  Icons.lock_outline_rounded,
                  dmLocal('Privacy & security', 'गोपनीयता और सुरक्षा'),
                  'Data export, mandatory trip PIN and deactivation',
                  () => _open(const PrivacyScreen())),
              const SizedBox(height: 18),
              const DmSectionHeader(title: 'Preferences'),
              _row(
                  Icons.contrast_rounded,
                  dmLocal('Appearance & accessibility', 'थीम और सुविधा'),
                  'Light / Dark, language and larger text',
                  () => _open(const AppearanceScreen())),
              _row(
                  Icons.tune_rounded,
                  'Notification preferences',
                  'In-app trip alerts and emailed receipts',
                  () => _open(const NotificationPreferencesScreen())),
              const SizedBox(height: 18),
              TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out')),
              const SizedBox(height: 10),
              Text(
                  'Direct UPI payments are sent to the driver and confirmed manually. DriveMate does not automatically verify bank payments or dispatch emergency services.',
                  style: dmCaption(size: 10.5)),
            ]));
  }

  Widget _stat(String value, String label) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: dmHeading(size: 22)),
        const SizedBox(height: 4),
        Text(label, style: dmCaption(size: 10))
      ]);
  Widget _quick(IconData icon, String label, VoidCallback action) => Expanded(
      child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(18),
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: dmSurface(),
              child: Column(children: [
                Icon(icon, size: 27, color: softWhite),
                const SizedBox(height: 10),
                Text(label,
                    style: TextStyle(
                        color: softWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))
              ]))));
  Widget _row(IconData icon, String title, String sub, VoidCallback action) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              leading: Icon(icon, color: softWhite),
              title: Text(title,
                  style: TextStyle(
                      color: softWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(sub, style: dmCaption(size: 11)),
              trailing: Icon(Icons.chevron_right_rounded, color: muted),
              onTap: action));
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _trip = true, _receipts = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await HubService.account();
      final p = d['preferences'] as Map;
      if (mounted) {
        setState(() {
          _trip = p['trip_updates'] == true;
          _receipts = p['email_receipts'] == true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save(String key, bool value) async {
    try {
      await HubService.preferences({key: value});
      if (mounted) {
        setState(() {
          if (key == 'trip_updates') {
            _trip = value;
          } else {
            _receipts = value;
          }
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
        backgroundColor: navy,
        appBar: AppBar(title: const Text('Notification preferences')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('In-app trip alerts'),
              value: _trip,
              onChanged: (v) => _save('trip_updates', v)),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Email receipts'),
              subtitle: const Text(
                  'Automatic receipt after the driver manually confirms cash/UPI received. SMTP must be configured.'),
              value: _receipts,
              onChanged: (v) => _save('email_receipts', v)),
          const SizedBox(height: 18),
          const Text(
              'Trip-start security codes are always required. In-app alerts are not Android background push/FCM.'),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: danger))
          ],
        ]));
  }
}
