// Deterministic API fixtures for widget/client tests; never used by the app.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/config.dart';
import 'package:drivemate/screens/map_picker_screen.dart';
import 'package:drivemate/theme/appearance.dart';

Map<String, dynamic> carFixture({int id = 1, bool isDefault = true}) => {
      'id': id,
      'make': 'Maruti Suzuki',
      'model': 'Dzire',
      'registration': 'HR26AB1234',
      'fuel': 'PETROL',
      'transmission': 'MANUAL',
      'seats': 5,
      'is_default': isDefault,
    };

Map<String, dynamic> bookingFixture(
        {int id = 1, String status = 'REQUESTED'}) =>
    {
      'id': id, 'status': status,
      'status_label': const {
        'REQUESTED': 'Searching for a driver',
        'ACCEPTED': 'Driver assigned',
        'ONGOING': 'Trip in progress',
        'COMPLETED': 'Completed',
        'CANCELLED': 'Cancelled'
      }[status],
      'service': 'HOURLY', 'service_label': 'Hourly', 'scheduled_at': null,
      'duration_hours': 4,
      'pickup': 'Sector 15, near the metro gate', 'drop_address': '',
      'notes': '',
      // DRF commonly sends Decimal money as strings. The client must handle it.
      'estimated_fare': '575.00',
      'final_fare': status == 'COMPLETED' ? '575.00' : null,
      'platform_fee_percent': 18, 'driver_payout': '471.50',
      'vehicle': carFixture(),
      'customer': {
        'id': 1,
        'name': 'Adarsh Kumar',
        'phone': '+919000000001',
        'email': ''
      },
      'driver': status == 'REQUESTED'
          ? null
          : {
              'id': 2,
              'name': 'Ravi Kumar',
              'phone': '+919000000002',
              'email': ''
            },
      'created_at': '2026-10-12T10:00:00Z', 'is_open': status == 'REQUESTED',
      'is_active': ['ACCEPTED', 'ONGOING'].contains(status), 'is_demo': false,
      'can_cancel': ['REQUESTED', 'ACCEPTED'].contains(status),
      'can_start': status == 'ACCEPTED', 'can_complete': status == 'ONGOING',
      'can_accept': status == 'REQUESTED',
      'events': [
        {
          'kind': 'CREATED',
          'label': 'Request created',
          'note': 'Request stored',
          'at': '2026-10-12T10:00:00Z'
        }
      ],
    };

class ApiFixture {
  final String role;
  final bool approved;
  bool online;
  bool getawayEnabled = false;
  List<Map<String, dynamic>> cars;
  List<Map<String, dynamic>> bookings;
  List<Map<String, dynamic>> notifications = [];
  final List<http.Request> requests = [];
  Map<String, dynamic> upiProfile = {'configured': false};
  Map<String, dynamic>? upiRequest;
  void syncUPIIntoBooking() {
    if (upiRequest == null || bookings.isEmpty) return;
    final b = bookings.firstWhere((b) => b['id'] == upiRequest!['booking_id']);
    final done = upiRequest!['status'] == 'CONFIRMED';
    b['payment_received'] = done;
    b['payment_method'] = 'UPI_DIRECT';
    b['payment_status'] = done
        ? 'DRIVER_CONFIRMED'
        : upiRequest!['status'] == 'REPORTED'
            ? 'AWAITING_DRIVER_CONFIRMATION'
            : 'DUE';
    b['payment_label'] = done
        ? 'UPI received (manually confirmed by driver)'
        : 'Payment not confirmed';
    b['upi_payment'] = upiRequest;
    b['can_confirm_cash'] = false;
  }

  final Map<String, List<Map<String, dynamic>>> collections = {
    'places': [],
    'contacts': [],
    'business': []
  };
  final Map<String, dynamic> preferences = {
    'theme': 'light',
    'language': 'en',
    'large_text': false,
    'trip_updates': true,
    'email_receipts': true
  };
  final List<Map<String, dynamic>> tickets = [];

  Map<String, dynamic>? lastBookingPost;
  int? failureStatus;
  String failureMessage = 'Test server unavailable';

  ApiFixture(
      {this.role = 'CUSTOMER',
      this.approved = false,
      this.online = false,
      List<Map<String, dynamic>>? cars,
      List<Map<String, dynamic>>? bookings})
      : cars = cars ?? [],
        bookings = bookings ?? [];

