import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../services/session_resume.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_feedback.dart';
import 'login_screen.dart';

/// Gate dashboard access on a fresh progress check, including after an app
/// restart. An offline or malformed response never counts as completion.
class SessionResumeScreen extends StatefulWidget {
  final VoidCallback? onReady;
  const SessionResumeScreen({super.key, this.onReady});

  @override
  State<SessionResumeScreen> createState() => _SessionResumeScreenState();
}

class _SessionResumeScreenState extends State<SessionResumeScreen> {
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await loadResumeState();
      if (!mounted) return;
      routeAfterAuth(context, state);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not check your progress. Please try again.';
          _loading = false;
        });
      }
    } finally {
      // Wait until the session gate finishes navigation (or shows its error),
      // so its clean route replacement cannot remove an update dialog.
      if (mounted) widget.onReady?.call();
    }
  }

  Future<void> _signOut() async {
    await AuthService.clearSession();
    if (!mounted) return;
    pushClean(context, const LoginScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DmErrorState(
                      title: 'Could not check your progress',
                      message: _error ?? 'Please try again.',
                      onRetry: _load,
                    ),
                    TextButton(
                        onPressed: _signOut, child: const Text('Sign out')),
                  ],
                ),
        ),
      ),
    );
  }
}
