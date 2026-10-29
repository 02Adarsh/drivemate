import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivemate/config.dart';
import 'package:drivemate/screens/login_screen.dart';
import 'package:drivemate/screens/server_connection_screen.dart';
import 'package:drivemate/services/auth_service.dart';
import 'package:drivemate/services/server_connection.dart';
import 'package:drivemate/services/vehicle_store.dart';
import 'package:drivemate/theme/dm_theme.dart';
import 'support/api_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ApiFixture().install());
  tearDown(() => AuthService.setHttpClientForTests(null));

  http.Response health({int status = 200, String service = 'drivemate-api'}) =>
      ApiFixture.reply({'status': 'ok', 'service': service, 'api_version': 10},
          status: status);

  test(
      'server roots, trailing slash and case normalize to a canonical /api base',
      () {
    expect(ServerConnection.normalize(' HTTP://192.168.1.20:8000/ '),
        'http://192.168.1.20:8000/api');
    expect(ServerConnection.normalize('https://EXAMPLE.COM/api/'),
        'https://example.com/api');
    expect(ServerConnection.normalize('http://127.0.0.1:8000/api'), apiBaseUrl);
  });

  for (final value in [
    '',
    '192.168.1.20:8000',
    'ftp://pc/api',
    'http://user:password@pc/api',
    'http://pc/api?token=secret',
    'https://pc/api#fragment',
    'http://pc/api/auth/login/',
    'http://pc/admin/',
    'http://pc:99999/api',
    'http://bad host/api'
  ]) {
    test('invalid / unsafe base rejected: $value', () {
      expect(() => ServerConnection.normalize(value), throwsFormatException);
    });
  }

  test(
      'health probe is public, sends no credentials and accepts only the real service shape',
      () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return health();
    });
    final result = await ServerConnection.probe(client, apiBaseUrl,
        timeout: const Duration(seconds: 1));
    expect(result.ok, isTrue);
    expect(captured!.url.path, '/api/health/');
    expect(captured!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
    expect(captured!.body, isEmpty);
    expect(captured!.followRedirects, isFalse);
  });

  for (final status in [400, 404, 500]) {
    test('HTTP $status never becomes a healthy cached backend', () async {
      final client = MockClient((request) async => health(status: status));
      final result = await ServerConnection.probe(client, apiBaseUrl,
          timeout: const Duration(seconds: 1));
      expect(result.ok, isFalse);
      expect(result.statusCode, status);
      AuthService.setHttpClientForTests(client);
      expect(await AuthService.detectBaseUrl(force: true), isNull);
    });
  }

  test('HTTP 200 HTML / another service and redirects are rejected', () async {
    for (final response in [
      http.Response('<html>other site</html>', 200),
      health(service: 'another-app'),
      http.Response('', 302, headers: {'location': 'https://other.invalid/'})
    ]) {
      final result = await ServerConnection.probe(
          MockClient((_) async => response), apiBaseUrl,
          timeout: const Duration(seconds: 1));
      expect(result.ok, isFalse);
    }
  });

  test('old reachable backend is not mistaken for the V9 API contract',
      () async {
    final result = await ServerConnection.probe(
        MockClient((_) async => ApiFixture.reply(
            {'status': 'ok', 'service': 'drivemate-api', 'api_version': 8})),
        apiBaseUrl,
        timeout: const Duration(seconds: 1));
    expect(result.ok, isFalse);
    expect(result.message, contains('API 10'));
  });

  test('health timeout is a clear failure, not a fake connected state',
      () async {
    final result = await ServerConnection.probe(
        MockClient((_) => Completer<http.Response>().future), apiBaseUrl,
        timeout: const Duration(milliseconds: 1));
    expect(result.ok, isFalse);
    expect(result.statusCode, isNull);
    expect(result.message, contains('No response'));
  });

  test(
      'v7 token without a backend pin is signed out on upgrade, not guessed onto another host',
      () async {
    SharedPreferences.setMockInitialValues({
      'dm_access_token': 'legacy-token',
      'dm_user': jsonEncode({'id': 1})
    });
    AuthService.setHttpClientForTests(MockClient((_) async => health()));
    await AuthService.initializeBackend();
    expect(await AuthService.hasSession(), isFalse);
    expect(await AuthService.cachedUser(), isNull);
  });

  test(
      'switching server clears login, persists the pin and removes fallback guesses',
      () async {
    await AuthService.initializeBackend();
    expect(await AuthService.hasSession(), isTrue);
    expect(
        await AuthService.setBackendUrl('http://192.168.1.20:8000/'), isTrue);
    expect(await AuthService.hasSession(), isFalse);
    expect(AuthService.customBaseUrl, 'http://192.168.1.20:8000/api');
    expect(AuthService.candidateBaseUrls(), ['http://192.168.1.20:8000/api']);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('dm_api_base_override_v8'), AuthService.customBaseUrl);
    expect(prefs.getString('dm_access_token'), isNull);
  });

  test('signed-in call failure never forwards Authorization to fallback hosts',
      () async {
    final hosts = <String>[];
    final headers = <String?>[];
    AuthService.setHttpClientForTests(MockClient((request) async {
      hosts.add(request.url.host);
      headers.add(request.headers['Authorization']);
      throw http.ClientException('fixture offline');
    }));
    await expectLater(
        AuthService.getJson('rides/bookings/'), throwsA(isA<ApiException>()));
    expect(hosts, hasLength(1));
    expect(hosts.every((host) => host == '127.0.0.1'), isTrue);
    expect(headers.every((header) => header == 'Bearer test-token'), isTrue);
  });

  test(
      'login data goes only to a health-verified server; discovery itself is public',
      () async {
    SharedPreferences.setMockInitialValues({});
    final sent = <http.Request>[];
    AuthService.setHttpClientForTests(MockClient((request) async {
      sent.add(request);
      if (request.url.path.endsWith('/health/')) return health();
      return ApiFixture.reply({'detail': 'fixture login failed'}, status: 400);
    }));
    await expectLater(
        AuthService.login(
            identifier: 'rider@example.com',
            password: 'test-password',
            role: 'CUSTOMER'),
        throwsA(isA<ApiException>()));
    expect(sent, hasLength(2));
    expect(sent[0].method, 'GET');
    expect(sent[0].body, isEmpty);
    expect(sent[1].url.host, sent[0].url.host);
    expect(sent[1].followRedirects, isFalse);
  });

  test(
      'an old in-flight response cannot repopulate data after switching the backend',
      () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    AuthService.setHttpClientForTests(MockClient((request) {
      started.complete();
      return pending.future;
    }));
    final request = AuthService.getJson('auth/me/');
    final assertion = expectLater(request, throwsA(isA<ApiException>()));
    await started.future;
    await AuthService.setBackendUrl('http://192.168.1.50:8000/api');
    pending
        .complete(ApiFixture.reply({'id': 1, 'full_name': 'Old server user'}));
    await assertion;
    expect(await AuthService.hasSession(), isFalse);
    expect(AuthService.activeBaseUrl, 'http://192.168.1.50:8000/api');
  });

  test(
      'offline garage data cannot bleed across backend switches with the same user ID/email',
      () async {
    final api = ApiFixture(cars: [carFixture()]);
    api.install();
    await VehicleStore.sync();
    expect(await VehicleStore.cached(), hasLength(1));
    await AuthService.setBackendUrl('http://192.168.1.50:8000/api');
    await AuthService.saveSession({
      'access': 'new-token',
      'user': {'id': 1, 'email': 'customer@example.com', 'role': 'CUSTOMER'}
    });
    expect(await VehicleStore.cached(), isEmpty);
  });

  test('invalid server address does not discard the current login', () async {
    await AuthService.initializeBackend();
    await expectLater(
        AuthService.setBackendUrl('ftp://not-an-api/'), throwsFormatException);
    expect(await AuthService.hasSession(), isTrue);
  });

  test(
      'a completed login response cannot be saved after the server was changed',
      () async {
    AuthService.setHttpClientForTests(
        MockClient((request) async => ApiFixture.reply({
              'access': 'old-login-token',
              'refresh': 'old-refresh',
              'user': {'id': 1, 'role': 'CUSTOMER', 'email': 'old@example.com'}
            })));
    final old = await AuthService.login(
        identifier: 'old@example.com', password: 'test', role: 'CUSTOMER');
    await AuthService.setBackendUrl('http://192.168.1.55:8000/api');
    await expectLater(
        AuthService.saveSession(old), throwsA(isA<ApiException>()));
    expect(await AuthService.hasSession(), isFalse);
    expect(await AuthService.cachedUser(), isNull);
  });

  test(
      'backend switching and session persistence serialize without leaving old credentials behind',
      () async {
    AuthService.setHttpClientForTests(
        MockClient((request) async => ApiFixture.reply({
              'access': 'old-login-token',
              'user': {'id': 1, 'role': 'CUSTOMER', 'email': 'old@example.com'}
            })));
    final old = await AuthService.login(
        identifier: 'old@example.com', password: 'test', role: 'CUSTOMER');
    final saved = AuthService.saveSession(old).catchError((Object error) {
      if (error is! ApiException) throw error;
    });
    await AuthService.setBackendUrl('http://192.168.1.55:8000/api');
    await saved;
    expect(await AuthService.hasSession(), isFalse);
    expect(AuthService.activeBaseUrl, 'http://192.168.1.55:8000/api');
  });

  test('expired access is refreshed once on the same pinned server', () async {
    ApiFixture()
        .install(extraPreferences: {'dm_refresh_token': 'test-refresh'});
    final calls = <http.Request>[];
    AuthService.setHttpClientForTests(MockClient((request) async {
      calls.add(request);
      if (request.url.path.endsWith('/token/refresh/')) {
        return ApiFixture.reply({'access': 'renewed-access'});
      }
      if (request.headers['Authorization'] == 'Bearer renewed-access') {
        return ApiFixture.reply({'ok': true});
      }
      return ApiFixture.reply({'detail': 'Expired'}, status: 401);
    }));
    final data = await AuthService.getJson('auth/me/');
    expect(data['ok'], isTrue);
    expect(calls, hasLength(3));
    expect(calls.every((r) => r.url.host == '127.0.0.1'), isTrue);
    expect(calls[1].headers.containsKey('Authorization'), isFalse);
    expect(await AuthService.token(), 'renewed-access');
  });

  test('rejected refresh does not loop or switch hosts', () async {
    ApiFixture()
        .install(extraPreferences: {'dm_refresh_token': 'invalid-refresh'});
    final calls = <http.Request>[];
    AuthService.setHttpClientForTests(MockClient((r) async {
      calls.add(r);
      return ApiFixture.reply({'detail': 'Expired'}, status: 401);
    }));
    await expectLater(
        AuthService.getJson('auth/me/'), throwsA(isA<ApiException>()));
    expect(calls, hasLength(2));
    expect(calls.every((r) => r.url.host == '127.0.0.1'), isTrue);
  });

  test(
      'a server switch during refresh cannot restore old tokens or replay data',
      () async {
    ApiFixture()
        .install(extraPreferences: {'dm_refresh_token': 'test-refresh'});
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    AuthService.setHttpClientForTests(MockClient((r) async {
      if (r.url.path.endsWith('/token/refresh/')) {
        started.complete();
        return pending.future;
      }
      return ApiFixture.reply({'detail': 'Expired'}, status: 401);
    }));
    final old = AuthService.getJson('auth/me/');
    final assertion = expectLater(old, throwsA(isA<ApiException>()));
    await started.future;
    await AuthService.setBackendUrl('http://192.168.1.60:8000/api');
    pending.complete(ApiFixture.reply({'access': 'old-server-access'}));
    await assertion;
    expect(await AuthService.hasSession(), isFalse);
    expect(AuthService.activeBaseUrl, 'http://192.168.1.60:8000/api');
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 650));
  }

  Future<void> showScreen(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(MaterialApp(theme: buildDriveMateTheme(), home: widget));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).first;
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('Server connection is reachable before login', (tester) async {
    await showScreen(tester, const LoginScreen());
    await tap(tester, 'Server connection');
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('USB cable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connection screen requires a valid tested backend before saving',
      (tester) async {
    await showScreen(tester, const ServerConnectionScreen());
    final save = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Use this server'), matching: find.byType(FilledButton)));
    expect(save.onPressed, isNull);
    await tester.enterText(find.byType(TextFormField), 'ftp://wrong/api');
    await tap(tester, 'Test connection');
    expect(find.textContaining('Use a full http://'), findsOneWidget);
    expect(AuthService.customBaseUrl, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'wrong health response stays visibly not ready and cannot enable save',
      (tester) async {
    AuthService.setHttpClientForTests(
        MockClient((_) async => http.Response('<html>other app</html>', 200)));
    await showScreen(tester, const ServerConnectionScreen());
    await tap(tester, 'Test connection');
    expect(find.text('Connection not ready'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Use this server'), matching: find.byType(FilledButton)));
    expect(save.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'successful probe requires confirmation and server switch returns a signed-in user to login',
      (tester) async {
    await showScreen(tester, const ServerConnectionScreen(loginRole: 'DRIVER'));
    await tester.enterText(
        find.byType(TextFormField), 'http://192.168.1.20:8000/api');
    await tap(tester, 'Test connection');
    expect(find.text('DriveMate API reached'), findsOneWidget);
    await tap(tester, 'Use this server');
    expect(find.text('Use this trusted server?'), findsOneWidget);
    expect(await AuthService.hasSession(), isTrue);
    await tap(tester, 'Use server');
    expect(await AuthService.hasSession(), isFalse);
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'editing after a successful test disables save until the new address is tested',
      (tester) async {
    await showScreen(tester, const ServerConnectionScreen());
    await tap(tester, 'Test connection');
    expect(find.text('DriveMate API reached'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField), 'http://192.168.1.88:8000/api');
    await settle(tester);
    final save = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Use this server'), matching: find.byType(FilledButton)));
    expect(save.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
