import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivemate/config.dart';
import 'package:drivemate/screens/home_screen.dart';
import 'package:drivemate/screens/driver_driving_details_screen.dart';
import 'package:drivemate/screens/driver_documents_screen.dart';
import 'package:drivemate/screens/driver_application_status_screen.dart';
import 'package:drivemate/screens/driver_personal_profile_screen.dart';
import 'package:drivemate/screens/profile_setup_screen.dart';
import 'package:drivemate/screens/splash_screen.dart';
import 'package:drivemate/screens/session_resume_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/services/session_resume.dart';

http.Response ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void install(
      {String role = 'CUSTOMER',
      bool completed = false,
      String driverStep = 'PERSONAL_PROFILE',
      bool fail = false,
      bool invalidProfile = false}) {
    SharedPreferences.setMockInitialValues({
      'dm_access_token': 'test-token',
      'dm_session_base_v8': apiBaseUrl,
      'dm_session_contract': 9,
      // Deliberately stale: resume must use current server state, not this.
      'dm_user': jsonEncode(
          {'name': 'Old Name', 'role': 'CUSTOMER', 'next_step': 'DASHBOARD'}),
    });
    AuthService.setHttpClientForTests(MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/health/')) {
        return ok(
            {'status': 'ok', 'service': 'drivemate-api', 'api_version': 10});
      }
      if (fail) throw Exception('offline');
      if (path.endsWith('/auth/me/')) {
        return ok({
          'user': {'id': 7, 'name': 'Test User', 'role': role},
          if (role == 'DRIVER') 'driver': {'next_step': driverStep}
        });
      }
      if (path.endsWith('/auth/profile/')) {
        return ok({
          'role': role,
          'profile': invalidProfile ? {} : {'profile_complete': completed}
        });
      }
      return ok({});
    }));
  }

  tearDown(() => AuthService.setHttpClientForTests(null));

  test('customer completion comes from server, not cached dashboard', () async {
    install(completed: false);
    expect((await loadResumeState())['user']['next_step'], 'PROFILE');
  });
  test('completed customer can reach dashboard', () async {
    install(completed: true);
    expect((await loadResumeState())['user']['next_step'], 'DASHBOARD');
  });
  test('driver continues the server-selected step', () async {
    install(role: 'DRIVER', driverStep: 'DRIVING_DETAILS');
    expect((await loadResumeState())['driver']['next_step'], 'DRIVING_DETAILS');
  });
  test('admin resumes without a customer profile', () async {
    install(role: 'ADMIN');
    expect((await loadResumeState())['user']['next_step'], 'ADMIN_DASHBOARD');
  });
  test('missing completion flag never enables dashboard', () async {
    install(invalidProfile: true);
    await expectLater(loadResumeState(), throwsA(isA<ApiException>()));
  });
  test('unknown driver step never enables dashboard', () async {
    install(role: 'DRIVER', driverStep: 'UNKNOWN');
    await expectLater(loadResumeState(), throwsA(isA<ApiException>()));
  });
  test('offline cannot be treated as complete', () async {
    install(fail: true);
    await expectLater(loadResumeState(), throwsA(isA<ApiException>()));
  });

  testWidgets('restarting incomplete customer opens profile, not dashboard',
      (tester) async {
    install(completed: false);
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restarting offline shows retry and never dashboard',
      (tester) async {
    install(fail: true);
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(SessionResumeScreen), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('restarting completed customer opens dashboard', (tester) async {
    install(completed: true);
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restarting driver resumes personal profile', (tester) async {
    install(role: 'DRIVER', driverStep: 'PERSONAL_PROFILE');
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(DriverPersonalProfileScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restarting driver resumes driving details', (tester) async {
    install(role: 'DRIVER', driverStep: 'DRIVING_DETAILS');
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(DriverDrivingDetailsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('restarting driver resumes documents', (tester) async {
    install(role: 'DRIVER', driverStep: 'DOCUMENTS');
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(DriverDocumentsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('driver awaiting review does not open dashboard on restart',
      (tester) async {
    install(role: 'DRIVER', driverStep: 'UNDER_REVIEW');
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(DriverApplicationStatusScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
