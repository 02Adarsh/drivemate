import 'package:flutter/material.dart';

import 'dm_theme.dart';

/// Surface helpers for the v6 look.
///
/// The visual language: deep near-black canvas, soft rounded panels, hairline
/// borders, one accent colour per card, and a single soft shadow on the elements
/// that float above the page. Nothing here uses blur filters, so scrolling stays
/// cheap on mid-range phones.

/// Extra palette entries that sit on top of `dm_theme.dart`.
Color get panelLift => DmAppearance.instance.dark
    ? const Color(0xFF191F27)
    : Colors.white; // raised surfaces (sheets, app bars)
Color get panelGlass => panel; // cards on top of photos
Color get inkFaint => muted; // tertiary text
Color get dividerSoft => hairline; // in-card dividers
const Color successDeep = Color(0xFF0E2A20);
const Color amberDeep = Color(0xFF2A2113);
const Color blueDeep = Color(0xFF101B2C);

/// Card / panel decoration used everywhere in the app.
BoxDecoration dmSurface({
  Color? color,
  double radius = radiusCard,
  Color? border,
  Color? glow,
  bool raised = false,
}) {
  return BoxDecoration(
    color: color ?? panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? hairline),
    boxShadow: glow != null
        ? [
            BoxShadow(
                color: glow.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 10))
          ]
        : raised
            ? [
                const BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 8))
              ]
            : null,
  );
}

/// Gradient panel: one accent colour fading into the dark surface.
BoxDecoration dmGradientSurface({
  required Color accent,
  double radius = 24,
  double strength = 0.24,
  List<Color>? colors,
}) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors ?? [Color.lerp(panel, accent, strength)!, panel],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: 0.28)),
  );
}

/// Bottom-sheet shape + colour, so every sheet in the app looks the same.
BoxDecoration get dmSheetDecoration => BoxDecoration(
      color: panelLift,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      border: Border(top: BorderSide(color: hairline)),
    );

/// Small vertical scrollbar-free list padding used by sheets.
const EdgeInsets dmSheetPadding = EdgeInsets.fromLTRB(20, 8, 20, 24);

/// Standard bottom-sheet header: grabber, title, optional subtitle and close.
class DmSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const DmSheetHeader(
      {super.key, required this.title, this.subtitle, this.onClose});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(
                color: hairline, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: dmHeading(size: 19)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(subtitle!, style: dmSubtitle(size: 12.4)),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Close',
              ),
          ],
        ),
      ],
    );
  }
}

/// Shows a modal bottom sheet with the standard look. Returns the value the
/// sheet was popped with.
Future<T?> dmShowSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xCC000000),
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: Container(
        decoration: dmSheetDecoration,
        constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(sheetContext).height -
                    MediaQuery.viewInsetsOf(sheetContext).bottom) *
                0.86),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: dmSheetPadding,
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DmSheetHeader(
                    title: title,
                    subtitle: subtitle,
                    onClose: () => Navigator.pop(sheetContext),
                  ),
                  const SizedBox(height: 6),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
