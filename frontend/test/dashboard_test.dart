import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivemate/screens/home_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

void main() {
  setUp(() => ApiFixture().install());
  tearDown(() => AuthService.setHttpClientForTests(null));
  Future<void> show(WidgetTester tester, String role, String name) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: buildDriveMateTheme(),
        home: HomeScreen(role: role, name: name)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('customer dashboard photo search and garage remain accessible',
      (tester) async {
    await show(tester, 'Customer', 'Adarsh Kumar');
    expect(find.text('Hello, Adarsh'), findsOneWidget);
    expect(find.text('Where should the driver come?'), findsOneWidget);
    expect(find.text('A verified driver for the car you own.'), findsOneWidget);
    final scroll = find
        .descendant(
            of: find.byKey(const ValueKey('home-0')),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('YOUR GARAGE'), 300,
        scrollable: scroll, maxScrolls: 15);
    expect(find.text('YOUR GARAGE'), findsOneWidget);
    await close(tester);
  });
  testWidgets('Home Services Activity Account tabs open implemented screens',
      (tester) async {
    await show(tester, 'Customer', 'Adarsh Kumar');
    await tab(tester, 'Services');
    expect(find.text('Ways to use DriveMate — pick a driver, keep your car.'),
        findsOneWidget);
    await tab(tester, 'Activity');
    expect(find.text('Your activity'), findsOneWidget);
    await tab(tester, 'Account');
    expect(find.text('YOUR ACCOUNT'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
      'unapproved driver remains locked and can open requests and earnings',
      (tester) async {
    await show(tester, 'Driver', 'Ravi Kumar');
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('YOUR APPLICATION'), findsOneWidget);
    await tab(tester, 'Requests');
    expect(find.text('Locked until approval'), findsOneWidget);
    await tab(tester, 'Earnings');
    expect(find.text('Earnings'), findsWidgets);
    await close(tester);
  });
  testWidgets('admin opens real queue and account', (tester) async {
    await show(tester, 'Admin', 'Platform Admin');
    expect(find.text('Verification is live'), findsOneWidget);
    await tab(tester, 'Queue');
    expect(find.text('Verification queue'), findsOneWidget);
    await tab(tester, 'Account');
    expect(find.text('YOUR ACCOUNT'), findsOneWidget);
    await close(tester);
  });
}
