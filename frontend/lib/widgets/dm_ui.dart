import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import 'dm_animations.dart';

/// v6 UI kit — the pieces the new Uber-style screens are built from.
///
/// All of them are plain widgets on purpose: flat colours, one gradient each,
/// no blur, no animation controller running in the background.

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Big tappable search field (the app never opens a keyboard directly from it -
/// it opens whatever flow the screen needs).
class DmSearchBar extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback? onTap;
  final IconData icon;
  final Widget? trailing;

  const DmSearchBar({
    super.key,
    required this.hint,
    this.value,
    this.onTap,
    this.icon = Icons.search_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final showingValue = value != null && value!.isNotEmpty;
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration:
            dmSurface(color: panel, radius: 20, border: Colors.transparent),
        child: Row(
          children: [
            Icon(icon, size: 20, color: showingValue ? red : muted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                showingValue ? value! : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: showingValue ? FontWeight.w600 : FontWeight.w500,
                  color: showingValue ? softWhite : muted,
                ),
              ),
            ),
            trailing ?? Icon(Icons.tune_rounded, size: 19, color: muted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo cards
// ---------------------------------------------------------------------------

/// Photo card with a dark scrim and a label - the "hero" style of the new UI.
class DmPhotoCard extends StatelessWidget {
  final String asset;
  final String label;
  final String? title;
  final String? body;
  final String? badge;
  final Color badgeColor;
  final double height;
  final VoidCallback? onTap;
  final Widget? footer;
  final double radius;

  const DmPhotoCard({
    super.key,
    required this.asset,
    required this.label,
    this.title,
    this.body,
    this.badge,
    this.badgeColor = red,
    this.height = 208,
    this.onTap,
    this.footer,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return RepaintBoundary(
      child: DmTapScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        // `minHeight` + a Stack (instead of a fixed height) means long copy can
        // never overflow a card: the card grows, the photo still fills it.
        child: Container(
          constraints: BoxConstraints(minHeight: height),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  // Decode at display size: keeps memory (and scroll) light.
                  cacheWidth: (MediaQuery.of(context).size.width * 2).round(),
                  errorBuilder: (_, __, ___) => Container(color: panel2),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0xE6000000)],
                      stops: [0.35, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badge != null) DmTag(label: badge!, color: badgeColor),
                    // Anchor: keeps the copy near the bottom of a short card and
                    // lets a tall card simply get taller.
                    SizedBox(height: height > 140 ? height - 140 : 18),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: red.withValues(alpha: 0.95),
                      ),
                    ),
                    if (title != null) ...[
                      const SizedBox(height: 6),
                      Text(title!,
                          style: dmHeading(size: 21)
                              .copyWith(color: Colors.white)),
                    ],
                    if (body != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: dmSubtitle(size: 12.4).copyWith(
                            color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 12),
                      footer!
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small square photo tile used in the service grid.
class DmPhotoTile extends StatelessWidget {
  final String asset;
  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final double height;

  const DmPhotoTile({
    super.key,
    required this.asset,
    required this.label,
    this.caption,
    this.onTap,
    this.height = 118,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                cacheWidth: 560,
                errorBuilder: (_, __, ___) => Container(color: panel2),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x11000000), Color(0xD9000000)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: height > 76 ? height - 76 : 12),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  if (caption != null)
                    Text(caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dmCaption(size: 10.4).copyWith(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wide photo band used at the top of detail screens.
class DmPhotoBand extends StatelessWidget {
  final String asset;
  final double height;
  final String? label;
  final String? title;
  final Widget? trailing;

  const DmPhotoBand({
    super.key,
    required this.asset,
    this.height = 168,
    this.label,
    this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return RepaintBoundary(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusCard + 2),
          border: Border.all(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              cacheWidth: (MediaQuery.of(context).size.width * 2).round(),
              errorBuilder: (_, __, ___) => Container(color: panel2),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x0D000000), Color(0xE0000000)],
                  stops: [0.3, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (label != null)
                          Text(
                            label!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                              color: red,
                            ),
                          ),
                        if (title != null) ...[
                          const SizedBox(height: 5),
                          Text(title!, style: dmHeading(size: 19).copyWith(color: Colors.white)),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// Rounded tag / chip (no interaction).
class DmTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const DmTag({super.key, required this.label, this.color = red, this.icon});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5)
          ],
          Text(
            label,
            style: TextStyle(
                fontSize: 10.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: color),
          ),
        ],
      ),
    );
  }
}

/// PIll-shaped segmented tabs, used for filters (All / Pending / Approved …).
class DmSegmentTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  const DmSegmentTabs(
      {super.key,
      required this.tabs,
      required this.index,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == index;
          return DmTapScale(
            onTap: () => onChanged(i),
            borderRadius: BorderRadius.circular(30),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? red : panel,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: selected ? red : hairline),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 12.3,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Selectable row used inside sheets (label + optional caption + check mark).
class DmOptionRow extends StatelessWidget {
  final String label;
  final String? caption;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  const DmOptionRow({
    super.key,
    required this.label,
    this.caption,
    this.icon,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? red.withValues(alpha: 0.10) : panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? red.withValues(alpha: 0.55) : hairline),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (selected ? red : muted).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: selected ? red : muted),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.4,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? softWhite
                          : softWhite.withValues(alpha: 0.92),
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 3),
                    Text(caption!, style: dmCaption(size: 11.2)),
                  ],
                ],
              ),
            ),
            trailing ??
                (selected
                    ? const Icon(Icons.check_circle_rounded,
                        size: 20, color: red)
                    : Icon(Icons.chevron_right_rounded,
                        size: 20, color: muted)),
          ],
        ),
      ),
    );
  }
}

