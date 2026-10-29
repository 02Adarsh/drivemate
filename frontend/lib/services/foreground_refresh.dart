import 'dart:async';

import 'package:flutter/material.dart';

/// Lightweight beta polling. Only runs while the app is foregrounded AND this
/// route is visible. It stops on pause/dispose; this is not background push,
/// WebSockets, GPS tracking or a guarantee of instantaneous delivery.
mixin ForegroundRefresh<T extends StatefulWidget> on State<T> {
  Timer? _refreshTimer;
  AppLifecycleListener? _lifecycleListener;
  Future<void> Function()? _refreshCallback;
  Duration _refreshInterval = const Duration(seconds: 8);

  void startForegroundRefresh(Future<void> Function() refresh,
      {Duration interval = const Duration(seconds: 8)}) {
    _refreshCallback = refresh;
    _refreshInterval = interval;
    _lifecycleListener ??= AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        _scheduleRefresh();
        _tick();
      } else {
        _refreshTimer?.cancel();
        _refreshTimer = null;
      }
    });
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (_refreshCallback != null &&
        (state == null || state == AppLifecycleState.resumed)) {
      _refreshTimer = Timer.periodic(_refreshInterval, (_) => _tick());
    }
  }

  void _tick() {
    if (!mounted || _refreshCallback == null) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _refreshCallback!(); // Each screen catches API failures and guards concurrent calls.
  }

  void stopForegroundRefresh() {
    _refreshCallback = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    stopForegroundRefresh();
    _lifecycleListener?.dispose();
    super.dispose();
  }
}
