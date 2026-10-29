import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'rides_service.dart';

/// Account-scoped, read-only offline cache. Writes always require the API.
/// v6's ownerless device garage is imported ONLY after explicit confirmation;
/// it must never silently attach another person's cars to a new login.
class VehicleStore {
  static const String _legacyKey = 'dm_vehicles_v1';

  static Future<String?> _accountKey() async {
    final user = await AuthService.cachedUser();
    if (user == null || user['role']?.toString().toUpperCase() != 'CUSTOMER') {
      return null;
    }
    return 'dm_vehicles_v8_${Uri.encodeComponent(AuthService.backendScope)}_${user['id']}_${Uri.encodeComponent((user['email'] ?? '').toString().toLowerCase())}';
  }

  /// Fetches and caches the server garage. Failures propagate to the screen.
  static Future<List<VehicleModel>> sync() async {
    final key = await _accountKey();
    final vehicles = await RidesService.vehicles();
    if (key != null && key == await _accountKey()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          key, jsonEncode(vehicles.map((v) => v.toJson()).toList()));
    }
    return vehicles;
  }

  /// Convenient read for home/booking: offline data is clearly a cache, and
  /// only read while signed in to its owner. Authorization failures aren't
  /// treated as "offline".
  static Future<List<VehicleModel>> load() async {
    try {
      return await sync();
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      return cached();
    }
  }

  static Future<List<VehicleModel>> cached() async {
    final key = await _accountKey();
    if (key == null) return [];
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(key)).map(VehicleModel.fromJson).toList();
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  static Future<int> legacyCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_legacyKey)).length;
  }

  /// Call only after the user confirms that the ownerless v6 cars are theirs.
  /// On failure legacy data remains intact; retry skips already-imported cars.
  static Future<int> importLegacyVehicles() async {
    final owner = await _accountKey();
    if (owner == null) {
      throw ApiException('Sign in to a customer account to import cars.');
    }
    final prefs = await SharedPreferences.getInstance();
    final old = _decode(prefs.getString(_legacyKey));
    final existing = await RidesService.vehicles();
    final known = existing.map((v) => v.registration).toSet();
    var moved = 0;
    for (final entry in old) {
      if (owner != await _accountKey()) {
        throw ApiException(
            'Account changed. Please import again after signing in.');
      }
      final registration = (entry['registration'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\s'), '')
          .toUpperCase();
      if (registration.isEmpty || known.contains(registration)) continue;
      await RidesService.saveVehicle(VehicleModel(
        make: (entry['make'] ?? '').toString(),
        model: (entry['model'] ?? '').toString(),
        registration: registration,
        fuel: (entry['fuel'] ?? 'PETROL').toString().toUpperCase(),
        transmission:
            (entry['transmission'] ?? 'MANUAL').toString().toUpperCase(),
        seats: int.tryParse((entry['seats'] ?? '5').toString()) ?? 5,
        isDefault: entry['isDefault'] == true,
      ));
      known.add(registration);
      moved++;
    }
    if (owner == await _accountKey()) await prefs.remove(_legacyKey);
    await sync();
    return moved;
  }
}
