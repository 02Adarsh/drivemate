import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import 'auth_service.dart';

/// Client models + the API layer for the v7 booking engine.
///
/// Everything here mirrors `backend/rides/` exactly: the server decides fares,
/// who may accept a request and when a trip can move to the next state. The app
/// only renders what it is told.

// ---------------------------------------------------------------------------
// Money helpers
// ---------------------------------------------------------------------------

double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String dmMoney(num? amount) {
  final value = (amount ?? 0).toDouble();
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.005) {
    return '₹${rounded.toStringAsFixed(0)}';
  }
  return '₹${value.toStringAsFixed(2)}';
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class VehicleModel {
  final int? id;
  final String make;
  final String model;
  final String registration;
  final String fuel;
  final String transmission;
  final int seats;
  final bool isDefault;

  const VehicleModel({
    this.id,
    required this.make,
    required this.model,
    required this.registration,
    this.fuel = 'PETROL',
    this.transmission = 'MANUAL',
    this.seats = 5,
    this.isDefault = false,
  });

  String get displayName => '$make $model'.trim();

  factory VehicleModel.fromJson(Map<String, dynamic> json) => VehicleModel(
        id: json['id'] as int?,
        make: (json['make'] ?? '').toString(),
        model: (json['model'] ?? '').toString(),
        registration: (json['registration'] ?? '').toString(),
        fuel: (json['fuel'] ?? 'PETROL').toString(),
        transmission: (json['transmission'] ?? 'MANUAL').toString(),
        seats: (json['seats'] as num?)?.toInt() ?? 5,
        isDefault: json['is_default'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'make': make,
        'model': model,
        'registration': registration,
        'fuel': fuel,
        'transmission': transmission,
        'seats': seats,
        'is_default': isDefault,
      };

  String get fuelLabel =>
      fuel.isEmpty ? '' : fuel[0] + fuel.substring(1).toLowerCase();
  String get transmissionLabel => transmission.isEmpty
      ? ''
      : transmission[0] + transmission.substring(1).toLowerCase();
}

class BookingEventModel {
  final String kind;
  final String label;
  final String note;
  final DateTime? at;

  const BookingEventModel(
      {required this.kind, required this.label, this.note = '', this.at});

  factory BookingEventModel.fromJson(Map<String, dynamic> json) =>
      BookingEventModel(
        kind: (json['kind'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        note: (json['note'] ?? '').toString(),
        at: DateTime.tryParse((json['at'] ?? '').toString()),
      );

  IconData get icon {
    switch (kind) {
      case 'CREATED':
        return Icons.add_circle_outline_rounded;
      case 'ACCEPTED':
        return Icons.person_add_alt_1_rounded;
      case 'DECLINED':
        return Icons.person_remove_alt_1_rounded;
      case 'STARTED':
        return Icons.directions_car_filled_rounded;
      case 'COMPLETED':
        return Icons.flag_circle_rounded;
      case 'CANCELLED':
        return Icons.cancel_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}

class BookingPerson {
  final bool hasPhoto;
  final int id;
  final String name;
  final String phone;
  final String email;

  const BookingPerson(
      {required this.id,
      required this.name,
      this.hasPhoto = false,
      this.phone = '',
      this.email = ''});

  factory BookingPerson.fromJson(Map<String, dynamic> json) => BookingPerson(
        hasPhoto: json['has_profile_photo'] == true,
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
      );
}

class BookingModel {
  final Map<String, dynamic> extra;
  final int id;
  final String status;
  final String statusLabel;
  final String service;
  final String serviceLabel;
  final DateTime? scheduledAt;
  final int durationHours;
  final String pickup;
  final String dropAddress;
  final String notes;
  final double estimatedFare;
  final double? finalFare;
  final int platformFeePercent;
  final double driverPayout;
  final VehicleModel? vehicle;
  final BookingPerson? customer;
  final BookingPerson? driver;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String cancelReason;
  final bool isOpen;
  final bool isActive;
  final bool isDemo;
  final bool canAccept;
  final bool canCancel;
  final bool canStart;
  final bool canComplete;
  final List<BookingEventModel> events;

  const BookingModel({
    this.extra = const {},
    required this.id,
    required this.status,
    required this.statusLabel,
    required this.service,
    required this.serviceLabel,
    this.scheduledAt,
    this.durationHours = 4,
    this.pickup = '',
    this.dropAddress = '',
    this.notes = '',
    this.estimatedFare = 0,
    this.finalFare,
    this.platformFeePercent = 18,
    this.driverPayout = 0,
    this.vehicle,
    this.customer,
    this.driver,
    this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason = '',
    this.isOpen = false,
    this.isActive = false,
    this.isDemo = false,
    this.canAccept = false,
    this.canCancel = false,
    this.canStart = false,
    this.canComplete = false,
    this.events = const [],
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) => BookingModel(
        extra: json,
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: (json['status'] ?? 'REQUESTED').toString(),
        statusLabel:
            (json['status_label'] ?? 'Searching for a driver').toString(),
        service: (json['service'] ?? 'BOOK_NOW').toString(),
        serviceLabel: (json['service_label'] ?? 'Book now').toString(),
        scheduledAt: DateTime.tryParse((json['scheduled_at'] ?? '').toString()),
        durationHours: (json['duration_hours'] as num?)?.toInt() ?? 4,
        pickup: (json['pickup'] ?? '').toString(),
        dropAddress: (json['drop_address'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        estimatedFare: _number(json['estimated_fare']),
        finalFare:
            json['final_fare'] == null ? null : _number(json['final_fare']),
        platformFeePercent:
            (json['platform_fee_percent'] as num?)?.toInt() ?? 18,
        driverPayout: _number(json['driver_payout']),
        vehicle: json['vehicle'] is Map
            ? VehicleModel.fromJson(
                (json['vehicle'] as Map).cast<String, dynamic>())
            : null,
        customer: json['customer'] is Map
            ? BookingPerson.fromJson(
                (json['customer'] as Map).cast<String, dynamic>())
            : null,
        driver: json['driver'] is Map
            ? BookingPerson.fromJson(
                (json['driver'] as Map).cast<String, dynamic>())
            : null,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
        acceptedAt: DateTime.tryParse((json['accepted_at'] ?? '').toString()),
        startedAt: DateTime.tryParse((json['started_at'] ?? '').toString()),
        completedAt: DateTime.tryParse((json['completed_at'] ?? '').toString()),
        cancelledAt: DateTime.tryParse((json['cancelled_at'] ?? '').toString()),
        cancelReason: (json['cancel_reason'] ?? '').toString(),
        isOpen: json['is_open'] == true,
        isActive: json['is_active'] == true,
        isDemo: json['is_demo'] == true,
        canAccept: json['can_accept'] == true,
        canCancel: json['can_cancel'] == true,
        canStart: json['can_start'] == true,
        canComplete: json['can_complete'] == true,
        events: ((json['events'] as List?) ?? [])
            .whereType<Map>()
            .map((item) =>
                BookingEventModel.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );

  double? _coordinate(String key) =>
      extra[key] == null ? null : _number(extra[key]);
  double? get pickupLatitude => _coordinate('pickup_latitude');
  double? get pickupLongitude => _coordinate('pickup_longitude');
  double? get dropLatitude => _coordinate('drop_latitude');
  double? get dropLongitude => _coordinate('drop_longitude');
  Map<String, dynamic>? get driverLocation => extra['driver_location'] is Map
      ? (extra['driver_location'] as Map).cast<String, dynamic>()
      : null;
  bool get otpRequired => extra['otp_required'] == true;
  bool get cashReceived => extra['cash_received_at'] != null;
  bool get paymentReceived => extra['payment_received'] == true || cashReceived;
  String get paymentMethod => (extra['payment_method'] ?? 'CASH').toString();
  String get paymentLabel => (extra['payment_label'] ??
          (cashReceived
              ? 'Cash received (driver-confirmed)'
              : 'Payment not confirmed'))
      .toString();
  Map<String, dynamic>? get upiPayment => extra['upi_payment'] is Map
      ? (extra['upi_payment'] as Map).cast<String, dynamic>()
      : null;
  bool get canViewUPI => extra['can_view_upi'] != false;
  bool get canPayUPI => extra['can_pay_upi'] is bool
      ? extra['can_pay_upi'] == true
      : status == 'COMPLETED' &&
          !paymentReceived &&
          (finalFare ?? estimatedFare) > 0;
  String get paymentBadge => cashReceived
      ? 'CASH RECEIVED'
      : paymentReceived && paymentMethod == 'UPI_DIRECT'
          ? 'UPI • DRIVER CONFIRMED'
          : extra['payment_status'] == 'NOT_REQUIRED'
              ? 'NO PAYMENT DUE'
              : extra['payment_status'] == 'AWAITING_DRIVER_CONFIRMATION'
                  ? 'UPI REPORTED • NOT CONFIRMED'
                  : 'PAYMENT NOT CONFIRMED';

  bool get canConfirmCash => extra['can_confirm_cash'] == true;
  bool get canRate => extra['can_rate'] == true;
  Map<String, dynamic>? get myRating => extra['my_rating'] is Map
      ? (extra['my_rating'] as Map).cast<String, dynamic>()
      : null;
  String get passengerName => (extra['passenger_name'] ?? '').toString();
  String get passengerPhone => (extra['passenger_phone'] ?? '').toString();
  String get businessLabel => (extra['business_label'] ?? '').toString();
  double get discountAmount => _number(extra['discount_amount']);

  Color get statusColor {
    switch (status) {
      case 'ACCEPTED':
        return info;
      case 'ONGOING':
        return success;
      case 'COMPLETED':
        return info;
      case 'CANCELLED':
      case 'EXPIRED':
        return danger;
      default:
        return warning;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'ACCEPTED':
        return Icons.person_add_alt_1_rounded;
      case 'ONGOING':
        return Icons.directions_car_filled_rounded;
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      case 'CANCELLED':
        return Icons.cancel_rounded;
      case 'EXPIRED':
        return Icons.timer_off_rounded;
      default:
        return Icons.radar_rounded;
    }
  }

  /// Human sentence for the state, used on cards and the detail screen.
  String get statusHint {
    switch (status) {
      case 'REQUESTED':
        return 'Eligible approved, online drivers can accept this request. GPS dispatch is not enabled.';
      case 'ACCEPTED':
        return '${driver?.name ?? "Your driver"} has accepted and is getting ready.';
      case 'ONGOING':
        return 'Trip in progress. It ends when the driver completes it in their app.';
      case 'COMPLETED':
        return 'Trip finished. The fare below is final.';
      case 'CANCELLED':
        return cancelReason.isEmpty
            ? 'This booking was cancelled.'
            : 'Cancelled: $cancelReason';
      case 'EXPIRED':
        return 'No driver accepted in time. Try again or schedule for later.';
      default:
        return statusLabel;
    }
  }

  bool get hasDriver => driver != null;
  bool get isFinished => ['COMPLETED', 'CANCELLED', 'EXPIRED'].contains(status);
}

class DriverSummaryModel {
  final bool isDemo;
  final bool available;
  final bool approved;
  final double today;
  final double week;
  final double lifetime;
  final int completedTrips;
  final int activeTrips;
  final int openRequests;
  final int platformFeePercent;
  final List<Map<String, dynamic>> daily;

  const DriverSummaryModel({
    this.isDemo = false,
    this.available = false,
    this.approved = false,
    this.today = 0,
    this.week = 0,
    this.lifetime = 0,
    this.completedTrips = 0,
    this.activeTrips = 0,
    this.openRequests = 0,
    this.platformFeePercent = 18,
    this.daily = const [],
  });

  factory DriverSummaryModel.fromJson(Map<String, dynamic> json) =>
      DriverSummaryModel(
        isDemo: json['is_demo'] == true,
        available: json['available'] == true,
        approved: json['approved'] == true,
        today: _number(json['today']),
        week: _number(json['week']),
        lifetime: _number(json['lifetime']),
        completedTrips: (json['completed_trips'] as num?)?.toInt() ?? 0,
        activeTrips: (json['active_trips'] as num?)?.toInt() ?? 0,
        openRequests: (json['open_requests'] as num?)?.toInt() ?? 0,
        platformFeePercent:
            (json['platform_fee_percent'] as num?)?.toInt() ?? 18,
        daily: ((json['daily'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(),
      );

  List<double> get barValues =>
      daily.map((day) => _number(day['payout'])).toList();

  List<String> get barLabels =>
      daily.map((day) => (day['label'] ?? '').toString()).toList();
}

class AppNotificationModel {
  final int id;
  final String title;
  final String body;
  final String kind;
  final int? bookingId;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotificationModel({
    required this.id,
    required this.title,
    this.body = '',
    this.kind = 'GENERAL',
    this.bookingId,
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) =>
      AppNotificationModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        kind: (json['kind'] ?? 'GENERAL').toString(),
        bookingId: (json['booking_id'] as num?)?.toInt(),
        isRead: json['is_read'] == true,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      );

  IconData get icon {
    switch (kind) {
      case 'BOOKING_REQUEST':
        return Icons.bolt_rounded;
      case 'BOOKING_ACCEPTED':
        return Icons.person_add_alt_1_rounded;
      case 'TRIP_STARTED':
        return Icons.directions_car_filled_rounded;
      case 'TRIP_COMPLETED':
        return Icons.flag_circle_rounded;
      case 'BOOKING_CANCELLED':
        return Icons.cancel_rounded;
      case 'PAYOUT':
        return Icons.payments_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color get color {
    switch (kind) {
      case 'BOOKING_REQUEST':
        return red;
      case 'BOOKING_ACCEPTED':
        return info;
      case 'TRIP_STARTED':
        return success;
      case 'TRIP_COMPLETED':
        return info;
      case 'BOOKING_CANCELLED':
        return danger;
      case 'PAYOUT':
        return success;
      default:
        return muted;
    }
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class BookingList {
  final List<BookingModel> active;
  final List<BookingModel> past;
  const BookingList({this.active = const [], this.past = const []});

  bool get isEmpty => active.isEmpty && past.isEmpty;

  factory BookingList.fromJson(Map<String, dynamic> json) => BookingList(
        active: ((json['active'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => BookingModel.fromJson(item.cast<String, dynamic>()))
            .toList(),
        past: ((json['past'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => BookingModel.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
}

class RidesService {
  /// A stable per-attempt retry key (128 random bits). The booking screen keeps
  /// it across connection retries, and the server returns the existing booking.
  static String newRequestKey() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ------------------------------------------------------------- vehicles
  static Future<List<VehicleModel>> vehicles() async {
    final data = await AuthService.getJson('rides/vehicles/');
    return ((data['results'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => VehicleModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  static Future<VehicleModel> saveVehicle(VehicleModel vehicle) async {
    final data = vehicle.id == null
        ? await AuthService.postJson('rides/vehicles/', vehicle.toJson())
        : await AuthService.putJson(
            'rides/vehicles/${vehicle.id}/', vehicle.toJson());
    return VehicleModel.fromJson(data);
  }

  static Future<void> deleteVehicle(int id) =>
      AuthService.deleteJson('rides/vehicles/$id/');

  // ------------------------------------------------------------ bookings
  static Future<BookingList> bookings() async =>
      BookingList.fromJson(await AuthService.getJson('rides/bookings/'));

  static Future<BookingModel> createBooking({
    required String service,
    required int durationHours,
    required String pickup,
    String dropAddress = '',
    String notes = '',
    DateTime? scheduledAt,
    required int vehicleId,
    required String requestKey,
    double? pickupLatitude,
    double? pickupLongitude,
    double? dropLatitude,
    double? dropLongitude,
    String passengerName = '',
    String passengerPhone = '',
    String promoCode = '',
    int? businessId,
  }) async {
    final data = await AuthService.postJson('rides/bookings/', {
      'service': service,
      'duration_hours': durationHours,
      'pickup': pickup,
      'drop_address': dropAddress,
      'notes': notes,
      if (scheduledAt != null)
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'vehicle_id': vehicleId,
      'request_key': requestKey,
      if (pickupLatitude != null)
        'pickup_latitude': pickupLatitude.toStringAsFixed(7),
      if (pickupLongitude != null)
        'pickup_longitude': pickupLongitude.toStringAsFixed(7),
      if (dropLatitude != null)
        'drop_latitude': dropLatitude.toStringAsFixed(7),
      if (dropLongitude != null)
        'drop_longitude': dropLongitude.toStringAsFixed(7),
      'passenger_name': passengerName,
      'passenger_phone': passengerPhone,
      if (promoCode.isNotEmpty) 'promo_code': promoCode,
      if (businessId != null) 'business_id': businessId,
    });
    return BookingModel.fromJson(data);
  }

  static Future<BookingModel> booking(int id) async =>
      BookingModel.fromJson(await AuthService.getJson('rides/bookings/$id/'));

  static Future<BookingModel> cancelBooking(int id,
          {String reason = ''}) async =>
      BookingModel.fromJson(await AuthService.postJson(
          'rides/bookings/$id/cancel/', {'reason': reason}));

  // -------------------------------------------------------------- driver
  static Future<bool> availability() async {
    final data = await AuthService.getJson('rides/availability/');
    return data['is_available'] == true;
  }

  static Future<bool> setAvailability(bool available) async {
    final data = await AuthService.postJson(
        'rides/availability/', {'available': available});
    return data['is_available'] == true;
  }

  static Future<List<BookingModel>> openRequests() async {
    final data = await AuthService.getJson('rides/requests/');
    return ((data['results'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => BookingModel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  static Future<BookingModel> acceptRequest(int id) async =>
      BookingModel.fromJson(
          await AuthService.postJson('rides/requests/$id/accept/'));

  static Future<void> declineRequest(int id) =>
      AuthService.postJson('rides/requests/$id/decline/');

  static Future<BookingList> trips() async =>
      BookingList.fromJson(await AuthService.getJson('rides/trips/'));

  static Future<BookingModel> startTrip(int id, {required String otp}) async =>
      BookingModel.fromJson(
          await AuthService.postJson('rides/trips/$id/start/', {'otp': otp}));

  static Future<BookingModel> completeTrip(int id) async =>
      BookingModel.fromJson(
          await AuthService.postJson('rides/trips/$id/complete/'));

  static Future<DriverSummaryModel> summary() async =>
      DriverSummaryModel.fromJson(await AuthService.getJson('rides/summary/'));

  // ------------------------------------------------------- notifications
  static Future<Map<String, dynamic>> notifications() =>
      AuthService.getJson('rides/notifications/');

  static Future<int> unreadCount() async {
    try {
      final data = await AuthService.getJson('rides/notifications/');
      return (data['unread'] as num?)?.toInt() ?? 0;
    } on ApiException {
      return 0;
    }
  }

  static Future<void> markRead(int id) =>
      AuthService.postJson('rides/notifications/$id/read/');

  static Future<void> markAllRead() =>
      AuthService.postJson('rides/notifications/read-all/');

  // ------------------------------------------------------------- pricing
  static Future<Map<String, dynamic>> adminOverview() =>
      AuthService.getJson('rides/admin/overview/');

  static Future<Map<String, dynamic>> pricing() =>
      AuthService.getJson('rides/pricing/');
}
