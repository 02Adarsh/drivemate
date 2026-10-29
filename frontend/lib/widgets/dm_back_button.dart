import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../theme/dm_theme.dart';

/// A back arrow that **always** does something.
///
/// This is the fix for the "back arrow does nothing" bug. Screens in this app
/// are opened in three different ways:
///
///  1. pushed on top of another screen                    → pop works
///  2. opened with `pushClean` / `pushReplacement`        → **no route below**
///  3. the first screen of a flow (login, register, …)    → **no route below**
///
/// `Navigator.maybePop(context)` silently does nothing in cases 2 and 3, which
/// is exactly how an arrow ends up looking broken on a real phone. This button
/// never leaves the user stuck:
///
///  * [onBack] given        → runs it (screen decides where to go)
///  * something to pop      → pops, handing [result] to the screen below
///  * nothing to pop        → replaces the screen with [fallback]
///  * neither               → sends the user to the introduction pages
class DmBackButton extends StatelessWidget {
  /// Explicit action; takes priority over popping.
  final VoidCallback? onBack;

  /// Screen to show when there is nothing on the stack to pop.
  final Widget? fallback;

  /// Value handed back to the screen below (e.g. `true` = "data changed,
  /// please refresh"). Ignored when [fallback] is used.
  final Object? result;

  final Color? color;
  final double size;
  final String tooltip;

  const DmBackButton({
    super.key,
    this.onBack,
    this.fallback,
    this.result,
    this.color,
    this.size = 21,
    this.tooltip = 'Back',
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return IconButton(
      onPressed: () {
        final explicit = onBack;
        if (explicit != null) {
          explicit();
          return;
        }
        goBackOr(context, fallback: fallback, result: result);
      },
      icon:
          Icon(Icons.arrow_back_rounded, size: size, color: color ?? softWhite),
      tooltip: tooltip,
      // Comfortably large touch target: the arrow is easy to hit one-handed.
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}
