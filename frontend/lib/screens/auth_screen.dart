import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../widgets/brand_mark.dart';
import 'driver_documents_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'otp_screen.dart';
import 'profile_setup_screen.dart';

class AuthScreen extends StatefulWidget {
  final String role;
  const AuthScreen({super.key, this.role = 'CUSTOMER'});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
  bool signup = false, busy = false, obscure = true, obscureConfirm = true, agree = false;
  late String role;
  @override void initState() { super.initState(); role = widget.role; }
  @override void dispose() { name.dispose(); email.dispose(); phone.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }

  bool _validIdentifier(String value) {
    final text = value.trim();
    if (text.contains('@')) { final pieces = text.split('@'); return pieces.length == 2 && pieces[0].isNotEmpty && pieces[1].contains('.') && !pieces[1].startsWith('.') && !pieces[1].endsWith('.'); }
    final digits = text.replaceAll(RegExp('[^0-9]'), '');
    final allowed = text.codeUnits.every((c) => (c >= 48 && c <= 57) || c == 43 || c == 45 || c == 40 || c == 41 || c == 32);
    return allowed && digits.length >= 8 && digits.length <= 15;
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (signup && !agree) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please accept the Terms and Privacy Policy.'))); return; }
    setState(() => busy = true);
    try {
      if (signup) {
        await AuthService.register(name.text.trim(), email.text.trim(), phone.text.trim(), password.text, role);
        if (!mounted) return;
        Navigator.push(context, _route(OtpScreen(email: email.text.trim(), role: role)));
      } else {
        final result = await AuthService.login(email.text.trim(), password.text, role);
        await AuthService.saveSession(result);
        if (!mounted) return;
        final user = result['user'];
        if (user['profile_complete'] == true && (role != 'DRIVER' || user['driver_documents_complete'] == true)) {
          Navigator.pushAndRemoveUntil(context, _route(HomeScreen(role: role == 'DRIVER' ? 'Driver' : 'Customer', name: user['name'])), (_) => false);
        } else if (role == 'DRIVER' && user['profile_complete'] == true) {
          Navigator.pushAndRemoveUntil(context, _route(DriverDocumentsScreen(name: user['name'])), (_) => false);
        } else {
          Navigator.pushAndRemoveUntil(context, _route(ProfileSetupScreen(name: user['name'], role: role)), (_) => false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: red));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Route<T> _route<T>(Widget page) => PageRouteBuilder<T>(pageBuilder: (_, animation, secondary) => page, transitionsBuilder: (_, animation, secondary, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: animation, child: child)), transitionDuration: const Duration(milliseconds: 320), reverseTransitionDuration: const Duration(milliseconds: 270));

  Widget _rolePill(String label, String value, IconData icon) => Expanded(child: GestureDetector(onTap: () => setState(() => role = value), child: AnimatedContainer(duration: const Duration(milliseconds: 210), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: role == value ? red : Colors.transparent, borderRadius: BorderRadius.circular(25)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: role == value ? Colors.white : muted), const SizedBox(width: 7), Text(label, style: TextStyle(color: role == value ? Colors.white : muted, fontWeight: FontWeight.w700, fontSize: 12))]))));

  Widget _input({required TextEditingController controller, required String label, required IconData icon, TextInputType? keyboard, bool secret = false, Widget? suffix, String? Function(String?)? validate}) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextFormField(controller: controller, keyboardType: keyboard, obscureText: secret, validator: validate, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: suffix)));

  @override
  Widget build(BuildContext context) => Scaffold(resizeToAvoidBottomInset: true, body: Stack(children: [
    const Positioned.fill(child: CinematicBackdrop()),
    SafeArea(child: Column(children: [Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(23, 12, 23, 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const BrandMark(size: 52), const SizedBox(width: 9), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('DriveMate', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), Text('RIDE TOGETHER. ALWAYS BETTER.', style: TextStyle(color: muted, fontSize: 7, letterSpacing: 1.3))]), const Spacer(), GestureDetector(onTap: () => setState(() => signup = !signup), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(signup ? 'Already have an account?' : 'Don’t have an account?', style: const TextStyle(color: muted, fontSize: 10)), const SizedBox(height: 2), Text(signup ? 'Log in  ›' : 'Sign Up  ›', style: const TextStyle(color: red, fontWeight: FontWeight.w700, fontSize: 11))]))]),
      const SizedBox(height: 42),
      AnimatedSwitcher(duration: const Duration(milliseconds: 320), switchInCurve: Curves.easeOutCubic, switchOutCurve: Curves.easeIn, transitionBuilder: (child, animation) => SlideTransition(position: Tween<Offset>(begin: const Offset(.045, 0), end: Offset.zero).animate(animation), child: FadeTransition(opacity: animation, child: child)), child: Form(key: form, child: Column(key: ValueKey('$signup-$role'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(signup ? 'Create Account' : 'Welcome Back!', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -.5)),
        const SizedBox(height: 5), Text(signup ? 'Join DriveMate and start your journey.' : 'Log in to continue your journey.', style: const TextStyle(color: Color(0xFFBEC3CD), fontSize: 13)),
        const SizedBox(height: 16), Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xC817171B), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(27)), child: Row(children: [_rolePill('Rider', 'CUSTOMER', Icons.directions_car_outlined), _rolePill('Driver', 'DRIVER', Icons.person_pin_circle_outlined)])),
        if (signup) ...[const SizedBox(height: 16), _input(controller: name, label: 'Full name', icon: Icons.person_outline, validate: (v) => v == null || v.trim().length < 2 ? 'Enter your full name' : null)],
        _input(controller: email, label: signup ? 'Email address' : 'Email or phone number', icon: Icons.mail_outline, keyboard: signup ? TextInputType.emailAddress : TextInputType.text, validate: (v) => v == null || !(signup ? _validEmail(v) : _validIdentifier(v)) ? (signup ? 'Enter a valid email' : 'Enter a valid email or phone') : null),
        if (signup) _input(controller: phone, label: 'Phone number', icon: Icons.phone_outlined, keyboard: TextInputType.phone, validate: (v) => v == null || !_validPhone(v) ? 'Enter a valid phone number' : null),
        _input(controller: password, label: 'Password', icon: Icons.lock_outline, secret: obscure, suffix: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined)), validate: (v) => v == null || v.length < 8 ? 'Use at least 8 characters' : null),
        if (signup) ...[
          _input(controller: confirm, label: 'Confirm password', icon: Icons.lock_outline, secret: obscureConfirm, suffix: IconButton(onPressed: () => setState(() => obscureConfirm = !obscureConfirm), icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined)), validate: (v) => v != password.text ? 'Passwords do not match' : null),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: agree, activeColor: red, onChanged: (v) => setState(() => agree = v ?? false), title: const Text.rich(TextSpan(style: TextStyle(color: muted, fontSize: 10), children: [TextSpan(text: 'I agree to the '), TextSpan(text: 'Terms & Conditions', style: TextStyle(color: red)), TextSpan(text: ' and '), TextSpan(text: 'Privacy Policy', style: TextStyle(color: red))]))),
        ] else Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.push(context, _route(const ForgotPasswordScreen())), child: const Text('Forgot Password?', style: TextStyle(color: red, fontSize: 11)))),
        const SizedBox(height: 5),
        SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: busy ? null : submit, style: FilledButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(signup ? 'Create Account' : 'Log In', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 9), const Icon(Icons.arrow_forward_rounded, size: 17)]))),
        const SizedBox(height: 18), const Row(children: [Expanded(child: Divider(color: Colors.white24)), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(color: muted, fontSize: 10))), Expanded(child: Divider(color: Colors.white24))]),
        const SizedBox(height: 13), SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(onPressed: () {}, icon: const Text('G', style: TextStyle(color: Color(0xFF4285F4), fontSize: 19, fontWeight: FontWeight.w800)), label: const Text('Continue with Google', style: TextStyle(fontSize: 11)), style: OutlinedButton.styleFrom(foregroundColor: softWhite, side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
        if (signup) const Padding(padding: EdgeInsets.only(top: 9), child: Center(child: Text('Email verification code will be sent to your inbox.', style: TextStyle(color: muted, fontSize: 10)))),
      ]))),
    ])))])),
  ]));

  bool _validEmail(String value) { final s=value.trim(); final parts=s.split('@'); return parts.length==2&&parts[0].isNotEmpty&&parts[1].contains('.')&&!parts[1].startsWith('.')&&!parts[1].endsWith('.'); }
  bool _validPhone(String value) { final s=value.trim(); final digits=s.replaceAll(RegExp('[^0-9]'),''); final allowed=s.codeUnits.every((c)=>(c>=48&&c<=57)||c==43||c==45||c==40||c==41||c==32); return allowed&&digits.length>=8&&digits.length<=15; }
}
