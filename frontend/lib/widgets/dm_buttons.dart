import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import '../config.dart';

/// Primary red action button with an arrow, matching the reference design.
class DmPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  final bool showArrow;

  const DmPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward_rounded,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusButton),
          boxShadow: onPressed == null || loading
              ? null
              : [
                  BoxShadow(
                      color: red.withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 8))
                ],
        ),
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
              backgroundColor:
                  onPressed == null || loading ? panel2 : softWhite,
              foregroundColor: navy),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(strokeWidth: 2.2, color: navy),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Flexible + ellipsis: a long label (or a large system font)
                    // shrinks instead of overflowing the button.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (showArrow) ...[
                      const SizedBox(width: 9),
                      Icon(icon, size: 18),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Dark outlined button used for Google / Apple sign-in.
class DmSocialButton extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback? onPressed;
  final bool comingSoon;

  const DmSocialButton({
    super.key,
    required this.leading,
    required this.label,
    this.onPressed,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: panel2,
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusField)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    color: softWhite),
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(width: 6),
              Text('(soon)', style: dmCaption(size: 10.5)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "──────── OR ────────" divider.
class DmOrDivider extends StatelessWidget {
  const DmOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Row(
      children: [
        Expanded(child: Divider(color: hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR',
              style: dmCaption(size: 10.5).copyWith(letterSpacing: 1.2)),
        ),
        Expanded(child: Divider(color: hairline)),
      ],
    );
  }
}

/// Bottom card: "New to DriveMate? Create your account and get started!"
class DmPromptCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const DmPromptCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.shield_outlined,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: red, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: dmCaption(size: 11.2)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: red, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Small badge that tells the truth about prototype behaviour.
class DmDemoBadge extends StatelessWidget {
  final String? text;
  const DmDemoBadge({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    if (!demoMode && text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_outlined, size: 12, color: warning),
          const SizedBox(width: 5),
          Text(
            text ?? environmentLabel,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: warning),
          ),
        ],
      ),
    );
  }
}

/// Rounded info strip (used for policy notes, warnings and hints).
class DmInfoBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const DmInfoBox({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = info,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: dmCaption(size: 11.6))),
        ],
      ),
    );
  }
}
