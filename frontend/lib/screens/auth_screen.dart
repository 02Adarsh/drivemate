import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'register_screen.dart';

/// Backwards-compatible entry point.
///
/// Older code pushed `AuthScreen(role: ...)` when it wanted the combined
/// login/signup screen. That screen is now split into two pages that match the
/// reference design, so this class simply forwards:
///
///   AuthScreen(role: 'DRIVER', startOnSignup: true) -> RegisterScreen
///   AuthScreen(role: 'CUSTOMER')                    -> LoginScreen
class AuthScreen extends StatelessWidget {
  final String role;
  final bool startOnSignup;

  const AuthScreen(
      {super.key, this.role = 'CUSTOMER', this.startOnSignup = false});

  @override
  Widget build(BuildContext context) =>
      startOnSignup ? RegisterScreen(role: role) : LoginScreen(role: role);
}
