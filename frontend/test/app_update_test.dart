import 'dart:async';
import 'dart:convert';

import 'package:drivemate/services/app_update.dart';
import 'package:drivemate/widgets/app_update_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> releaseFixture({
  String tag = 'v1.8.0+18',
  String? page,
  bool draft = false,
  bool prerelease = false,
  List<Object?>? assets,
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': page ??
          'https://github.com/02Adarsh/drivemate/releases/tag/${Uri.encodeComponent(tag)}',
      'assets': assets ??
          [
            {'name': 'app-release.apk', 'state': 'uploaded'}
          ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('release parser', () {
    test('uses Android build number and validates the trusted release', () {
      final update = AppUpdateService.parseRelease(releaseFixture(), 17);
      expect(update?.tag, 'v1.8.0+18');
      expect(update?.buildNumber, 18);
      expect(update?.releasePage.host, 'github.com');
      expect(AppUpdateService.parseRelease(releaseFixture(), 18), isNull);
      expect(AppUpdateService.parseRelease(releaseFixture(), 19), isNull);
      expect(AppUpdateService.parseRelease(releaseFixture(), 0), isNull);
    });

    test(
        'ignores wrong tags, missing APK, drafts, prereleases and untrusted URLs',
        () {
      for (final bad in [
        releaseFixture(tag: 'v1.8.0'),
        releaseFixture(tag: 'v1.8.0+0'),
        releaseFixture(tag: 'v1.8.0+999999999999999999999999999999999'),
        releaseFixture(assets: []),
        releaseFixture(assets: [
          {'name': 'app-release.apk', 'state': 'new'}
        ]),
        releaseFixture(draft: true),
        releaseFixture(prerelease: true),
        releaseFixture(
            page:
                'http://github.com/02Adarsh/drivemate/releases/tag/v1.8.0%2B18'),
        releaseFixture(
            page:
                'https://github.com.evil.example/02Adarsh/drivemate/releases/tag/v1.8.0%2B18'),
        releaseFixture(
            page: 'https://github.com/other/repo/releases/tag/v1.8.0%2B18'),
        releaseFixture(
            page:
                'https://github.com/02Adarsh/drivemate/releases/tag/v1.8.0%2B19'),
      ]) {
        expect(AppUpdateService.parseRelease(bad, 17), isNull, reason: '$bad');
      }
    });
  });

  test('GitHub check handles valid, offline and rate-limited responses safely',
      () async {
    final valid = MockClient((request) async {
      expect(request.url, AppUpdateService.latestRelease);
      return http.Response(jsonEncode(releaseFixture()), 200);
    });
    final result = await AppUpdateService.check(
        client: valid, getInstalledBuild: () async => '17');
    expect(result?.buildNumber, 18);
    final limited = MockClient((_) async => http.Response('rate limited', 403));
    expect(
        await AppUpdateService.check(
            client: limited, getInstalledBuild: () async => '17'),
        isNull);
    final offline = MockClient((_) async => throw Exception('offline'));
    expect(
        await AppUpdateService.check(
            client: offline, getInstalledBuild: () async => '17'),
        isNull);
    expect(
        await AppUpdateService.check(
            client: valid, getInstalledBuild: () async => 'not-a-number'),
        isNull);
  });

  final update = AppUpdateService.parseRelease(releaseFixture(), 17)!;

  Future<void> show(WidgetTester tester,
      {required GlobalKey<NavigatorState> key,
      required ValueNotifier<bool> ready,
      required UpdateCheck check,
      UpdateLaunch? launch}) async {
    await tester.pumpWidget(AppUpdateWatcher(
      navigatorKey: key,
      startupReady: ready,
      check: check,
      launch: launch,
      child: MaterialApp(
          navigatorKey: key, home: const Scaffold(body: Text('Home'))),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('waits for splash, dismisses, and prompts again on reopening',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(false);
    addTearDown(ready.dispose);
    var checks = 0;
    await show(tester, key: key, ready: ready, check: () async {
      checks++;
      return update;
    });
    expect(find.text('Update available'), findsNothing);
    expect(checks, 0);
    ready.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(checks, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Update opens the trusted release and retry occurs after return',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    addTearDown(ready.dispose);
    Uri? opened;
    await show(tester,
        key: key,
        ready: ready,
        check: () async => update,
        launch: (uri) async {
          opened = uri;
          return true;
        });
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(opened, update.releasePage);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offline check fails open and retries on next resume',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    addTearDown(ready.dispose);
    var checks = 0;
    await show(tester, key: key, ready: ready, check: () async {
      checks++;
      if (checks == 1) throw Exception('offline');
      return update;
    });
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a resume during an unfinished check triggers a fresh check',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    addTearDown(ready.dispose);
    final first = Completer<AppReleaseUpdate?>();
    var checks = 0;
    await show(tester, key: key, ready: ready, check: () {
      checks++;
      return checks == 1 ? first.future : Future.value(update);
    });
    expect(checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    first.complete(null);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('never shows a dialog while backgrounded', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    addTearDown(ready.dispose);
    final first = Completer<AppReleaseUpdate?>();
    var checks = 0;
    await show(tester, key: key, ready: ready, check: () {
      checks++;
      return checks == 1 ? first.future : Future.value(update);
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    first.complete(update);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resume while prompt is visible never stacks duplicate dialogs',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final ready = ValueNotifier<bool>(true);
    addTearDown(ready.dispose);
    await show(tester, key: key, ready: ready, check: () async => update);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
