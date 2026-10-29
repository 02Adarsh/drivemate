import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import 'auth_backdrop.dart';
import 'dm_back_button.dart';

/// Standard screen shell: backdrop, safe area, optional back arrow and either a
/// scrollable or fixed body.
///
/// [onBack] lets a screen decide where "back" goes. This matters because after
/// OTP verification the navigation stack is cleared (`pushClean`), so a plain
/// `Navigator.maybePop()` would silently do nothing — the arrow would look
/// broken. Passing [onBack] (or [backFallback]) guarantees the arrow always
/// does something useful, and the same action is wired to the phone's hardware
/// / gesture back button through [PopScope].
class DmScreen extends StatelessWidget {
  final Widget child;
  final bool scroll;
  final bool showBack;
  final bool cinematic; // photo backdrop (splash/onboarding) instead of glows
  final EdgeInsets padding;
  final Widget? topBar;
  final bool keyboardSafe;

  /// Explicit back action (takes priority).
  final VoidCallback? onBack;

  /// Used when there is nothing on the stack to pop: the app replaces the
  /// current screen with this widget.
  final Widget? backFallback;

  /// Value handed to the screen below when this one pops (steps pass `true`
  /// so the dashboard knows it should refresh).
  final Object? backResult;

  /// Custom back arrow (colour / size / tooltip).
  final Color? backColor;

  const DmScreen({
    super.key,
    required this.child,
    this.scroll = true,
    this.showBack = false,
    this.cinematic = false,
    this.padding = const EdgeInsets.fromLTRB(23, 6, 23, 26),
    this.topBar,
    this.keyboardSafe = true,
    this.onBack,
    this.backFallback,
    this.backResult,
    this.backColor,
  });

  void _handleBack(BuildContext context) {
    final explicit = onBack;
    if (explicit != null) {
      explicit();
      return;
    }
    goBackOr(context, fallback: backFallback, result: backResult);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    // If there is a route below, popping is the natural behaviour. If there is
    // not (login/register/OTP after `pushClean`), the system back button would
    // normally close the app - send the person to the fallback instead.
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final hasFallbackAction = onBack != null || backFallback != null;

    return PopScope(
      canPop: canPop || !hasFallbackAction,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: navy,
        resizeToAvoidBottomInset: keyboardSafe,
        body: Stack(
          children: [
            Positioned.fill(
              child: cinematic
                  ? const CinematicBackdrop()
                  : const AuthBackdrop(child: SizedBox.shrink()),
            ),
            SafeArea(
              child: Column(
                children: [
                  if (topBar != null) topBar!,
                  if (showBack)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: DmBackButton(
                          onBack: onBack,
                          fallback: backFallback,
                          result: backResult,
                          color: backColor,
                        ),
                      ),
                    ),
                  Expanded(
                    child: scroll
                        ? SingleChildScrollView(
                            padding: padding,
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: child,
                          )
                        : Padding(padding: padding, child: child),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
