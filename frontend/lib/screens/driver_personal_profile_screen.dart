import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/india_locations.dart';
import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../utils/validators.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/dm_select_field.dart';
import '../widgets/step_progress.dart';
import 'driver_driving_details_screen.dart';
import 'home_screen.dart';

/// DRIVER REGISTRATION — STEP 2 of 5: personal profile.
///
/// Photo, date of birth, address, state → city, PIN code, emergency contact and
/// languages. Every field is required; the backend re-checks the whole step and
/// refuses to advance while anything is missing.
class DriverPersonalProfileScreen extends StatefulWidget {
  final String name;
  const DriverPersonalProfileScreen({super.key, required this.name});

  @override
  State<DriverPersonalProfileScreen> createState() =>
      _DriverPersonalProfileScreenState();
}

class _DriverPersonalProfileScreenState
    extends State<DriverPersonalProfileScreen> {
  static final List<String> _languageOptions = [
    'Hindi',
    'English',
    'Urdu',
    'Punjabi',
    'Bengali',
    'Marathi',
    'Gujarati',
    'Tamil',
    'Telugu',
    'Kannada',
    'Malayalam',
  ];

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _intro = TextEditingController();

  final Set<String> _languages = const {};
  String? _state;
  String? _city;
  XFile? _photo;
  DateTime? _dob;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _restoreSaved();
  }

  /// Pulls back whatever the driver already saved, so leaving this screen and
  /// returning from the dashboard never means typing everything again.
  Future<void> _restoreSaved() async {
    try {
      final data = await AuthService.getProfile();
      final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted || profile.isEmpty) return;
      setState(() {
        _address.text = (profile['address'] ?? '').toString();
        _pincode.text = (profile['pincode'] ?? '').toString();
        _emergencyName.text =
            (profile['emergency_contact_name'] ?? '').toString();
        _emergencyPhone.text =
            (profile['emergency_contact_phone'] ?? '').toString();
        _intro.text = (profile['introduction'] ?? '').toString();

        final state = (profile['state'] ?? '').toString();
        if (state.isNotEmpty) _state = state;
        final city = (profile['city'] ?? '').toString();
        if (city.isNotEmpty) _city = city;

        final languages = profile['languages'];
        if (languages is List && languages.isNotEmpty) {
          _languages
            ..clear()
            ..addAll(languages.map((language) => language.toString()));
        }
        final dob = (profile['date_of_birth'] ?? '').toString();
        if (dob.isNotEmpty) _dob = DateTime.tryParse(dob);
      });
    } catch (_) {
      // Nothing saved yet (or offline): the form simply starts empty.
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _pincode.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _intro.dispose();
    super.dispose();
  }

  int? get _age {
    if (_dob == null) return null;
    final today = DateTime.now();
    var years = today.year - _dob!.year;
    if (today.month < _dob!.month ||
        (today.month == _dob!.month && today.day < _dob!.day)) {
      years -= 1;
    }
    return years;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
          source: source, maxWidth: 1400, imageQuality: 82);
      if (file != null) setState(() => _photo = file);
    } catch (_) {
      if (mounted) {
        showDmMessage(
            context, 'Could not open the camera/gallery on this device.',
            error: true);
      }
    }
  }

  void _choosePhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: red),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: red),
              title: const Text('Take a selfie'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: 'Select your date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
              primary: red, surface: panel, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (selected != null) setState(() => _dob = selected);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      showDmMessage(context, 'A profile photo is required.', error: true);
      return;
    }
    if (_dob == null) {
      showDmMessage(context, 'Select your date of birth.', error: true);
      return;
    }
    if ((_age ?? 0) < 18) {
      showDmMessage(context, 'Driver applicants must be at least 18 years old.',
          error: true);
      return;
    }
    if (_state == null || _city == null) {
      showDmMessage(context, 'Select your state and city.', error: true);
      return;
    }
    if (_languages.isEmpty) {
      showDmMessage(context, 'Select at least one language you speak.',
          error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await AuthService.uploadProfilePhoto(_photo!.path);
      await AuthService.saveProfile({
        'step': 'PERSONAL',
        'date_of_birth': DmDateField.toApiDate(_dob!),
        'address': _address.text.trim(),
        'state': _state,
        'city': _city,
        'pincode': _pincode.text.trim(),
        'service_area': _city,
        'emergency_contact_name': _emergencyName.text.trim(),
        'emergency_contact_phone': _emergencyPhone.text.trim(),
        'languages': _languages.join(', '),
        'introduction': _intro.text.trim(),
      });
      if (!mounted) return;
      showDmMessage(context, 'Personal profile saved.');
      // push (not replace) so the back arrow and swipe-back both return here.
      Navigator.of(context)
          .push(dmRoute(DriverDrivingDetailsScreen(name: widget.name)));
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
    final cities = IndiaLocations.citiesFor(_state);

    return DmScreen(
      showBack: true,
      // Always goes somewhere useful: back to the previous screen when there is
      // one, otherwise to the driver dashboard (where "Continue" resumes here).
      backFallback: HomeScreen(role: 'Driver', name: widget.name),
      // Tells the dashboard "details may have changed" so it refreshes.
      backResult: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DmEntrance(
              child: StepHeader(
                step: 2,
                title: 'Personal profile',
                subtitle:
                    'Tell us who you are and how to reach your emergency contact.',
              ),
            ),
            const SizedBox(height: 24),
            DmEntrance(
                delay: 60,
                child: _Photo(reference: _photo, onTap: _choosePhotoSource)),
            const SizedBox(height: 20),
            DmEntrance(
              delay: 100,
              child: DmDateField(
                hint: 'Date of birth',
                value: _dob,
                onTap: _pickDob,
                validator: (_) =>
                    _dob == null ? 'Date of birth is required' : null,
              ),
            ),
            if (_dob != null && (_age ?? 0) < 18)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('You must be 18 or older to apply.',
                    style: TextStyle(color: danger, fontSize: 11.5)),
              ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 140,
              child: DmField(
                controller: _address,
                hint: 'House / street address',
                icon: Icons.home_outlined,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    DmValidators.requiredText(value, 'Address'),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 180,
              child: DmSelectField(
                hint: 'State / Union Territory',
                icon: Icons.map_outlined,
                value: _state,
                options: IndiaLocations.states,
                searchHint: 'Search state',
                validator: (value) =>
                    _state == null ? 'State is required' : null,
                onChanged: (value) => setState(() {
                  _state = value;
                  _city = null; // city list depends on the state
                }),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 220,
              child: DmSelectField(
                hint: 'City',
                icon: Icons.location_city_outlined,
                value: _city,
                options: cities,
                enabled: _state != null,
                disabledHint: 'Select a state first',
                searchHint: 'Search city',
                validator: (value) => _city == null ? 'City is required' : null,
                onChanged: (value) => setState(() => _city = value),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 240,
              child: DmField(
                controller: _pincode,
                hint: 'PIN code (6 digits)',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                validator: DmValidators.pincode,
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 280,
              child: DmField(
                controller: _emergencyName,
                hint: 'Emergency contact name',
                icon: Icons.contact_emergency_outlined,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    DmValidators.requiredText(value, 'Emergency contact name'),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 320,
              child: DmField(
                controller: _emergencyPhone,
                hint: 'Emergency contact number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: DmValidators.phone,
              ),
            ),
            const SizedBox(height: 20),
            const DmEntrance(
                delay: 360, child: DmSectionLabel('Languages you speak')),
            DmEntrance(
              delay: 380,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _languageOptions
                    .map(
                      (language) => DmSelectChip(
                        label: language,
                        selected: _languages.contains(language),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _languages.add(language);
                          } else {
                            _languages.remove(language);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 18),
            DmEntrance(
              delay: 420,
              child: DmField(
                controller: _intro,
                hint: 'Short introduction (optional)',
                icon: Icons.notes_outlined,
                maxLines: 3,
                maxLength: 400,
                helper:
                    'Example: 6 years of driving experience, comfortable with automatic and manual cars.',
              ),
            ),
            const SizedBox(height: 20),
            DmEntrance(
              delay: 460,
              child: DmPrimaryButton(
                  label: 'Continue to driving details',
                  loading: _saving,
                  onPressed: _save),
            ),
            const SizedBox(height: 12),
            const DmEntrance(
              delay: 500,
              child: DmInfoBox(
                text:
                    'Every field above is required before the next step unlocks. Your data is used for '
                    'verification and safety only.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  final XFile? reference;
  final VoidCallback onTap;
  const _Photo({required this.reference, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Center(
      child: Column(
        children: [
          DmTapScale(
            onTap: onTap,
            scale: 0.94,
            child: Stack(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: panel,
                    border: Border.all(
                        color: reference == null ? hairline : red,
                        width: reference == null ? 1 : 2),
                    image: reference == null
                        ? null
                        : DecorationImage(
                            image: FileImage(File(reference!.path)),
                            fit: BoxFit.cover),
                  ),
                  child: reference == null
                      ? const Icon(Icons.add_a_photo_outlined,
                          color: red, size: 30)
                      : null,
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: red,
                      shape: BoxShape.circle,
                      border: Border.all(color: navy, width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Profile photo (required)', style: dmCaption(size: 11.5)),
        ],
      ),
    );
  }
}
