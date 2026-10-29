import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/hub_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_screen.dart';
import 'account_tools_screen.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});
  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  List<Map<String, dynamic>> _contacts = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await HubService.list('contacts');
      if (mounted) {
        setState(() =>
            _contacts = rows.where((p) => p['emergency'] == true).toList());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _dial(String phone) async {
    try {
      await HubService.dial(phone);
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
          Text(dmLocal('Safety centre', 'सुरक्षा केंद्र'),
              style: dmHeading(size: 29)),
          const SizedBox(height: 10),
          Text('Your safety comes first', style: dmHeading(size: 21)),
          const SizedBox(height: 18),
          DmPrimaryButton(
              label: 'Open emergency dialer — 112',
              icon: Icons.emergency_outlined,
              onPressed: () => _dial('112')),
          const SizedBox(height: 12),
          const DmInfoBox(
              color: danger,
              text:
                  'This opens your phone dialer; you choose whether to call. DriveMate does not automatically dispatch police/ambulance or silently place emergency calls.'),
          const SizedBox(height: 24),
          const DmSectionHeader(title: 'Trusted emergency contacts'),
          if (_error != null)
            DmListCard(
                icon: Icons.cloud_off_outlined,
                title: 'Contacts not synced',
                body: _error!,
                onTap: _load)
          else if (_contacts.isEmpty)
            const DmEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Add someone you trust',
                body:
                    'Save a family member or emergency contact and open their number in the phone dialer.'),
          for (final c in _contacts) ...[
            DmListCard(
                icon: Icons.call_outlined,
                title: c['name'].toString(),
                body: c['phone'].toString(),
                onTap: () => _dial(c['phone'].toString())),
            const SizedBox(height: 10)
          ],
          const SizedBox(height: 12),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                        dmRoute(const HubCollectionScreen(kind: 'contacts')));
                    await _load();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Manage trusted contacts'))),
          const SizedBox(height: 24),
          const DmSectionHeader(title: 'Built into your trip'),
          const DmListCard(
              icon: Icons.password_rounded,
              title: 'Mandatory customer start code',
              body:
                  'Only you can retrieve your trip code. The assigned driver must verify it on the server before the app starts the trip.'),
          const SizedBox(height: 12),
          const DmListCard(
              icon: Icons.person_pin_circle_outlined,
              title: 'Assigned-driver contact',
              body:
                  'After acceptance, the actual driver’s name and mobile number are shown. Tap to open the dialer.'),
          const SizedBox(height: 12),
          const DmListCard(
              icon: Icons.map_outlined,
              title: 'Permission-based location',
              body:
                  'Driver GPS updates are participant-only during an active trip. Last-update time is shown; an unavailable/stale position is not displayed as live movement.'),
          const SizedBox(height: 12),
          const DmListCard(
              icon: Icons.verified_user_outlined,
              title: 'Document review',
              body:
                  'Drivers pass the application, documents, consents and training workflow before taking requests.'),
        ]));
  }
}
