import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:drivemate/screens/account_screen.dart';
import 'package:drivemate/screens/account_tools_screen.dart';
import 'package:drivemate/screens/booking_detail_screen.dart';
import 'package:drivemate/screens/home_screen.dart';
import 'package:drivemate/screens/login_screen.dart';
import 'package:drivemate/screens/map_picker_screen.dart';
import 'package:drivemate/screens/otp_screen.dart';
import 'package:drivemate/screens/payments_support_screen.dart';
import 'package:drivemate/screens/register_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/services/rides_service.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

class _Dialer extends UrlLauncherPlatform {
  final List<String> opened = [];
  @override
  Null get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiFixture api;
  final oldLauncher = UrlLauncherPlatform.instance;
  late _Dialer dialer;
  setUpAll(() async {
    final manifest =
        (jsonDecode(await rootBundle.loadString('FontManifest.json')) as List)
            .cast<Map>();
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'].toString());
      for (final font in (entry['fonts'] as List)) {
        loader.addFont(rootBundle.load((font as Map)['asset'].toString()));
      }
      await loader.load();
    }
  });
  setUp(() {
    api = ApiFixture();
    api.install();
    dialer = _Dialer();
    UrlLauncherPlatform.instance = dialer;
  });
  tearDown(() {
    AuthService.setHttpClientForTests(null);
    UrlLauncherPlatform.instance = oldLauncher;
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 700));
  }

  Future<void> show(WidgetTester t, Widget child,
      {bool followAppearance = false, double width = 360}) async {
    t.view.physicalSize = Size(width * 3, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ListenableBuilder(
        listenable: DmAppearance.instance,
        builder: (context, _) => MaterialApp(
            theme: buildDriveMateTheme(),
            home: RepaintBoundary(
                key: const ValueKey('preview'), child: child))));
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

  Future<void> scrollTo(WidgetTester t, String label) async {
    final list = find.byType(ListView).first;
    await t.scrollUntilVisible(find.text(label), 300,
        scrollable:
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
        maxScrolls: 30);
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  }

  test('appearance settings persist on device', () async {
    await DmAppearance.instance.setDark(true);
    await DmAppearance.instance.setLargeText(true);
    await DmAppearance.instance.setLanguage('hi');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('dm_dark_v9'), isTrue);
    expect(prefs.getString('dm_language_v9'), 'hi');
    DmAppearance.instance.dark = false;
    await DmAppearance.instance.load();
    expect(DmAppearance.instance.dark, isTrue);
  });

  testWidgets(
      'light dark toggle repaints the whole dashboard without resetting navigation',
      (t) async {
    await show(t, const HomeScreen(role: 'Customer', name: 'Adarsh Kumar'));
    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFFFFFFFF));
    await t.tap(find.byTooltip('Light / Dark mode'));
    await settle(t);
    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        const Color(0xFF08090B));
    expect(find.text('Hello, Adarsh'), findsOneWidget);
    await close(t);
  });

  testWidgets('map confirmation needs a pin and an address', (t) async {
    await show(t, const MapPickerScreen());
    FilledButton save() => t.widget<FilledButton>(find.ancestor(
        of: find.text('Confirm location'),
        matching: find.byType(FilledButton)));
    expect(save().onPressed, isNull);
    await t.ensureVisible(find.byType(FlutterMap));
    await t.tap(find.byType(FlutterMap));
    await settle(t);
    expect(save().onPressed, isNull);
    await t.enterText(find.byType(TextFormField).last, 'Near the metro gate');
    await settle(t);
    expect(save().onPressed, isNotNull);
    await close(t);
  });

  testWidgets(
      'explicit address search uses the backend rather than fake suggestions',
      (t) async {
    await show(t, const MapPickerScreen());
    await t.enterText(find.byType(TextFormField).first, 'Sector 15');
    await settle(t);
    await t.tap(find.byTooltip('Search places'));
    await settle(t);
    expect(
        api.requests.any((r) =>
            r.url.path.endsWith('/hub/map/search/') &&
            r.url.queryParameters['q'] == 'Sector 15'),
        isTrue);
    expect(find.text('Sector 15, near the metro gate'), findsOneWidget);
    await close(t);
  });

  testWidgets('customer sees the protected trip code after acceptance',
      (t) async {
    api.bookings = [bookingFixture(status: 'ACCEPTED')];
    await show(t, const BookingDetailScreen(bookingId: 1));
    expect(find.text('YOUR TRIP-START CODE'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('Start trip'), findsNothing);
    await close(t);
  });

  testWidgets(
      'driver cannot see the code and a wrong code does not start the trip',
      (t) async {
    api = ApiFixture(
        role: 'DRIVER',
        approved: true,
        online: true,
        bookings: [bookingFixture(status: 'ACCEPTED')]);
    api.install();
    await show(t, const BookingDetailScreen(bookingId: 1, isDriver: true));
    expect(find.text('123456'), findsNothing);
    await tap(t, 'Start trip');
    await t.enterText(find.byType(TextFormField).last, '111111');
    await settle(t);
    await tap(t, 'Verify code & start trip');
    expect(api.bookings.single['status'], 'ACCEPTED');
    await tap(t, 'Start trip');
    await t.enterText(find.byType(TextFormField).last, '123456');
    await settle(t);
    await tap(t, 'Verify code & start trip');
    expect(api.bookings.single['status'], 'ONGOING');
    await close(t);
  });

  testWidgets('assigned driver phone opens the real tel dialer intent',
      (t) async {
    api.bookings = [bookingFixture(status: 'ACCEPTED')];
    await show(t, const BookingDetailScreen(bookingId: 1));
    await scrollTo(t, '+919000000002');
    await tap(t, '+919000000002');
    expect(dialer.opened, contains('tel:+919000000002'));
    await close(t);
  });

  testWidgets('family contact form saves real account data', (t) async {
    await show(t, const HubCollectionScreen(kind: 'contacts'));
    await tap(t, 'Add person');
    await t.enterText(
        find.byType(TextFormField).at(0), 'Trusted family member');
    await t.enterText(find.byType(TextFormField).at(1), '+919876543210');
    await tap(t, 'Save to account');
    expect(api.collections['contacts'], hasLength(1));
    expect(find.text('Trusted family member'), findsOneWidget);
    await close(t);
  });

  testWidgets('business profile form creates a selectable owned profile',
      (t) async {
    await show(t, const HubCollectionScreen(kind: 'business'));
    await tap(t, 'Add business profile');
    await t.enterText(find.byType(TextFormField).first, 'Example company');
    await tap(t, 'Save to account');
    expect(api.collections['business'], hasLength(1));
    expect(find.text('Example company'), findsOneWidget);
    await close(t);
  });

  testWidgets('appearance screen changes persisted local and server settings',
      (t) async {
    await show(t, const AppearanceScreen());
    await t.tap(find.byType(Switch).first);
    await settle(t);
    expect(DmAppearance.instance.dark, isTrue);
    expect(api.preferences['theme'], 'dark');
    await close(t);
  });

  testWidgets(
      'email code sign in is a working action without entering a password',
      (t) async {
    await show(t, const LoginScreen());
    await t.enterText(find.byType(TextFormField).first, 'customer@example.com');
    await tap(t, 'Continue with email code');
    expect(find.byType(OtpScreen), findsOneWidget);
    expect(api.requests.any((r) => r.url.path.endsWith('/auth/login/otp/')),
        isTrue);
    await close(t);
  });

  testWidgets(
      'cash is confirmed only after an explicit collection confirmation',
      (t) async {
    final b = bookingFixture(status: 'COMPLETED')
      ..addAll({'can_confirm_cash': true});
    api.bookings = [b];
    await show(
        t, ReceiptScreen(booking: BookingModel.fromJson(b), isDriver: true));
    await tap(t, 'Confirm cash received');
    expect(api.bookings.single['cash_received_at'], isNull);
    await tap(t, 'I received cash');
    expect(api.bookings.single['cash_received_at'], isNotNull);
    expect(find.text('CASH RECEIVED'), findsOneWidget);
    await close(t);
  });

  testWidgets('invitation code entry is available during registration',
      (t) async {
    await show(t, const RegisterScreen());
    expect(find.widgetWithText(TextFormField, 'Invitation code (optional)'),
        findsOneWidget);
    await close(t);
  });

  testWidgets(
      'account exposes real tools rather than wallet top up placeholders',
      (t) async {
    await show(
        t,
        const Scaffold(
            body: AccountScreen(role: 'Customer', name: 'Adarsh Kumar')));
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Add money'), findsNothing);
    await scrollTo(t, 'Business profiles');
    expect(find.text('Business profiles'), findsOneWidget);
    await close(t);
  });

  testWidgets('light and dark UI preview capture', (t) async {
    await show(t, const HomeScreen(role: 'Customer', name: 'Adarsh Kumar'));
    if (const bool.fromEnvironment('CAPTURE_V9')) {
      await t.runAsync(() async {
        for (final asset in [
          'hero_chauffeur',
          'svc_airport',
          'svc_hourly',
          'svc_outstation'
        ]) {
          await precacheImage(AssetImage('assets/images/$asset.jpg'),
              t.element(find.byType(HomeScreen)));
        }
      });
      await t.pump();
      await t.runAsync(() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('preview')));
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs_preview_v9_light.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await DmAppearance.instance.setDark(true);
      await settle(t);
      await t.runAsync(() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('preview')));
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs_preview_v9_dark.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(find.text('DriveMate'), findsOneWidget);
    await close(t);
  });
}
