import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/rides_service.dart';
import '../services/vehicle_store.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';

/// YOUR GARAGE — the customer's cars, now stored on the server.
///
/// v7: the list comes from `/api/rides/vehicles/`, so the same car is there on
/// every device you sign in from. When the phone is offline the last synced list
/// is shown read-only, and the screen says exactly that.
class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  List<VehicleModel> _vehicles = const [];
  bool _loading = true;
  bool _offline = false;
  String? _error;
  int _legacyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await VehicleStore.sync();
      final legacy = await VehicleStore.legacyCount();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _legacyCount = legacy;
        _offline = false;
        _loading = false;
      });
    } on ApiException catch (error) {
      final cached = await VehicleStore.cached();
      if (!mounted) return;
      setState(() {
        _vehicles = cached;
        _error = error.statusCode == 401 || error.statusCode == 403
            ? error.message
            : null;
        _offline = true;
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({VehicleModel? existing}) async {
    final saved = await dmShowSheet<VehicleModel>(
      context,
      title: existing == null ? 'Add your car' : 'Edit ${existing.displayName}',
      subtitle: 'The driver always drives the car you register here.',
      child: _VehicleForm(existing: existing),
    );
    if (saved == null) return;

    await _load();
    if (mounted) {
      showDmMessage(context,
          existing == null ? 'Vehicle added and synced.' : 'Vehicle updated.');
    }
  }

  Future<void> _importLegacy() async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: panel,
              title: const Text('Import v6 cars?'),
              content: Text(
                  'These cars were saved on this phone without an account owner. Import only if they belong to you. '
                  'They will be attached to the customer account currently signed in.',
                  style: dmSubtitle(size: 12.5)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Not now')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('They are mine')),
              ],
            ));
    if (yes != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final count = await VehicleStore.importLegacyVehicles();
      if (mounted) {
        showDmMessage(
            context, '$count cars imported. Duplicates were skipped.');
      }
    } on ApiException catch (error) {
      if (mounted) {
        showDmMessage(
            context, '${error.message} Local copies are kept; you can retry.',
            error: true);
      }
    }
    await _load();
  }

  Future<void> _delete(VehicleModel vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Remove vehicle?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
            '${vehicle.displayName} (${vehicle.registration}) will be removed from your account.',
            style: dmSubtitle(size: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await RidesService.deleteVehicle(vehicle.id!);
      await _load();
      if (mounted) showDmMessage(context, 'Vehicle removed.');
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    }
  }

  Future<void> _makeDefault(VehicleModel vehicle) async {
    try {
      await RidesService.saveVehicle(
        VehicleModel(
          id: vehicle.id,
          make: vehicle.make,
          model: vehicle.model,
          registration: vehicle.registration,
          fuel: vehicle.fuel,
          transmission: vehicle.transmission,
          seats: vehicle.seats,
          isDefault: true,
        ),
      );
      await _load();
      if (mounted) {
        showDmMessage(
            context, '${vehicle.displayName} is now your default car.');
      }
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DmEntrance(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR GARAGE',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: red)),
                const SizedBox(height: 8),
                const Text('Your vehicles',
                    style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        height: 1.12)),
                const SizedBox(height: 6),
                Text(
                    'Saved to your DriveMate account - the same cars on every device you sign in from.',
                    style: TextStyle(fontSize: 13, color: muted)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_offline)
            const DmInfoBox(
              icon: Icons.cloud_off_rounded,
              color: warning,
              text:
                  'Offline: showing the last synced list. Reconnect to add, edit or remove a car.',
            )
          else
            const DmInfoBox(
              icon: Icons.cloud_done_outlined,
              text:
                  'Synced with your account. The driver always drives the car you pick here.',
            ),
          const SizedBox(height: 18),
          if (!_offline && _legacyCount > 0) ...[
            DmListCard(
                icon: Icons.file_download_outlined,
                title: 'Import $_legacyCount cars from v6',
                body:
                    'Import only if these old device-only cars belong to you. Confirmation is required.',
                onTap: _importLegacy),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            DmErrorState(
                title: 'Garage unavailable', message: _error!, onRetry: _load)
          else if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator()))
          else if (_vehicles.isEmpty)
            DmEmptyState(
              icon: Icons.directions_car_outlined,
              title: 'No vehicles yet',
              body:
                  'Add the car you want a driver to drive. You can keep more than one and mark a default.',
              actionLabel: _offline ? null : 'Add your first car',
              onAction: _offline ? null : _openEditor,
            )
          else ...[
            for (final vehicle in _vehicles) ...[
              _VehicleCard(
                vehicle: vehicle,
                onEdit: _offline ? null : () => _openEditor(existing: vehicle),
                onDelete: _offline ? null : () => _delete(vehicle),
                onDefault: _offline ? null : () => _makeDefault(vehicle),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _offline ? null : _openEditor,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add another car',
                    style:
                        TextStyle(fontSize: 13.4, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const DmSectionHeader(title: 'What we need from you'),
          const DmListCard(
            icon: Icons.badge_outlined,
            title: 'Registration number',
            body: 'Printed exactly as on the number plate, e.g. HR 26 AB 1234.',
            accent: info,
          ),
          const SizedBox(height: 11),
          const DmListCard(
            icon: Icons.local_gas_station_outlined,
            title: 'Fuel & transmission',
            body: 'Used to match a driver who is comfortable with your car.',
            accent: warning,
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onDefault;

  const _VehicleCard(
      {required this.vehicle, this.onEdit, this.onDelete, this.onDefault});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmEntrance(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration:
            dmSurface(color: panel, glow: vehicle.isDefault ? red : null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.directions_car_filled_rounded,
                      color: red, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vehicle.displayName, style: dmHeading(size: 16.5)),
                      const SizedBox(height: 3),
                      Text(
                          '${vehicle.fuelLabel} • ${vehicle.transmissionLabel} • ${vehicle.seats} seats',
                          style: dmCaption(size: 11.4)),
                    ],
                  ),
                ),
                if (vehicle.isDefault)
                  const DmPill(label: 'DEFAULT', color: red, solid: true),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: panel3,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.pin_outlined, size: 15, color: muted),
                  const SizedBox(width: 9),
                  Text(
                    vehicle.registration,
                    style: const TextStyle(
                        fontSize: 13.6,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit',
                        style: TextStyle(
                            fontSize: 12.4, fontWeight: FontWeight.w700)),
                  ),
                ),
                if (!vehicle.isDefault)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onDefault,
                      icon: const Icon(Icons.star_outline_rounded, size: 16),
                      label: const Text('Default',
                          style: TextStyle(
                              fontSize: 12.4, fontWeight: FontWeight.w700)),
                    ),
                  ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: danger),
                    label: const Text('Remove',
                        style: TextStyle(
                            fontSize: 12.4,
                            fontWeight: FontWeight.w700,
                            color: danger)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form shown inside the standard bottom sheet.
class _VehicleForm extends StatefulWidget {
  final VehicleModel? existing;
  const _VehicleForm({this.existing});

  @override
  State<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<_VehicleForm> {
  static final List<String> _fuels = [
    'PETROL',
    'DIESEL',
    'CNG',
    'ELECTRIC',
    'HYBRID'
  ];
  static final List<String> _transmissions = ['MANUAL', 'AUTOMATIC'];
  static final List<int> _seatOptions = [4, 5, 6, 7];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _registration;

  late String _fuel;
  late String _transmission;
  late int _seatCount;
  late bool _isDefault;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _make = TextEditingController(text: existing?.make ?? '');
    _model = TextEditingController(text: existing?.model ?? '');
    _registration = TextEditingController(text: existing?.registration ?? '');
    _fuel = existing?.fuel ?? 'PETROL';
    _transmission = existing?.transmission ?? 'MANUAL';
    _seatCount = existing?.seats ?? 5;
    _isDefault = existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _registration.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final stored = await RidesService.saveVehicle(VehicleModel(
        id: widget.existing?.id,
        make: _make.text.trim(),
        model: _model.text.trim(),
        registration: _registration.text.trim().toUpperCase(),
        fuel: _fuel,
        transmission: _transmission,
        seats: _seatCount,
        isDefault: _isDefault,
      ));
      if (mounted) Navigator.pop(context, stored);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DmField(
            controller: _make,
            hint: 'Car make — Maruti Suzuki',
            icon: Icons.factory_outlined,
            textInputAction: TextInputAction.next,
            validator: (value) => (value == null || value.trim().length < 2)
                ? 'Enter the car make'
                : null,
          ),
          const SizedBox(height: 14),
          DmField(
            controller: _model,
            hint: 'Model — Swift Dzire',
            icon: Icons.directions_car_outlined,
            textInputAction: TextInputAction.next,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Enter the model'
                : null,
          ),
          const SizedBox(height: 14),
          DmField(
            controller: _registration,
            hint: 'Registration — HR 26 AB 1234',
            icon: Icons.pin_outlined,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9 ]'))
            ],
            onChanged: (value) => _registration.value = TextEditingValue(
              text: value.toUpperCase(),
              selection: TextSelection.collapsed(offset: value.length),
            ),
            validator: (value) {
              final text = (value ?? '').replaceAll(' ', '');
              if (text.length < 6 || text.length > 16) {
                return 'Enter a 6–16 character registration number';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          const DmSectionLabel('Fuel'),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final fuel in _fuels)
                DmSelectChip(
                  label: fuel[0] + fuel.substring(1).toLowerCase(),
                  selected: _fuel == fuel,
                  onSelected: (_) => setState(() => _fuel = fuel),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const DmSectionLabel('Transmission'),
          Wrap(
            spacing: 9,
            children: [
              for (final item in _transmissions)
                DmSelectChip(
                  label: item[0] + item.substring(1).toLowerCase(),
                  selected: _transmission == item,
                  onSelected: (_) => setState(() => _transmission = item),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const DmSectionLabel('Seats'),
          Wrap(
            spacing: 9,
            children: [
              for (final count in _seatOptions)
                DmSelectChip(
                  label: '$count seats',
                  selected: _seatCount == count,
                  onSelected: (_) => setState(() => _seatCount = count),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            value: _isDefault,
            onChanged: (value) => setState(() => _isDefault = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('Use as my default car',
                style: TextStyle(fontSize: 13.6, fontWeight: FontWeight.w600)),
            subtitle: Text('Booking will pick this car first.',
                style: dmCaption(size: 11.4)),
          ),
          const SizedBox(height: 10),
          if (_error != null) ...[
            DmInfoBox(text: _error!, color: danger),
            const SizedBox(height: 12)
          ],
          DmPrimaryButton(
            loading: _saving,
            label: widget.existing == null ? 'Add vehicle' : 'Save changes',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
