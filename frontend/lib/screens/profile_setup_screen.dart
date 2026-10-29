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
import 'driver_personal_profile_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Rider profile completion: photo, address, state → city, PIN code and an
/// emergency contact. Drivers are forwarded into the driver wizard instead, so
/// both roles always land on the right screen.
class ProfileSetupScreen extends StatefulWidget {
  final String name;
  final String role;
  const ProfileSetupScreen(
      {super.key, required this.name, this.role = 'CUSTOMER'});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();

  XFile? _photo;
  String? _state;
  String? _city;
  bool _saving = false;

  bool get _isDriver => widget.role.toUpperCase() == 'DRIVER';

  @override
  void initState() {
    super.initState();
    if (_isDriver) {
      // Drivers must never be stuck on the customer profile screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        replaceWith(context, DriverPersonalProfileScreen(name: widget.name));
      });
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _pincode.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
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

  void _chooseSource() {
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
              title: const Text('Take a photo'),
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_photo == null) {
      showDmMessage(context, 'Add a profile photo to continue.', error: true);
      return;
    }
    if (_state == null || _city == null) {
      showDmMessage(context, 'Select your state and city.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await AuthService.uploadProfilePhoto(_photo!.path);
      final result = await AuthService.saveProfile({
        'address': _address.text.trim(),
        'state': _state,
        'city': _city,
        'pincode': _pincode.text.trim(),
        'emergency_contact_name': _emergencyName.text.trim(),
        'emergency_contact_phone': _emergencyPhone.text.trim(),
      }, step: 'PROFILE');
      if (!mounted) return;
      final complete = result['profile_complete'] == true;
      showDmMessage(
          context,
          complete
              ? 'Profile complete. Welcome to DriveMate!'
              : 'Profile saved.');
      pushClean(context, HomeScreen(role: 'Customer', name: widget.name));
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
      backFallback: LoginScreen(role: widget.role),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DmEntrance(
              child: StepHeader(
                step: 1,
                total: 1,
                eyebrow: 'Rider profile',
                title: 'Complete your profile',
                subtitle:
                    'Photo, address and an emergency contact. All fields are required.',
              ),
            ),
            const SizedBox(height: 24),
            DmEntrance(
                delay: 70,
                child: _PhotoPicker(photo: _photo, onTap: _chooseSource)),
            const SizedBox(height: 22),
            DmEntrance(
              delay: 120,
              child: DmField(
                controller: _address,
                hint: 'House / street address',
                icon: Icons.location_on_outlined,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    DmValidators.requiredText(value, 'Address'),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 160,
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
                  _city = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            DmEntrance(
              delay: 200,
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
                textInputAction: TextInputAction.done,
                validator: DmValidators.phone,
              ),
            ),
            const SizedBox(height: 18),
            DmEntrance(
              delay: 360,
              child: DmPrimaryButton(
                  label: 'Save and continue',
                  loading: _saving,
                  onPressed: _save),
            ),
            const SizedBox(height: 14),
            const DmEntrance(
              delay: 400,
              child: DmInfoBox(
                text:
                    'Your emergency contact is used only in a safety situation and is never shown to a driver.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular photo picker with a red "add" badge.
class _PhotoPicker extends StatelessWidget {
  final XFile? photo;
  final VoidCallback onTap;
  const _PhotoPicker({required this.photo, required this.onTap});

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
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: panel,
                    border: Border.all(
                        color: photo == null ? hairline : red,
                        width: photo == null ? 1 : 2),
                    image: photo == null
                        ? null
                        : DecorationImage(
                            image: FileImage(File(photo!.path)),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: photo == null
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
