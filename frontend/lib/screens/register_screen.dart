import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../utils/validators.dart';
import '../widgets/brand_header.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_back_button.dart';
import '../widgets/dm_fields.dart';
import '../widgets/policy_sheet.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

/// Step 1 of registration: create the account.
///
/// Layout follows the reference design (Rider | Driver switch, five fields,
/// terms row, red Create Account button, Google/Apple buttons).
///
/// The role sent here is only a *request*: the backend always sets the role
/// itself and rejects attempts to create an ADMIN account through signup.
class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, this.role = 'CUSTOMER'});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _referral = TextEditingController();

  late String _role;
  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _role = widget.role == 'DRIVER' ? 'DRIVER' : 'CUSTOMER';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _referral.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      showDmMessage(
          context, 'Please accept the Terms & Conditions and Privacy Policy.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.register(
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        password: _password.text,
        confirmPassword: _confirm.text,
        referralCode: _referral.text.trim().toUpperCase(),
        role: _role,
      );
      if (!mounted) return;
      showDmMessage(
          context, 'Account created. Enter the 6-digit code we emailed you.');
      Navigator.of(context).pushReplacement(
        dmRoute(OtpScreen(email: _email.text.trim(), role: _role)),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final isDriver = _role == 'DRIVER';

    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 20, 2),
                  child: Row(
                    children: [
                      DmBackButton(fallback: LoginScreen(role: _role)),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Already have an account?',
                              style: dmCaption(size: 11)),
                          const SizedBox(height: 2),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pushReplacement(
                                dmRoute(LoginScreen(role: _role))),
                            child: const Text(
                              'Log In  ›',
                              style: TextStyle(
                                  color: red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 23),
                  child: BrandHeader(markSize: 46),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(23, 26, 23, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DmEntrance(
                          child: Text('Create Account',
                              style: dmHeading(size: 28))),
                      const SizedBox(height: 7),
                      DmEntrance(
                        delay: 60,
                        child: Text(
                          isDriver
                              ? 'Start your driver application. You will complete your profile, driving details and documents in the next steps.'
                              : 'Join DriveMate and start your journey in just a few steps.',
                          style: dmSubtitle(size: 13.2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      DmEntrance(
                        delay: 110,
                        child: _RolePill(
                          role: _role,
                          onChanged: (value) => setState(() => _role = value),
                        ),
                      ),
                      const SizedBox(height: 18),
                      DmEntrance(
                          delay: 150,
                          child: DmField(
                            controller: _name,
                            hint: 'Full Name',
                            icon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                            validator: DmValidators.fullName,
                          )),
                      const SizedBox(height: 12),
                      DmEntrance(
                          delay: 190,
                          child: DmField(
                            controller: _email,
                            hint: 'Email Address',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: DmValidators.email,
                          )),
                      const SizedBox(height: 12),
                      DmEntrance(
                          delay: 230,
                          child: DmField(
                            controller: _phone,
                            hint: 'Phone Number',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            validator: DmValidators.phone,
                            helper:
                                'Used for booking updates. Login stays on your email address.',
                          )),
                      const SizedBox(height: 12),
                      DmEntrance(
                          delay: 270,
                          child: DmField(
                            controller: _password,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscure: _hidePassword,
                            textInputAction: TextInputAction.next,
                            validator: DmValidators.password,
                            suffix: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                              ),
                            ),
                          )),
                      const SizedBox(height: 12),
                      DmEntrance(
                          delay: 310,
                          child: DmField(
                            controller: _confirm,
                            hint: 'Confirm Password',
                            icon: Icons.lock_outline_rounded,
                            obscure: _hideConfirm,
                            textInputAction: TextInputAction.done,
                            validator: (value) => DmValidators.confirmPassword(
                                value, _password.text),
                            suffix: IconButton(
                              onPressed: () =>
                                  setState(() => _hideConfirm = !_hideConfirm),
                              icon: Icon(
                                _hideConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                              ),
                            ),
                          )),
                      const SizedBox(height: 10),
                      DmEntrance(
                          delay: 350,
                          child: DmAgreementRow(
                            value: _agreed,
                            onChanged: (value) =>
                                setState(() => _agreed = value),
                            text: [
                              const TextSpan(text: 'I agree to the '),
                              policySpan('Terms & Conditions', context,
                                  PolicyDoc.terms),
                              const TextSpan(text: ' and '),
                              policySpan(
                                  'Privacy Policy', context, PolicyDoc.privacy),
                            ],
                          )),
                      const SizedBox(height: 16),
                      Column(children: [
                        DmField(
                            controller: _referral,
                            hint: 'Invitation code (optional)',
                            icon: Icons.redeem_outlined,
                            maxLength: 12),
                        const SizedBox(height: 14),
                        DmEntrance(
                            delay: 390,
                            child: DmPrimaryButton(
                                label: 'Create Account',
                                loading: _busy,
                                onPressed: _submit))
                      ]),
                      const SizedBox(height: 20),
                      DmPromptCard(
                        icon: Icons.login_rounded,
                        title: 'Already registered?',
                        subtitle: 'Log in to continue where you left off.',
                        onTap: () => Navigator.of(context)
                            .pushReplacement(dmRoute(LoginScreen(role: _role))),
                      ),
                      if (isDriver) ...[
                        const SizedBox(height: 16),
                        const DmInfoBox(
                          text:
                              'After signup: 1) verify email  2) personal profile  3) driving details  4) documents + consent  5) admin verification. '
                              'You stay offline until an admin approves your application.',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rider | Driver switch, styled like the reference design.
class _RolePill extends StatelessWidget {
  final String role;
  final ValueChanged<String> onChanged;
  const _RolePill({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: panel3,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: hairline),
      ),
      child: Row(
        children: [
          _pill(
            label: 'Rider',
            icon: Icons.directions_car_outlined,
            value: 'CUSTOMER',
            selected: role == 'CUSTOMER',
          ),
          _pill(
            label: 'Driver',
            icon: Icons.person_pin_circle_outlined,
            value: 'DRIVER',
            selected: role == 'DRIVER',
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required String value,
    required bool selected,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? red : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: red.withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? Colors.white : muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
