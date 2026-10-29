import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../utils/validators.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/step_progress.dart';
import 'driver_documents_screen.dart';
import 'driver_personal_profile_screen.dart';

/// DRIVER REGISTRATION - STEP 3 of 5: driving details.
///
/// Licence number, expiry, experience and the capability set that the future
/// matching system will filter on (transmission, vehicle type, highway, night,
/// outstation).
class DriverDrivingDetailsScreen extends StatefulWidget {
  final String name;
  const DriverDrivingDetailsScreen({super.key, required this.name});

  @override
  State<DriverDrivingDetailsScreen> createState() =>
      _DriverDrivingDetailsScreenState();
}

class _DriverDrivingDetailsScreenState
    extends State<DriverDrivingDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenceNumber = TextEditingController();
  final _experience = TextEditingController(text: '1');

  DateTime? _licenceExpiry;
  bool _saving = false;

  final Map<String, bool> _skills = {
    'manual_transmission': false,
    'automatic_transmission': false,
    'sedan': false,
    'suv': false,
    'luxury': false,
    'highway': false,
    'night_driving': false,
    'outstation': false,
  };

  bool get _hasTransmission =>
      _skills['manual_transmission']! || _skills['automatic_transmission']!;
  bool get _hasVehicleType =>
      _skills['sedan']! || _skills['suv']! || _skills['luxury']!;

  @override
  void initState() {
    super.initState();
    _restoreSaved();
  }

  /// Restores licence details and skills already stored on the server.
  Future<void> _restoreSaved() async {
    try {
      final data = await AuthService.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted || profile.isEmpty) return;
      setState(() {
        _licenceNumber.text = (profile['licence_number'] ?? '').toString();
        final expiry = (profile['licence_expiry'] ?? '').toString();
        if (expiry.isNotEmpty) _licenceExpiry = DateTime.tryParse(expiry);
        final years = profile['experience_years'];
        if (years is num && years > 0) {
          _experience.text = years.toInt().toString();
        }
        for (final key in _skills.keys) {
          if (profile[key] == true) _skills[key] = true;
        }
      });
    } catch (_) {
      // Nothing saved yet (or offline): the form simply starts empty.
    }
  }

  @override
  void dispose() {
    _licenceNumber.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _licenceExpiry ?? DateTime(now.year + 5, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 30),
      helpText: 'Select licence expiry date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
              primary: red, surface: panel, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (selected != null) setState(() => _licenceExpiry = selected);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_licenceExpiry == null) {
      showDmMessage(context, 'Select your licence expiry date.', error: true);
      return;
    }
    if (!_licenceExpiry!.isAfter(DateTime.now())) {
      showDmMessage(context, 'Your licence expiry date must be in the future.',
          error: true);
      return;
    }
    if (!_hasTransmission) {
      showDmMessage(context,
          'Select at least one transmission type (Manual or Automatic).',
          error: true);
      return;
    }
    if (!_hasVehicleType) {
      showDmMessage(context, 'Select at least one vehicle type you can drive.',
          error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await AuthService.saveProfile({
        'step': 'DRIVING',
        'licence_number': _licenceNumber.text.trim(),
        'licence_expiry': DmDateField.toApiDate(_licenceExpiry!),
        'experience_years': int.tryParse(_experience.text.trim()) ?? 0,
        ..._skills,
      });
      if (!mounted) return;
      showDmMessage(context, 'Driving details saved.');
      // push (not replace) so back/swipe-back returns to this step.
      Navigator.of(context)
          .push(dmRoute(DriverDocumentsScreen(name: widget.name)));
    } on ApiException catch (error) {
      if (!mounted) return;
      final missing = error.missingFields.isEmpty
          ? ''
          : '\n• ${error.missingFields.join('\n• ')}';
      showDmMessage(context, '${error.message}$missing', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      // Back always works: previous screen if there is one, else step 2.
      backFallback: DriverPersonalProfileScreen(name: widget.name),
      backResult: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StepHeader(
              step: 3,
              title: 'Driving details',
              subtitle:
                  'Your licence and the capabilities we use to match you with the right car.',
            ),
            const SizedBox(height: 24),
            DmField(
              controller: _licenceNumber,
              hint: 'Driving licence number',
              icon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  DmValidators.requiredText(value, 'Licence number'),
            ),
            const SizedBox(height: 12),
            DmDateField(
              hint: 'Licence expiry date',
              value: _licenceExpiry,
              onTap: _pickExpiry,
              validator: (_) =>
                  _licenceExpiry == null ? 'Licence expiry is required' : null,
            ),
            const SizedBox(height: 12),
            DmField(
              controller: _experience,
              hint: 'Driving experience (years)',
              icon: Icons.timelapse_outlined,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              validator: DmValidators.years,
            ),
            const SizedBox(height: 22),
            const DmSectionLabel('Transmission you can drive (required)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DmSelectChip(
                  label: 'Manual',
                  icon: Icons.settings_outlined,
                  selected: _skills['manual_transmission']!,
                  onSelected: (value) =>
                      setState(() => _skills['manual_transmission'] = value),
                ),
                DmSelectChip(
                  label: 'Automatic',
                  icon: Icons.auto_mode_outlined,
                  selected: _skills['automatic_transmission']!,
                  onSelected: (value) =>
                      setState(() => _skills['automatic_transmission'] = value),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const DmSectionLabel('Vehicle types you can drive (required)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DmSelectChip(
                  label: 'Sedan',
                  icon: Icons.directions_car_outlined,
                  selected: _skills['sedan']!,
                  onSelected: (value) =>
                      setState(() => _skills['sedan'] = value),
                ),
                DmSelectChip(
                  label: 'SUV',
                  icon: Icons.airport_shuttle_outlined,
                  selected: _skills['suv']!,
                  onSelected: (value) => setState(() => _skills['suv'] = value),
                ),
                DmSelectChip(
                  label: 'Luxury cars',
                  icon: Icons.diamond_outlined,
                  selected: _skills['luxury']!,
                  onSelected: (value) =>
                      setState(() => _skills['luxury'] = value),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const DmSectionLabel('Additional capabilities (optional)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DmSelectChip(
                  label: 'Highway driving',
                  icon: Icons.add_road_outlined,
                  selected: _skills['highway']!,
                  onSelected: (value) =>
                      setState(() => _skills['highway'] = value),
                ),
                DmSelectChip(
                  label: 'Night driving',
                  icon: Icons.nights_stay_outlined,
                  selected: _skills['night_driving']!,
                  onSelected: (value) =>
                      setState(() => _skills['night_driving'] = value),
                ),
                DmSelectChip(
                  label: 'Outstation trips',
                  icon: Icons.route_outlined,
                  selected: _skills['outstation']!,
                  onSelected: (value) =>
                      setState(() => _skills['outstation'] = value),
                ),
              ],
            ),
            const SizedBox(height: 22),
            DmPrimaryButton(
                label: 'Continue to documents',
                loading: _saving,
                onPressed: _save),
            const SizedBox(height: 12),
            const DmInfoBox(
              text:
                  'These capabilities decide which booking requests you can receive. For example, an '
                  'automatic SUV booking is only offered to drivers who selected both.',
            ),
          ],
        ),
      ),
    );
  }
}
