import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// One place for user-facing messages, so the app never shows a raw exception.
void showDmMessage(BuildContext context, String message,
    {bool error = false, Duration? duration}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration ?? const Duration(seconds: 3),
        backgroundColor: error ? const Color(0xFF3A1A1D) : panel2,
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: error ? danger : success,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    color: softWhite,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Full-screen friendly error state with a retry action.
class DmErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  const DmErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: danger, size: 28),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center, style: dmCaption(size: 12.5)),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 190,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