  void install({Map<String, Object>? extraPreferences}) {
    DmMapTesting.disableNetworkTiles = true;
    DmAppearance.instance.dark = false;
    DmAppearance.instance.language = 'en';
    DmAppearance.instance.largeText = false;
    SharedPreferences.setMockInitialValues({
      'dm_access_token': 'test-token',
      'dm_session_base_v8': apiBaseUrl,
      'dm_session_contract': 9,
      'dm_user': jsonEncode({
        'id': role == 'DRIVER' ? 2 : 1,
        'email': '${role.toLowerCase()}@example.com',
        'full_name': role == 'DRIVER' ? 'Ravi Kumar' : 'Adarsh Kumar',
        'role': role
      }),
      ...?extraPreferences,
    });
    AuthService.setHttpClientForTests(MockClient(handle));
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (failureStatus != null) {
      return reply({'detail': failureMessage}, status: failureStatus!);
    }
    final path = request.url.path;
    if (path.endsWith('/api/health/')) {
      return reply(
          {'status': 'ok', 'service': 'drivemate-api', 'api_version': 10});
    }
    final data = request.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(request.body) as Map).cast<String, dynamic>();
    if (path.endsWith('/auth/login/otp/')) {
      return reply({'email': data['email'], 'message': 'Code sent.'});
    }
    if (path.endsWith('/auth/verify-otp/')) {
      return data['otp'] == '123456'
          ? reply({
              'access': 'verified-token',
              'user': {
                'id': 1,
                'name': 'Adarsh Kumar',
                'email': 'customer@example.com',
                'role': 'CUSTOMER',
                'next_step': 'DASHBOARD',
                'profile_complete': true
              }
            })
          : reply({'detail': 'Incorrect verification code.'}, status: 400);
    }
    if (path.endsWith('/hub/account/')) {
      return reply({
        'user': {
          'id': role == 'DRIVER' ? 2 : 1,
          'name': role == 'DRIVER' ? 'Ravi Kumar' : 'Adarsh Kumar',
          'email': '${role.toLowerCase()}@example.com',
          'phone': '+919000000001',
          'role': role
        },
        'preferences': preferences,
        'completed_trips':
            bookings.where((b) => b['status'] == 'COMPLETED').length,
        'active_trips':
            bookings.where((b) => b['status'] != 'COMPLETED').length,
        'saved_places': collections['places']!.length,
        'invite_code': 'TESTCODE',
        'referral_count': 0,
        'email_delivery_configured': true
      });
    }
    if (path.endsWith('/hub/preferences/')) {
      preferences.addAll(data);
      return reply(preferences);
    }
    if (path.endsWith('/hub/promotions/')) return reply({'results': []});
    if (path.endsWith('/hub/tickets/')) {
      return reply({'results': tickets, 'count': tickets.length});
    }
    if (path.endsWith('/hub/map/search/')) {
      return reply({
        'results': [
          {
            'address': 'Sector 15, near the metro gate',
            'latitude': 28.4595,
            'longitude': 77.0266
          }
        ]
      });
    }
    final collection =
        RegExp(r'/hub/collections/(places|contacts|business)/(\d+)?/?$')
            .firstMatch(path);
    if (collection != null) {
      final items = collections[collection[1]]!;
      if (request.method == 'POST') {
        final row = {...data, 'id': items.length + 1};
        items.add(row);
        return reply(row, status: 201);
      }
      if (collection[2] != null) {
        final id = int.parse(collection[2]!);
        if (request.method == 'DELETE') {
          items.removeWhere((r) => r['id'] == id);
          return reply({'detail': 'Removed'});
        }
        final row = items.firstWhere((r) => r['id'] == id);
        row.addAll(data);
        return reply(row);
      }
      return reply({'results': items, 'count': items.length});
    }
    final code = RegExp(r'/rides/bookings/(\d+)/start-code/$').firstMatch(path);
    if (code != null) {
      return reply({
        'otp': '123456',
        'expired': false,
        'expires_at': '2099-01-01T00:00:00Z',
        'email_sent': true
      });
    }
    final cash = RegExp(r'/rides/bookings/(\d+)/cash/$').firstMatch(path);
    if (cash != null) {
      final b = bookings.firstWhere((b) => b['id'] == int.parse(cash[1]!));
      b['cash_received_at'] = '2026-10-28T10:00:00Z';
      b['can_confirm_cash'] = false;
      return reply(b);
    }
    final rating = RegExp(r'/rides/bookings/(\d+)/rating/$').firstMatch(path);
    if (rating != null) {
      final b = bookings.firstWhere((b) => b['id'] == int.parse(rating[1]!));
      b['my_rating'] = data;
      return reply(data);
    }
    if (path.endsWith('/payments/driver/profile/')) {
      if (request.method == 'POST') {
        upiProfile = {...upiProfile, ...data, 'configured': true};
      }
      return reply(upiProfile);
    }
    final upi = RegExp(r'/payments/trips/(\d+)/(qr/|report/|review/|cancel/)?$')
        .firstMatch(path);
    if (upi != null) {
      final id = int.parse(upi[1]!);
      final action = upi[2];
      final b = bookings.firstWhere((b) => b['id'] == id);
      if (action == 'qr/') {
        return http.Response.bytes(
            base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAcIAAAHCAQAAAABUY/ToAAADoklEQVR4nO2cXYrjOBRGzx0b8qhALaCWYu9gllT0kmoH9lKygALrMSDzzYMkR3E1zNCd0Enm3geTODooBnH13R/ZxK/Z/NcvguCkk0466aSTTjr5eKQV64HYw3wEG2OP2RHqD3XU+If/rZOPRSJJYpAkLZ00hYSkepnoVMYtnZrB03M9p5P3J2PxLzYCzHYQxB4bWY1BUv41e6Qbzenka5D9/sbw2WOEL9M8ggBsti6JeKs5nXxxcn6XgE72sYCN0Yxhue+cTr4EGSRNAORFs1qVQp0gnPNOJyndbk4nX4qczczsCAxLJ4iHLICKxYOANYdlt5rTyRchsx5qCh7z+9k0HzFBQnA2CGfT1ajfmtPJ1yJrbL8AUGL7/ElX95qv8tjeydbKklCCISeEyJ9KGijUxFFOFwX5GnJyZzs/tFs+FE1d7l0++RpyslrVQ7HIHRHfZMS3ZMOpT5r//jLBCrPlIbI/92+dfFzSRqAkpsPZICT04z2RHdRsfdZDOXS7zZxOvgpZ9NBEt4mibRsLqRmS19V0IZ7rOZ28H7mtIbYFUrxP1s9FRNd7XnN18rsVJ8OWhL4o6Xq5VPA9LnPyJ6bNytelK2HaUIP5uqt1ylls90NOXlmN7btN8VTHo+Xihzbvg+shJ/fWrpCly+q6+KGliqKcog7aHJSvIScv1vQP2TCdDcKXlXRRBCOADZ9dMgBBqsRzPaeT9yZtZDWIB2nKSaKE2XtCOpkxH1cr2aPofYxO7q1uY1BDMmg3tNxZ7fkhJ/8LKZ16ICTsQ2cjx/bxoNo1VCS2jY/wb518GLJ6lZAobR81mK9CO23di7UzxDW1k61leWMEgNjXwisrEN+SQad8GT6PRiPCn+s5nbwf2eSpa6msdBLlHusmNdQcPHM/5OQ3MvcPxR772DKLE7VQPx9Xs49TcUE23mZOJ1+EvOpBq/XVXOEYasoxR23D1szofsjJK2tqHdeXy/Iph4ayeb3Myb3p2srJe22V1hqh5V7YoR669zXk5DV5ee+HJlYzO5YzijnbOB8hvxAEXA85ubfW+yzdVdd9HtA1lVbvyXfyJ9Zo6qG2Dqntik17PeR7mZP/QgYp72o/rMc+TiXeLwfPFt/LnNzZt3fHlCNAa2+DVhOxSxBX06C1L0enf3NOJ1+TDKqN+SFR1TW5AQTolN+qN9bXoj3rczp5e7KtdTRnWhfqgeml2/pBqrmmdrI183ecO+mkk0466aST/3PyH8M3RbJCNsr4AAAAAElFTkSuQmCC'),
            200,
            headers: {'content-type': 'image/png'});
      }
      if (upiRequest == null && request.method == 'POST') {
        upiRequest = {
          'id': 'fixture-payment',
          'booking_id': id,
          'amount': b['final_fare'] ?? b['estimated_fare'],
          'currency': 'INR',
          'receiver_upi_id': 'qa.receiver@invalid',
          'receiver_name': 'Ravi Kumar',
          'status': 'CREATED',
          'status_label': 'Awaiting payment',
          'qr_payload':
              'upi://pay?pa=qa.receiver%40invalid&pn=Ravi%20Kumar&am=575.00&cu=INR&tr=DMTEST&tn=DriveMate%20trip',
          'customer_reference': '',
          'bank_reference': '',
          'audit': [],
          'bank_verified': false,
        };
      }
      if (upiRequest == null) {
        return reply({'detail': 'Not found'}, status: 404);
      }
      if (action == 'report/') {
        upiRequest!['status'] = 'REPORTED';
        upiRequest!['customer_reference'] = data['reference'];
        upiRequest!['status_label'] =
            'Customer reported payment - not confirmed';
      }
      if (action == 'review/') {
        if (role != 'DRIVER') {
          return reply({'detail': 'Assigned driver only'}, status: 403);
        }
        if (data['action'] == 'reject') {
          upiRequest!['status'] = 'REJECTED';
          upiRequest!['review_note'] = data['note'];
        } else {
          if (data['checked_bank'] != true ||
              double.tryParse('${data['received_amount']}') !=
                  double.parse(upiRequest!['amount'].toString())) {
            return reply({'detail': 'Amount does not match the final fare.'},
                status: 400);
          }
          upiRequest!['status'] = 'CONFIRMED';
          upiRequest!['status_label'] =
              'UPI received - manually confirmed by driver';
          upiRequest!['bank_reference'] = data['bank_reference'];
          upiRequest!['confirmed_at'] = '2026-10-28T10:00:00Z';
        }
      }
      if (action == 'cancel/') {
        upiRequest!['status'] = 'CANCELLED';
        upiRequest!['status_label'] = 'Closed in app';
      }
      upiRequest!['can_report'] = role == 'CUSTOMER' &&
          ['CREATED', 'REPORTED', 'REJECTED'].contains(upiRequest!['status']);
      upiRequest!['can_confirm'] = role == 'DRIVER' &&
          ['CREATED', 'REPORTED', 'REJECTED'].contains(upiRequest!['status']);
      upiRequest!['can_reject'] =
          role == 'DRIVER' && upiRequest!['status'] == 'REPORTED';
      upiRequest!['can_cancel'] =
          ['CREATED', 'REJECTED'].contains(upiRequest!['status']);
      syncUPIIntoBooking();
      return reply(upiRequest!);
    }
    if (path.endsWith('/auth/driver/application/')) {
      return reply({
        'progress': {
          'verification_status': approved ? 'APPROVED' : 'INCOMPLETE',
          'verification_status_label': approved ? 'Approved' : 'Incomplete',
          'next_step': approved ? 'DASHBOARD' : 'PERSONAL_PROFILE',
        }
      });
    }
    if (path.endsWith('/auth/admin/drivers/')) {
      return reply({'count': 0, 'results': []});
    }
    if (path.endsWith('/rides/admin/overview/')) {
      return reply({'open_requests': 0, 'active_trips': 0});
    }
    if (path.endsWith('/rides/pricing/')) {
      return reply({
        'services': [
          price('BOOK_NOW', 99, 129, 1),
          price('HOURLY', 99, 119, 2),
          price('FULL_DAY', 199, 109, 8),
          price('AIRPORT', 149, 139, 2),
          price('OUTSTATION', 249, 149, 6),
          price('NIGHT', 129, 139, 2),
          if (getawayEnabled) price('GETAWAY', 250, 125, 1),
        ],
        'platform_fee_percent': 18
      });
    }
    if (path.endsWith('/rides/vehicles/')) {
      if (request.method == 'POST') {
        final car = {
          ...data,
          'id': cars.length + 1,
          'is_default': cars.isEmpty || data['is_default'] == true
        };
        if (car['is_default'] == true) {
          for (final c in cars) {
            c['is_default'] = false;
          }
        }
        cars.add(car);
        return reply(car, status: 201);
      }
      return reply({'count': cars.length, 'results': cars});
    }
    final vehicleMatch = RegExp(r'/rides/vehicles/(\d+)/$').firstMatch(path);
    if (vehicleMatch != null) {
      final id = int.parse(vehicleMatch[1]!);
      if (request.method == 'DELETE') {
        cars.removeWhere((c) => c['id'] == id);
        return reply({'detail': 'Vehicle removed'});
      }
      final car = cars.firstWhere((c) => c['id'] == id);
      car.addAll(data);
      return reply(car);
    }
    if (path.endsWith('/rides/bookings/') && request.method == 'POST') {
      lastBookingPost = data;
      final b = {
        ...bookingFixture(id: bookings.length + 1),
        ...data,
        'can_accept': false
      };
      bookings.add(b);
      notifications.add({
        'id': 1,
        'title': 'Booking request sent',
        'body': 'Your request is stored.',
        'booking_id': b['id'],
        'kind': 'BOOKING_CREATED',
        'is_read': false
      });
      return reply(b, status: 201);
    }
    if (path.endsWith('/rides/bookings/') || path.endsWith('/rides/trips/')) {
      return reply({
        'count': bookings.length,
        'active': bookings
            .where((b) =>
                ['REQUESTED', 'ACCEPTED', 'ONGOING'].contains(b['status']))
            .toList(),
        'past': bookings
            .where((b) =>
                ['COMPLETED', 'CANCELLED', 'EXPIRED'].contains(b['status']))
            .toList(),
      });
    }
    if (path.endsWith('/rides/requests/')) {
      return reply({
        'count': bookings.where((b) => b['status'] == 'REQUESTED').length,
        'is_available': online,
        'results': bookings.where((b) => b['status'] == 'REQUESTED').toList()
      });
    }
    final transition = RegExp(
            r'/rides/(?:bookings|requests|trips)/(\d+)/(accept|decline|start|complete|cancel)/$')
        .firstMatch(path);
    if (transition != null) {
      final id = int.parse(transition[1]!);
      final action = transition[2];
      final b = bookings.firstWhere((b) => b['id'] == id);
      if (action == 'decline') {
        bookings.remove(b);
        return reply({'detail': 'Request hidden'});
      }
      if (action == 'start' && data['otp'] != '123456') {
        return reply({'detail': 'Incorrect trip-start code.'}, status: 400);
      }
      final next = {
        'accept': 'ACCEPTED',
        'start': 'ONGOING',
        'complete': 'COMPLETED',
        'cancel': 'CANCELLED'
      }[action]!;
      final events = (b['events'] as List).toList();
      b.addAll(bookingFixture(id: id, status: next));
      b['can_accept'] = false;
      b['otp_required'] = next == 'ACCEPTED';
      b['can_confirm_cash'] = next == 'COMPLETED';
      b['can_rate'] = next == 'COMPLETED';
      b['events'] = [
        ...events,
        {
          'kind': next == 'ONGOING' ? 'STARTED' : next,
          'label': next,
          'note': 'Server transition',
          'at': '2026-10-12T11:00:00Z'
        }
      ];
      return reply(b);
    }
    final detail = RegExp(r'/rides/bookings/(\d+)/$').firstMatch(path);
    if (detail != null) {
      return reply(
          bookings.firstWhere((b) => b['id'] == int.parse(detail[1]!)));
    }
    if (path.endsWith('/rides/availability/')) {
      if (request.method == 'POST') online = data['available'] == true;
      return reply({
        'is_available': online,
        'is_approved': approved,
        'open_requests': bookings.length
      });
    }
    if (path.endsWith('/rides/summary/')) {
      final completed =
          bookings.where((b) => b['status'] == 'COMPLETED').length;
      return reply({
        'available': online,
        'approved': approved,
        'today': (471.5 * completed).toString(),
        'week': (471.5 * completed).toString(),
        'lifetime': (471.5 * completed).toString(),
        'completed_trips': completed,
        'active_trips': 0,
        'open_requests': online ? bookings.length : 0,
        'platform_fee_percent': 18,
        'daily': List.generate(
            7,
            (i) => {
                  'label': ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][i],
                  'payout': i == 6 ? (471.5 * completed).toString() : '0',
                  'trips': i == 6 ? completed : 0
                })
      });
    }
    if (path.endsWith('/rides/notifications/')) {
      return reply({
        'unread': notifications.where((n) => n['is_read'] != true).length,
        'count': notifications.length,
        'results': notifications
      });
    }
    if (path.endsWith('/rides/notifications/read-all/')) {
      for (final n in notifications) {
        n['is_read'] = true;
      }
      return reply({'unread': 0});
    }
    final read = RegExp(r'/rides/notifications/(\d+)/read/$').firstMatch(path);
    if (read != null) {
      notifications
          .firstWhere((n) => n['id'] == int.parse(read[1]!))['is_read'] = true;
      return reply({'unread': 0});
    }
    return reply({'detail': 'Unexpected test endpoint $path'}, status: 404);
  }

  static Map<String, dynamic> price(
          String key, int base, int hourly, int min) =>
      {
        'key': key,
        'service': key,
        'base': base,
        'per_hour': hourly,
        'minimum_hours': min
      };

  static http.Response reply(Map<String, dynamic> body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}
