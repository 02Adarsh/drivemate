// Basic widget tests. Run with:  flutter test
//
// They cover screens that do not need a running backend, plus the
// "slide to get started" control that previously did nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drivemate/main.dart';
import 'package:drivemate/screens/login_screen.dart';
import 'package:drivemate/screens/register_screen.dart';
import 'package:drivemate/widgets/slide_to_start.dart';

void main() {
  setUp(() {
    // The splash screen reads the saved session, which uses SharedPreferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('app launches with the splash screen', (tester) async {
    await tester.pumpWidget(const DriveMateApp());
    expect(
        find.text('YOUR CAR. YOUR DESTINATION. YOUR DRIVER.'), findsOneWidget);

    // Let the splash timer finish and move on to the introduction pages.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Your car.'), findsWidgets);
  });

  testWidgets('login screen shows the core actions', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: LoginScreen(role: 'CUSTOMER')));
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Continue with email code'), findsOneWidget);
    expect(find.text('New to DriveMate?'), findsOneWidget);
  });

  testWidgets('register screen switches between Rider and Driver',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: RegisterScreen(role: 'CUSTOMER')));
    expect(find.text('Create Account'), findsWidgets);

    await tester.tap(find.text('Driver'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('driver application'), findsOneWidget);
  });

  testWidgets('slide to get started completes on a full drag', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideToStart(onCompleted: () => completed = true),
        ),
      ),
    );

    final slider = find.byType(SlideToStart);
    expect(slider, findsOneWidget);

    // Drag across the full width of the track.
    final start = tester.getTopLeft(slider) + const Offset(24, 30);
    await tester.dragFrom(start, Offset(tester.getSize(slider).width, 0));
    await tester.pump(const Duration(milliseconds: 200));

    expect(completed, isTrue,
        reason: 'The slider must fire onCompleted after a full drag.');
  });

  testWidgets('slide to get started also completes on tap', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideToStart(onCompleted: () => completed = true),
        ),
      ),
    );

    await tester.tap(find.byType(SlideToStart));
    await tester.pump();

    expect(completed, isTrue,
        reason: 'A tap is the fallback so nobody gets stuck.');
  });
}
