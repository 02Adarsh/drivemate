import 'package:flutter/material.dart';

import '../screens/driver_application_status_screen.dart';
import '../screens/driver_documents_screen.dart';
import '../screens/driver_driving_details_screen.dart';
import '../screens/driver_personal_profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/profile_setup_screen.dart';

/// Shared page transition.
///
/// Uses [MaterialPageRoute], which now picks up the app-wide
/// `CupertinoPageTransitionsBuilder` from the theme: a smooth slide plus the
/// swipe-from-edge back gesture on both Android and iOS.
Route<T> dmRoute<T>(Widget page) => MaterialPageRoute<T>(builder: (_) => page);

/// Push a page and remove everything behind it (used after login / OTP).
void pushClean(BuildContext context, Widget page) {
  Navigator.of(context).pushAndRemoveUntil(dmRoute(page), (_) => false);
}

/// Replace the current screen (no back stack entry left behind).
void replaceWith(BuildContext context, Widget page) {
  Navigator.of(context).pushReplacement(dmRoute(page));
}

/// Back behaviour that always works.
///
/// 1. If there is something to pop, pop it (animated, swipe-friendly), handing
///    [result] to the screen below (steps use `true` to mean "data changed").
/// 2. Otherwise replace the screen with [fallback].
/// 3. Otherwise go to the introduction pages, so a person is never stuck on a
///    dead screen with a back arrow that does nothing.
///
/// Use this instead of `Navigator.maybePop()`: `maybePop` *silently does
/// nothing* when the current screen was opened with `pushClean` /
/// `pushReplacement` (no route below), which is exactly the bug where the
/// top-left arrow appears broken.
void goBackOr(BuildContext context, {Widget? fallback, Object? result}) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
    return;
  }
  navigator.pushReplacement(dmRoute(fallback ?? const OnboardingScreen()));
}

/// True when the current screen has another route underneath it.
bool canGoBack(BuildContext context) => Navigator.of(context).canPop();

/// Where to send a person after login / OTP / registration.
///
/// The server decides: `next_step` comes from the backend, so the app can never
/// decide on its own that a registration step is finished.
void routeAfterAuth(BuildContext context, Map<String, dynamic> payload) {
  final user =
      (payload['user'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  final driver = (payload['driver'] as Map?)?.cast<String, dynamic>();
  final role = (user['role'] ?? 'CUSTOMER').toString();
  final nextStep = (user['next_step'] ?? driver?['next_step'] ?? '').toString();
  final name = (user['name'] ?? 'there').toString();

  if (role == 'DRIVER') {
    switch (nextStep) {
      case 'PERSONAL_PROFILE':
        pushClean(context, DriverPersonalProfileScreen(name: name));
        return;
      case 'DRIVING_DETAILS':
        pushClean(context, DriverDrivingDetailsScreen(name: name));
        return;
      case 'DOCUMENTS':
        pushClean(context, DriverDocumentsScreen(name: name));
        return;
      case 'UNDER_REVIEW':
      case 'FIX_AND_RESUBMIT':
      case 'SUSPENDED':
        pushClean(context, DriverApplicationStatusScreen(name: name));
        return;
      case 'DASHBOARD':
        pushClean(context, HomeScreen(role: 'Driver', name: name));
        return;
      default:
        pushClean(context, DriverPersonalProfileScreen(name: name));
        return;
    }
  }

  if (role == 'ADMIN') {
    pushClean(context, HomeScreen(role: 'Admin', name: name));
    return;
  }

  if (nextStep == 'DASHBOARD') {
    pushClean(context, HomeScreen(role: 'Customer', name: name));
  } else {
    pushClean(context, ProfileSetupScreen(name: name, role: 'CUSTOMER'));
  }
}

String roleLabel(String role) {
  switch (role.toUpperCase()) {
    case 'DRIVER':
      return 'Driver';
    case 'ADMIN':
      return 'Administrator';
    default:
      return 'Rider';
  }
}
