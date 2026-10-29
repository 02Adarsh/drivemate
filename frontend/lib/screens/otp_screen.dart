import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../utils/validators.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import 'login_screen.dart';

/// Email verification.
///
/// Development note: with the default Django console email backend the 6-digit
/// code is printed in the terminal where `runserver` is running (and in the
/// Emails table of the admin site). Real email delivery needs SMTP settings in
/// `backend/.env`.
class OtpScreen extends StatefulWidget {
  final String email;
  final String role;
  final String purpose;
  const OtpScreen(
      {super.key,
      required this.email,
      this.role = 'CUSTOMER',
      this.purpose = 'VERIFY_EMAIL'});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result =
          await AuthService.verifyOtp(widget.email, _code.text.trim());
      await AuthService.saveSession(result);
      if (!mounted) return;
      routeAfterAuth(context, result);
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      if (widget.purpose == 'LOGIN') {
        await AuthService.requestLoginOtp(widget.email);
      } else {
        await AuthService.resendOtp(widget.email);
      }
      if (!mounted) return;
      showDmMessage(context, 'A new code has been sent to ${widget.email}');
      _startCountdown();
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      backFallback: LoginScreen(role: widget.role),
      padding: const EdgeInsets.fromLTRB(23, 8, 23, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.mark_email_read_outlined,
                  color: red, size: 26),
            ),
            const SizedBox(height: 22),
            Text('Check your inbox', style: dmHeading(size: 27)),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit verification code we sent to ${widget.email}.',
              style: dmSubtitle(size: 13.2),
            ),
            const SizedBox(height: 26),
            DmField(
              controller: _code,
              hint: '• • • • • •',
              icon: Icons.password_rounded,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: DmValidators.otp,
            ),
            const SizedBox(height: 18),
            DmPrimaryButton(
                label: 'Verify email', loading: _busy, onPressed: _verify),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _secondsLeft == 0 ? _resend : null,
                child: Text(
                  _secondsLeft == 0
                      ? 'Resend code'
                      : 'Resend code in ${_secondsLeft}s',
                  style: TextStyle(
                      color: _secondsLeft == 0 ? red : muted, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const DmInfoBox(
              text:
                  'Check Inbox and Spam. Account codes are private: never share them. Email delivery requires the SMTP settings on your backend; use Resend after the cooldown.',
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () =>
                    goBackOr(context, fallback: LoginScreen(role: widget.role)),
                child: Text('Wrong email address? Go back',
                    style: dmCaption(size: 11.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
