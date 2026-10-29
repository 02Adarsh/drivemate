import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:drivemate/screens/direct_upi_payment_screen.dart';
import 'package:drivemate/screens/driver_upi_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/services/direct_upi_service.dart';
import 'package:drivemate/services/rides_service.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

class _UPILauncher extends UrlLauncherPlatform {
  final List<String> urls = [];
  @override
  Null get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiFixture api;
  late _UPILauncher launcher;
  final previousLauncher = UrlLauncherPlatform.instance;
  setUp(() {
    api = ApiFixture(bookings: [bookingFixture(status: 'COMPLETED')]);
    api.install();
    launcher = _UPILauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() {
    AuthService.setHttpClientForTests(null);
    UrlLauncherPlatform.instance = previousLauncher;
  });
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 650));
    await t.pump(const Duration(milliseconds: 650));
  }

  Future<void> show(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildDriveMateTheme(), home: child));
    await settle(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t);
    final target = find.text(label).first;
    await Scrollable.ensureVisible(t.element(target), alignment: 0.5);
    await settle(t);
    await t.tap(target);
    await settle(t);
  }

  Future<void> scroll(WidgetTester t, String label) async {
    await t.scrollUntilVisible(find.text(label), 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first,
        maxScrolls: 30);
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  }

  test('request service does not accept an editable fare/receiver argument',
      () async {
    final data = await DirectUPIService.create(1);
    expect(data['amount'], '575.00');
    final post = api.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/payments/trips/1/'));
    expect(jsonDecode(post.body), isEmpty);
  });

  test(
      'opening the UPI app preserves amount but never marks the payment confirmed',
      () async {
    final data = await DirectUPIService.create(1);
    await DirectUPIService.openUPI(data['qr_payload'].toString());
    final uri = Uri.parse(launcher.urls.single);
    expect(uri.scheme, 'upi');
    expect(uri.queryParameters['am'], '575.00');
    expect(uri.queryParameters['pa'], 'qa.receiver@invalid');
    expect(api.upiRequest!['status'], 'CREATED');
    expect(api.upiRequest!['bank_verified'], isFalse);
  });

  testWidgets(
      'customer QR shows read-only server fare and an explicit manual-mode notice',
      (t) async {
    await show(t, const DirectUPIPaymentScreen(bookingId: 1));
    expect(find.text('₹575.00'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('manual driver confirmation'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Record actual UPI credit'), findsNothing);
    await close(t);
  });

  testWidgets(
      'I paid only reports a reference and does not create a paid receipt',
      (t) async {
    await show(t, const DirectUPIPaymentScreen(bookingId: 1));
    await scroll(t, 'I paid — send reference to driver');
    await tap(t, 'I paid — send reference to driver');
    await t.enterText(find.byType(TextFormField).last, 'RRN1234567890');
    await t.tap(find.byType(Checkbox).last);
    await settle(t);
    await tap(t, 'Report — not verified payment');
    expect(api.upiRequest!['status'], 'REPORTED');
    expect(api.bookings.single['payment_received'], isFalse);
    expect(find.text('Waiting for driver bank check'), findsOneWidget);
    expect(find.text('Open updated receipt'), findsNothing);
    await close(t);
  });

  testWidgets(
      'driver confirmation requires bank acknowledgement and exact actual amount',
      (t) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        bookings: [bookingFixture(status: 'COMPLETED')]);
    api.install();
    await show(t, const DirectUPIPaymentScreen(bookingId: 1, isDriver: true));
    await scroll(t, 'Record actual UPI credit');
    await tap(t, 'Record actual UPI credit');
    await t.enterText(find.byType(TextFormField).at(0), '1.00');
    await t.enterText(find.byType(TextFormField).at(1), 'BANKREF123456');
    await t.tap(find.byType(Checkbox).last);
    await settle(t);
    await tap(t, 'Manually confirm actual receipt');
    expect(api.upiRequest!['status'], 'CREATED');
    await scroll(t, 'Record actual UPI credit');
    await tap(t, 'Record actual UPI credit');
    await t.enterText(find.byType(TextFormField).at(0), '575.00');
    await t.enterText(find.byType(TextFormField).at(1), 'BANKREF123456');
    await t.tap(find.byType(Checkbox).last);
    await settle(t);
    await tap(t, 'Manually confirm actual receipt');
    expect(api.upiRequest!['status'], 'CONFIRMED');
    expect(api.upiRequest!['bank_verified'], isFalse);
    expect(find.text('Open updated receipt'), findsOneWidget);
    await close(t);
  });

  testWidgets('customer screen observes manual driver confirmation on polling',
      (t) async {
    await show(t, const DirectUPIPaymentScreen(bookingId: 1));
    api.upiRequest!['status'] = 'CONFIRMED';
    api.upiRequest!['status_label'] =
        'UPI received - manually confirmed by driver';
    api.upiRequest!['bank_reference'] = 'BANKREF123456';
    api.upiRequest!['confirmed_at'] = '2026-10-28T10:00:00Z';
    await t.pump(const Duration(seconds: 8));
    await settle(t);
    await scroll(t, 'Open updated receipt');
    expect(find.text('Open updated receipt'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await close(t);
  });

  testWidgets('driver receiving setup never asks for a UPI PIN', (t) async {
    api = ApiFixture(role: 'DRIVER', approved: true);
    api.install();
    await show(t, const DriverUPIScreen());
    expect(find.text('Receiving UPI & QR'), findsOneWidget);
    expect(
        find.widgetWithText(
            TextFormField, 'Current DriveMate password (not UPI PIN)'),
        findsOneWidget);
    await tap(t, 'Save receiving details');
    expect(
        find.text('Upload your own receiving UPI QR image.'), findsOneWidget);
    await close(t);
  });

  test(
      'UPI receipt model does not pretend a manually confirmed UPI transfer was cash',
      () {
    final b = BookingModel.fromJson({
      ...bookingFixture(status: 'COMPLETED'),
      'payment_received': true,
      'payment_method': 'UPI_DIRECT',
      'payment_label': 'UPI received (manually confirmed by driver)',
      'payment_status': 'DRIVER_CONFIRMED'
    });
    expect(b.paymentReceived, isTrue);
    expect(b.cashReceived, isFalse);
    expect(b.paymentBadge, 'UPI • DRIVER CONFIRMED');
  });
}
