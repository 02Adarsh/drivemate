import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';

typedef UpdateCheck = Future<AppReleaseUpdate?> Function();
typedef UpdateLaunch = Future<bool> Function(Uri uri);

/// Checks after the splash navigation and every subsequent foreground resume.
/// No last-dismissed version is persisted: choosing Later only dismisses the
/// current prompt and the next opening checks again.
class AppUpdateWatcher extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<bool> startupReady;
  final Widget child;
  final UpdateCheck? check;
  final UpdateLaunch? launch;

  const AppUpdateWatcher({
    super.key,
    required this.navigatorKey,
    required this.startupReady,
    required this.child,
    this.check,
    this.launch,
  });

  @override
  State<AppUpdateWatcher> createState() => _AppUpdateWatcherState();
}

class _AppUpdateWatcherState extends State<AppUpdateWatcher>
    with WidgetsBindingObserver {
  bool _checking = false;
  bool _dialogOpen = false;
  bool _pendingRecheck = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.startupReady.addListener(_onReady);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onReady());
  }

  @override
  void didUpdateWidget(covariant AppUpdateWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startupReady != widget.startupReady) {
      oldWidget.startupReady.removeListener(_onReady);
      widget.startupReady.addListener(_onReady);
    }
  }

  void _onReady() {
    if (mounted && widget.startupReady.value && _foreground) {
      unawaited(_checkForUpdate());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_checking && !_dialogOpen) {
        _pendingRecheck = true;
      } else {
        _onReady();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    _checking = true;
    try {
      final release = await (widget.check ?? AppUpdateService.check)();
      if (!mounted || !_foreground || release == null) return;
      final context = widget.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      // This prompt already serves any resume that occurred during the check.
      _pendingRecheck = false;
      _dialogOpen = true;
      final wantsUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Text('DriveMate ${release.tag} is available. '
              'Open GitHub to download and install the new APK.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (!mounted || wantsUpdate != true) return;
      final open = widget.launch ??
          (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
      final opened = await open(release.releasePage);
      if (!opened && mounted) {
        final messenger = ScaffoldMessenger.maybeOf(
            widget.navigatorKey.currentContext ?? context);
        messenger?.showSnackBar(const SnackBar(
            content: Text('Could not open GitHub. Please try again later.')));
      }
    } catch (_) {
      // The app must remain usable if GitHub, the browser or plugins fail.
    } finally {
      _dialogOpen = false;
      _checking = false;
      if (_pendingRecheck) {
        _pendingRecheck = false;
        if (mounted && _foreground && widget.startupReady.value) {
          unawaited(_checkForUpdate());
        }
      }
    }
  }

  @override
  void dispose() {
    widget.startupReady.removeListener(_onReady);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
