import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'onboarding_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final email = TextEditingController(), otp = TextEditingController(), password = TextEditingController();
  int step = 0;
  bool busy = false, obscure = true;
  @override void dispose() { email.dispose(); otp.dispose(); password.dispose(); super.dispose(); }

  Future<void> next() async {
    if (email.text.trim().isEmpty || !email.text.contains('@')) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the account email address.'))); return; }
    if (step == 1 && (otp.text.length != 6 || password.text.length < 8)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the 6-digit code and a password with at least 8 characters.'))); return; }
    setState(() => busy = true);
    try {
      if (step == 0) {
        await AuthService.requestPasswordReset(email.text.trim());
        if (!mounted) return;
        setState(() => step = 1);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If the account exists, a reset code has been sent.')));
      } else {
        await AuthService.confirmPasswordReset(email.text.trim(), otp.text.trim(), password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. Sign in with your new password.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: red));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(children: [
      const Positioned.fill(child: CinematicBackdrop()),
      SafeArea(child: Padding(padding: const EdgeInsets.all(23), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
        const SizedBox(height: 24),
        const Icon(Icons.lock_reset_rounded, color: red, size: 42),
        const SizedBox(height: 17),
        Text(step == 0 ? 'Reset your password' : 'Create a new password', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(step == 0 ? 'We’ll email a secure one-time reset code.' : 'Enter the code sent to your email and choose a new password.', style: const TextStyle(color: muted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 23),
        TextField(controller: email, enabled: step == 0, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined))),
        if (step == 1) ...[
          const SizedBox(height: 12),
          TextField(controller: otp, maxLength: 6, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit reset code', prefixIcon: Icon(Icons.password), counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'New password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_off : Icons.visibility)))),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: busy ? null : next, style: FilledButton.styleFrom(backgroundColor: red), child: busy ? const CircularProgressIndicator(color: Colors.white) : Text(step == 0 ? 'Send reset code' : 'Update password'))),
      ]))),
    ]),
  );
}
