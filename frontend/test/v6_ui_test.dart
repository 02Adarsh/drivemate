// Feature-screen regressions updated to the V9 map-required booking contract.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/screens/book_driver_screen.dart';
import 'package:drivemate/screens/explore_screen.dart';
import 'package:drivemate/screens/safety_screen.dart';
import 'package:drivemate/screens/vehicles_screen.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

void main() {
  setUp(() => ApiFixture().install());
  tearDown(() => AuthService.setHttpClientForTests(null));
  Future<void> show(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(MaterialApp(theme: buildDriveMateTheme(), home: widget));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> step(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('services lists real booking entry points and bundled photos',
      (tester) async {
    await show(tester, const Scaffold(body: ExploreScreen(name: 'Adarsh')));
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('A trained driver. Your own car.'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Book now'), findsOneWidget);
  });
  testWidgets('booking requires a map pin, not only typed pickup text',
      (tester) async {
    await show(tester, const BookDriverScreen(name: 'Adarsh'));
    await step(tester);
    await step(tester);
    expect(find.text('Where should they come?'), findsOneWidget);
    expect(find.text('Choose a pickup pin on the map to continue'),
        findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).first, 'Sector 15 metro gate');
    await tester.pump();
    expect(find.text('Choose a pickup pin on the map to continue'),
        findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Continue'), matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });
  testWidgets('minimum total service prices come from the server table',
      (tester) async {
    await show(tester, const BookDriverScreen(name: 'Adarsh'));
    expect(find.textContaining('from ₹'), findsWidgets);
    expect(find.text('from ₹228'), findsOneWidget);
  });
  testWidgets('garage is an account-synced actionable empty state',
      (tester) async {
    await show(tester, const VehiclesScreen());
    expect(find.text('Your vehicles'), findsOneWidget);
    expect(find.text('No vehicles yet'), findsOneWidget);
    expect(find.text('Add your first car'), findsOneWidget);
    expect(
        find.textContaining('Saved to your DriveMate account'), findsOneWidget);
  });
  testWidgets('safety opens a dialer action and manages trusted contacts',
      (tester) async {
    await show(tester, const SafetyScreen());
    expect(find.textContaining('112'), findsWidgets);
    expect(find.text('Manage trusted contacts'), findsOneWidget);
    expect(find.text('Mandatory customer start code'), findsOneWidget);
  });
}
