import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivemate/screens/book_driver_screen.dart';
import 'package:drivemate/screens/booking_detail_screen.dart';
import 'package:drivemate/screens/bookings_screen.dart';
import 'package:drivemate/screens/driver_earnings_screen.dart';
import 'package:drivemate/screens/driver_requests_screen.dart';
import 'package:drivemate/screens/home_screen.dart';
import 'package:drivemate/screens/notifications_screen.dart';
import 'package:drivemate/screens/vehicles_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/services/rides_service.dart';
import 'package:drivemate/services/vehicle_store.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiFixture api;
  setUp(() {
    api = ApiFixture();
    api.install();
  });
  tearDown(() => AuthService.setHttpClientForTests(null));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> screen(WidgetTester tester, Widget child,
      {double width = 360, double scale = 1}) async {
    tester.view.physicalSize = Size(width * 3, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: buildDriveMateTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: child));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, String text) async {
    final main = find
        .descendant(
            of: find.byType(ListView).first, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text(text), 300,
        scrollable: main, maxScrolls: 25);
    await settle(tester);
  }

  Future<void> pickupPin(WidgetTester tester) async {
    await tap(tester, 'Choose pickup on map');
    await tester.enterText(
        find.byType(TextFormField).first, 'Sector 15 metro gate');
    await settle(tester);
    await tester.tap(find.byTooltip('Search places'));
    await settle(tester);
    await tester.tap(find.text('Sector 15, near the metro gate').first);
    await settle(tester);
    await tap(tester, 'Confirm location');
  }

  Future<void> disposeUi(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .pump(); // Cancels foreground timers before Flutter checks invariants.
  }

  test('Decimal strings and numbers both parse without dropping real fares',
      () {
    final b = BookingModel.fromJson(bookingFixture(status: 'COMPLETED'));
    expect(b.estimatedFare, 575);
    expect(b.finalFare, 575);
    expect(b.driverPayout, 471.5);
    expect(dmMoney(b.driverPayout), '₹471.50');
    expect(b.isFinished, isTrue);
    final numeric = {
      ...bookingFixture(),
      'estimated_fare': 357.0,
      'driver_payout': 292.74
    };
    expect(BookingModel.fromJson(numeric).driverPayout, 292.74);
  });

  test(
      'API sends choices, a stable retry key and UTC schedule, never a client price',
      () async {
    api.cars = [carFixture()];
    final scheduled = DateTime.parse('2026-10-14T14:00:00+05:30');
    final b = await RidesService.createBooking(
        service: 'HOURLY',
        durationHours: 4,
        pickup: 'Sector 15 metro gate',
        scheduledAt: scheduled,
        vehicleId: 1,
        requestKey: 'retry-safe-key');
    expect(b.id, 1);
    expect(api.lastBookingPost!['request_key'], 'retry-safe-key');
    expect(api.lastBookingPost!['vehicle_id'], 1);
    expect(api.lastBookingPost!['scheduled_at'], '2026-10-14T08:30:00.000Z');
    expect(api.lastBookingPost!.containsKey('estimated_fare'), isFalse);
    expect(api.lastBookingPost!.containsKey('final_fare'), isFalse);
  });

  test('offline garage cache is scoped to the signed-in account', () async {
    api.cars = [carFixture()];
    await VehicleStore.sync();
    expect(await VehicleStore.cached(), hasLength(1));
    await AuthService.clearSession();
    expect(await VehicleStore.cached(), isEmpty);
    await AuthService.saveSession({
      'access': 'other-token',
      'user': {'id': 3, 'email': 'someoneelse@example.com', 'role': 'CUSTOMER'}
    });
    expect(await VehicleStore.cached(), isEmpty);
  });

  test(
      'v6 cars stay untouched until an explicit import and string IDs become server IDs',
      () async {
    api.install(extraPreferences: {
      'dm_vehicles_v1': jsonEncode([
        {
          'id': 'v-old-id',
          'make': 'Maruti Suzuki',
          'model': 'Dzire',
          'registration': 'HR 26 AB 1234',
          'fuel': 'Petrol',
          'transmission': 'Manual',
          'seats': '5',
          'isDefault': true
        }
      ])
    });
    await VehicleStore.sync();
    expect(api.cars, isEmpty,
        reason: 'Reading a garage must not silently claim old device cars.');
    expect(await VehicleStore.legacyCount(), 1);
    expect(await VehicleStore.importLegacyVehicles(), 1);
    expect(await VehicleStore.legacyCount(), 0);
    expect(api.cars.single['registration'], 'HR26AB1234');
    expect((await VehicleStore.cached()).single.id, 1);
  });

  test('summary parses money strings and the seven real chart values',
      () async {
    api.bookings = [bookingFixture(status: 'COMPLETED')];
    final summary = await RidesService.summary();
    expect(summary.lifetime, 471.5);
    expect(summary.completedTrips, 1);
    expect(summary.barValues, hasLength(7));
    expect(summary.barValues.last, 471.5);
  });

  testWidgets(
      'car form validates then saves to the server and renders the synced car',
      (tester) async {
    await screen(tester, const VehiclesScreen());
    await tap(tester, 'Add your first car');
    await tap(tester, 'Add vehicle');
    expect(find.text('Enter the car make'), findsOneWidget);
    expect(api.cars, isEmpty);
    await tester.enterText(find.byType(TextFormField).at(0), 'Maruti Suzuki');
    await tester.enterText(find.byType(TextFormField).at(1), 'Dzire');
    await tester.enterText(find.byType(TextFormField).at(2), 'hr26ab1234');
    await tap(tester, 'Add vehicle');
    expect(api.cars, hasLength(1));
    expect(find.text('Maruti Suzuki Dzire'), findsOneWidget);
    expect(find.text('HR26AB1234'), findsOneWidget);
    expect(
        api.requests.any((r) =>
            r.method == 'POST' && r.url.path.endsWith('/rides/vehicles/')),
        isTrue);
    await disposeUi(tester);
  });

  testWidgets(
      'all five booking steps create a real API request and open its detail',
      (tester) async {
    api.cars = [carFixture()];
    await screen(tester,
        const BookDriverScreen(name: 'Adarsh', initialService: 'Hourly'));
    await tap(tester, 'Continue');
    await tap(tester, 'Continue');
    expect(find.text('Choose a pickup pin on the map to continue'),
        findsOneWidget);
    await pickupPin(tester);
    await tap(tester, 'Continue');
    expect(find.text('Maruti Suzuki Dzire'), findsOneWidget);
    await tap(tester, 'Continue');
    expect(find.text('₹575'), findsWidgets);
    await tap(tester, 'Request a driver');
    await tap(tester, 'Send request to drivers');
    expect(api.bookings, hasLength(1));
    expect(api.lastBookingPost!['vehicle_id'], 1);
    expect(api.lastBookingPost!['request_key'], isNotEmpty);
    expect(find.text('Request sent to drivers'), findsOneWidget);
    await tap(tester, 'Open my booking');
    expect(find.text('Searching for a driver'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets(
      'full-day duration respects the server minimum rather than a misleading two-hour quote',
      (tester) async {
    await screen(tester,
        const BookDriverScreen(name: 'Adarsh', initialService: 'Full day'));
    await tap(tester, 'Continue');
    expect(find.text('2 hours'), findsNothing);
    expect(find.text('4 hours'), findsNothing);
    expect(find.text('8 hours'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets(
      'driver availability toggle writes to the server instead of just changing the switch',
      (tester) async {
    api = ApiFixture(role: 'DRIVER', approved: true);
    api.install();
    await screen(tester, const HomeScreen(role: 'Driver', name: 'Ravi Kumar'));
    expect(find.text('You are offline'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(api.online, isTrue);
    expect(find.text('You are online'), findsOneWidget);
    expect(
        api.requests.any((r) =>
            r.method == 'POST' && r.url.path.endsWith('/rides/availability/')),
        isTrue);
    await disposeUi(tester);
  });

  testWidgets(
      'live driver request can be accepted and becomes the assigned trip',
      (tester) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        online: true,
        bookings: [bookingFixture()]);
    api.install();
    await screen(
        tester,
        const Scaffold(
            body: DriverRequestsScreen(approved: true, online: true)));
    await scrollTo(tester, 'Accept request');
    await tap(tester, 'Accept request');
    expect(api.bookings.single['status'], 'ACCEPTED');
    expect(find.text('IN PROGRESS'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets('decline really removes the request from this driver inbox',
      (tester) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        online: true,
        bookings: [bookingFixture()]);
    api.install();
    await screen(
        tester,
        const Scaffold(
            body: DriverRequestsScreen(approved: true, online: true)));
    await scrollTo(tester, 'Decline');
    await tap(tester, 'Decline');
    expect(api.bookings, isEmpty);
    expect(find.text('No live requests right now'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets(
      'assigned trip starts, completion requires confirmation, and the ledger is recorded',
      (tester) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        online: true,
        bookings: [bookingFixture(status: 'ACCEPTED')]);
    api.install();
    await screen(
        tester, const BookingDetailScreen(bookingId: 1, isDriver: true));
    await scrollTo(tester, 'Start trip');
    await tap(tester, 'Start trip');
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await settle(tester);
    await tap(tester, 'Verify code & start trip');
    expect(api.bookings.single['status'], 'ONGOING');
    await scrollTo(tester, 'Complete trip');
    await tap(tester, 'Complete trip');
    expect(api.bookings.single['status'], 'ONGOING');
    await tap(tester, 'Trip is finished');
    expect(api.bookings.single['status'], 'COMPLETED');
    expect(find.text('Complete trip'), findsNothing);
    expect(api.bookings.single['final_fare'], '575.00');
    await disposeUi(tester);
  });

  testWidgets(
      'waiting detail refreshes the status after eight seconds without a fake assignment',
      (tester) async {
    api.bookings = [bookingFixture()];
    await screen(tester, const BookingDetailScreen(bookingId: 1));
    expect(find.text('Searching for a driver'), findsOneWidget);
    api.bookings[0] = bookingFixture(status: 'ACCEPTED');
    await tester.pump(const Duration(seconds: 8));
    await settle(tester);
    expect(find.text('Driver assigned'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets('notifications mark read and open the linked booking',
      (tester) async {
    api.bookings = [bookingFixture()];
    api.notifications = [
      {
        'id': 1,
        'title': 'Booking request sent',
        'body': 'Stored on the server',
        'kind': 'BOOKING_CREATED',
        'is_read': false,
        'booking_id': 1
      }
    ];
    await screen(tester, const NotificationsScreen());
    await tap(tester, 'Booking request sent');
    expect(api.notifications.single['is_read'], isTrue);
    expect(find.text('Searching for a driver'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets(
      'earnings renders actual completed-trip values and never pretends they are paid',
      (tester) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        bookings: [bookingFixture(status: 'COMPLETED')]);
    api.install();
    await screen(
        tester, const Scaffold(body: DriverEarningsScreen(approved: true)));
    expect(find.text('₹471.50'), findsWidgets);
    await scrollTo(tester, 'COMPLETED TRIPS');
    expect(find.text('PAID TRIPS'), findsNothing);
    expect(find.text('#1 · Hourly'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets('offline garage is an honest read-only account cache',
      (tester) async {
    api.cars = [carFixture()];
    await VehicleStore.sync();
    api.failureStatus = 503;
    await screen(tester, const VehiclesScreen());
    expect(find.textContaining('Offline: showing the last synced list'),
        findsOneWidget);
    final edit = tester.widget<TextButton>(find
        .ancestor(of: find.text('Edit'), matching: find.byType(TextButton))
        .first);
    expect(edit.onPressed, isNull);
    expect(find.text('Maruti Suzuki Dzire'), findsOneWidget);
    await disposeUi(tester);
  });

  testWidgets(
      'activity API errors do not masquerade as no bookings or zero earnings',
      (tester) async {
    api.failureStatus = 503;
    await screen(tester, const Scaffold(body: BookingsScreen(name: 'Adarsh')));
    expect(find.text('Could not load your bookings'), findsOneWidget);
    expect(find.text('No active booking'), findsNothing);
    await disposeUi(tester);
  });

  testWidgets('detail stays usable at 320px with larger system text',
      (tester) async {
    api.bookings = [bookingFixture(status: 'COMPLETED')];
    await screen(tester, const BookingDetailScreen(bookingId: 1),
        width: 320, scale: 1.4);
    await scrollTo(tester, 'TIMELINE');
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });
  testWidgets('foreground refresh pauses with the app and stops after disposal',
      (tester) async {
    api.bookings = [bookingFixture()];
    await screen(tester, const BookingDetailScreen(bookingId: 1));
    final before = api.requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 16));
    expect(api.requests.length, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(api.requests.length, greaterThan(before));
    await disposeUi(tester);
    final disposedCount = api.requests.length;
    await tester.pump(const Duration(seconds: 16));
    expect(api.requests.length, disposedCount);
  });
}
