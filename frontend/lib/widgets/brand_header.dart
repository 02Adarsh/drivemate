import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import 'brand_mark.dart';

/// Logo + wordmark + tagline, exactly like the reference screens.
///
/// [trailing] sits on the right (for example "Don't have an account? Sign Up").
class BrandHeader extends StatelessWidget {
  final Widget? trailing;
  final double markSize;
  const BrandHeader({super.key, this.trailing, this.markSize = 46});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4),
                  children: <TextSpan>[
                    TextSpan(text: 'Drive', style: TextStyle(color: softWhite)),
                    const TextSpan(text: 'Mate', style: TextStyle(color: red)),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'RIDE TOGETHER. ALWAYS BETTER.',
                style: TextStyle(
                  color: muted,
                  fontSize: 7.2,
                  letterSpacing: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
