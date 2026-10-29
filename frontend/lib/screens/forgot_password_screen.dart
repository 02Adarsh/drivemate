import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../utils/validators.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import 'login_screen.dart';

/// Two-step password reset: request a code, then set a new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();

  int _step = 0;
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_step == 0) {
        await AuthService.requestPasswordReset(_email.text.trim());
        if (!mounted) return;
        setState(() => _step = 1);
        showDmMessage(
            context, 'If that account exists, a reset code has been sent.');
      } else {
        await AuthService.confirmPasswordReset(
            _email.text.trim(), _otp.text.trim(), _password.text);
        if (!mounted) return;
        showDmMessage(
            context, 'Password changed. Sign in with your new password.');
        goBackOr(context, fallback: const LoginScreen());
      }
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      backFallback: const LoginScreen(),
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
              child: const Icon(Icons.lock_reset_rounded, color: red, size: 26),
            ),
            const SizedBox(height: 22),
            Text(
              _step == 0 ? 'Reset your password' : 'Create a new password',
              style: dmHeading(size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              _step == 0
                  ? 'We will email a one-time reset code to your registered address.'
                  : 'Enter the code from your email and choose a new password.',
              style: dmSubtitle(size: 13.2),
            ),
            const SizedBox(height: 24),
            DmField(
              controller: _email,
              hint: 'Email address',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              enabled: _step == 0,
              validator: DmValidators.email,
            ),
            if (_step == 1) ...[
              const SizedBox(height: 12),
              DmField(
                controller: _otp,
                hint: '6-digit reset code',
                icon: Icons.password_rounded,
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: DmValidators.otp,
              ),
              const SizedBox(height: 12),
              DmField(
                controller: _password,
                hint: 'New password',
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                validator: DmValidators.password,
                suffix: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(
                      _hide
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19),
                ),
              ),
            ],
            const SizedBox(height: 20),
            DmPrimaryButton(
              label: _step == 0 ? 'Send reset code' : 'Update password',
              loading: _busy,
              onPressed: _next,
            ),
          ],
        ),
      ),
    );
  }
}
