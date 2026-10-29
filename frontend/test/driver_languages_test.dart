import 'dart:async';
import 'dart:convert';

import 'package:drivemate/config.dart';
import 'package:drivemate/screens/driver_personal_profile_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/widgets/dm_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response ok(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void install(Future<http.Response> Function() profile) {
    SharedPreferences.setMockInitialValues({
      'dm_access_token': 'test-token',
      'dm_session_base_v8': apiBaseUrl,
      'dm_session_contract': 9,
    });
    AuthService.setHttpClientForTests(MockClient((request) async {
      if (request.url.path.endsWith('/health/')) {
        return ok(
            {'status': 'ok', 'service': 'drivemate-api', 'api_version': 10});
      }
      if (request.url.path.endsWith('/auth/profile/')) return profile();
      return ok({});
    }));
  }

  Finder chip(String language) => find.ancestor(
      of: find.text(language), matching: find.byType(DmSelectChip));

  Future<void> showScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DriverPersonalProfileScreen(name: 'Test Driver')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hindi'));
    await tester.pumpAndSettle();
  }

  tearDown(() => AuthService.setHttpClientForTests(null));

  testWidgets('languages can be selected, combined, and deselected',
      (tester) async {
    install(() async => ok({
          'profile': {'languages': ''}
        }));
    await showScreen(tester);
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isFalse);
    await tester.tap(find.text('Hindi'));
    await tester.pumpAndSettle();
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isTrue);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(tester.widget<DmSelectChip>(chip('English')).selected, isTrue);
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isTrue);
    await tester.tap(find.text('Hindi'));
    await tester.pumpAndSettle();
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the API comma-separated language string',
      (tester) async {
    install(() async => ok({
          'profile': {'languages': 'Hindi, English'}
        }));
    await showScreen(tester);
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isTrue);
    expect(tester.widget<DmSelectChip>(chip('English')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores list-form language responses', (tester) async {
    install(() async => ok({
          'profile': {
            'languages': ['Hindi']
          }
        }));
    await showScreen(tester);
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late profile response does not overwrite a new selection',
      (tester) async {
    final response = Completer<http.Response>();
    install(() => response.future);
    await showScreen(tester);
    await tester.tap(find.text('Hindi'));
    await tester.pump();
    response.complete(ok({
      'profile': {'languages': 'English'}
    }));
    await tester.pumpAndSettle();
    expect(tester.widget<DmSelectChip>(chip('Hindi')).selected, isTrue);
    expect(tester.widget<DmSelectChip>(chip('English')).selected, isFalse);
    expect(tester.takeException(), isNull);
  });
}