/// Label + value row (booking summary, account details).
class DmInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const DmInfoRow(
      {super.key,
      required this.label,
      required this.value,
      this.icon,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: 9)
          ],
          Expanded(flex: 4, child: Text(label, style: dmCaption(size: 12.2))),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.8,
                fontWeight: FontWeight.w700,
                color: valueColor ?? softWhite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "How it works" step row with a connected rail.
class DmStepRow extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final IconData icon;
  final bool last;

  const DmStepRow({
    super.key,
    required this.index,
    required this.title,
    required this.body,
    required this.icon,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: red.withValues(alpha: 0.35)),
                ),
                child: Center(
                  child: Icon(icon, size: 17, color: red),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                      width: 1.5,
                      color: hairline,
                      margin: const EdgeInsets.symmetric(vertical: 4)),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STEP $index', style: dmSectionLabel()),
                  const SizedBox(height: 3),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body, style: dmCaption(size: 11.8)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circular avatar with initials (no photo needed).
class DmAvatar extends StatelessWidget {
  final String name;
  final double size;

  const DmAvatar({super.key, required this.name, this.size = 52});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [red, redDeep]),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Text(
        initials,
        style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
            color: softWhite),
      ),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'DM';
    if (parts.length == 1) {
      final single = parts.first;
      return (single.length >= 2 ? single.substring(0, 2) : single)
          .toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}

/// Copy-to-clipboard row (used for support email / phone numbers).
class DmCopyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String copiedMessage;

  const DmCopyRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.copiedMessage = 'Copied to clipboard',
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(copiedMessage),
              duration: const Duration(seconds: 1)),
        );
      },
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: dmSurface(),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: dmCaption(size: 11)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 13.4, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 17, color: muted),
          ],
        ),
      ),
    );
  }
}

/// Simple bar chart (earnings). Values are plain doubles; the chart is honest
/// about zeros - it never invents data.
class DmBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final double height;

  const DmBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = red,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final maxValue =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final ratio =
              maxValue <= 0 ? 0.02 : (values[i] / maxValue).clamp(0.02, 1.0);
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  height: (height - 26) * ratio,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color:
                        values[i] <= 0 ? panel3 : color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: values[i] <= 0
                            ? hairline
                            : color.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(height: 7),
                Text(labels[i], style: dmCaption(size: 9.8)),
              ],
            ),
          );
        }),
      ),
    );
  }
}
