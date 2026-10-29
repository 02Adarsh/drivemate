import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_screen.dart';
import '../utils/validators.dart';
import 'forgot_password_screen.dart';
import 'onboarding_screen.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, this.role = 'CUSTOMER'});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _role;
  bool _busy = false;
  bool _hidden = true;
  @override
  void initState() {
    super.initState();
    _role = widget.role;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final data = await AuthService.login(
          identifier: _email.text.trim(),
          password: _password.text,
          role: _role);
      await AuthService.saveSession(data);
      if (mounted) routeAfterAuth(context, data);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.payload?['needs_verification'] == true) {
        await Navigator.of(context).push(dmRoute(OtpScreen(
            email: (e.payload?['email'] ?? _email.text).toString(),
            role: _role)));
      } else {
        showDmMessage(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailCode() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showDmMessage(
          context, 'Enter your account email above to receive a sign-in code.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.requestLoginOtp(email);
      if (!mounted) return;
      await Navigator.of(context).push(
          dmRoute(OtpScreen(email: email, role: _role, purpose: 'LOGIN')));
    } on ApiException catch (e) {
      if (mounted) showDmMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DmScreen(
        showBack: true,
        backFallback: const OnboardingScreen(),
        child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const BrandMark(size: 48),
                  const Spacer(),
                  IconButton(
                      onPressed: () => DmAppearance.instance
                          .setDark(!DmAppearance.instance.dark),
                      icon: Icon(DmAppearance.instance.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined),
                      tooltip: 'Light / Dark mode')
                ]),
                const SizedBox(height: 30),
                Text('Welcome Back!', style: dmHeading(size: 34)),
                const SizedBox(height: 9),
                Text(
                    dmLocal('Your car. Your driver. Your day.',
                        'आपकी कार। आपका ड्राइवर। आपका दिन।'),
                    style: dmSubtitle(size: 15)),
                const SizedBox(height: 26),
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'CUSTOMER', label: Text('Rider')),
                      ButtonSegment(value: 'DRIVER', label: Text('Driver'))
                    ],
                    selected: {
                      _role == 'ADMIN' ? 'CUSTOMER' : _role
                    },
                    onSelectionChanged:
                        _busy ? null : (v) => setState(() => _role = v.first)),
                if (_role == 'ADMIN')
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Staff sign-in', style: dmCaption())),
                const SizedBox(height: 20),
                DmField(
                    controller: _email,
                    hint: 'Email or mobile number',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: DmValidators.identifier),
                const SizedBox(height: 14),
                DmField(
                    controller: _password,
                    hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscure: _hidden,
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Enter your password' : null,
                    suffix: IconButton(
                        onPressed: () => setState(() => _hidden = !_hidden),
                        icon: Icon(_hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined))),
                Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () => Navigator.of(context)
                            .push(dmRoute(const ForgotPasswordScreen())),
                        child: const Text('Forgot Password?'))),
                DmPrimaryButton(
                    label: 'Log In', loading: _busy, onPressed: _login),
                const SizedBox(height: 13),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: _busy ? null : _emailCode,
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text('Continue with email code'))),
                const SizedBox(height: 24),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('New to DriveMate?', style: dmCaption(size: 13)),
                  TextButton(
                      onPressed: () => Navigator.of(context).push(dmRoute(
                          RegisterScreen(
                              role: _role == 'ADMIN' ? 'CUSTOMER' : _role))),
                      child: const Text('Create account'))
                ]),
                const Divider(),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() =>
                            _role = _role == 'ADMIN' ? 'CUSTOMER' : 'ADMIN'),
                    child: Text(_role == 'ADMIN'
                        ? 'Back to rider login'
                        : 'Staff sign-in')),
                const SizedBox(height: 10),
                Text(
                    'Account email codes are private. Trip-start codes are separate and only shared with your assigned driver when you meet.',
                    style: dmCaption(size: 11)),
              ],
            )));
  }
}
