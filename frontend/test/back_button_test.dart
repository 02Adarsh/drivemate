// Tests for the top-left back arrow.
//
// The bug this guards against: screens use `Navigator.maybePop()`, which
// silently does nothing when the screen was opened with `pushClean` /
// `pushReplacement` (no route below). On a real phone the arrow then looks
// completely dead. `DmBackButton` (and `goBackOr`) always do something:
// pop when possible, otherwise show a fallback screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drivemate/screens/login_screen.dart';
import 'package:drivemate/screens/register_screen.dart';
import 'package:drivemate/widgets/dm_back_button.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('Register: back arrow works even with nothing on the stack',
      (tester) async {
    usePhoneSurface(tester);

    // Exactly the situation right after signup/OTP: a single route, no history.
    await tester
        .pumpWidget(const MaterialApp(home: RegisterScreen(role: 'CUSTOMER')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(DmBackButton), findsOneWidget,
        reason: 'The arrow must be visible.');

    await tester.tap(find.byType(DmBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The fallback (the login screen) must take over - never a dead arrow.
    expect(find.text('Welcome Back!'), findsOneWidget);
  });

  testWidgets('Login: back arrow leaves for the introduction pages',
      (tester) async {
    usePhoneSurface(tester);

    await tester
        .pumpWidget(const MaterialApp(home: LoginScreen(role: 'CUSTOMER')));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byType(DmBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Onboarding page 1 headline + the slide-to-start control.
    expect(find.textContaining('Your car.'), findsWidgets);
  });

  testWidgets('Back arrow pops a pushed screen and hands back its result',
      (tester) async {
    usePhoneSurface(tester);
    Object? received;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  received = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute<Object?>(
                      builder: (_) => const Scaffold(
                        body: Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: DmBackButton(result: true),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DmBackButton), findsOneWidget);

    await tester.tap(find.byType(DmBackButton));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget,
        reason: 'The screen below is visible again.');
    expect(received, isTrue,
        reason:
            'The result must reach the screen below (used to refresh the dashboard).');
  });
}
