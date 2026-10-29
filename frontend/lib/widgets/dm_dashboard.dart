import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import 'brand_mark.dart';
import 'dm_animations.dart';

/// Clean, reusable building blocks for the dashboards.
///
/// Everything here is deliberately cheap to paint: flat colours, one small
/// gradient per card, no blurs and no per-frame shadows, so scrolling stays at
/// 60/120 fps on a mid-range phone.

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Top bar of a dashboard: brand mark, greeting, notification and log-out.
class DmGreetingHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final String roleLabel;
  final VoidCallback? onBell;
  final VoidCallback? onLogout;
  final bool bellBadge;

  const DmGreetingHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.roleLabel,
    this.onBell,
    this.onLogout,
    this.bellBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BrandMark(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${name.split(' ').first}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dmHeading(size: 19),
                  ),
                  const SizedBox(height: 2),
                  Text(roleLabel,
                      style: dmCaption(size: 10.8)
                          .copyWith(letterSpacing: 1.1, color: red)),
                ],
              ),
            ),
            _HeaderButton(
              icon: Icons.notifications_none_rounded,
              onTap: onBell,
              showDot: bellBadge,
              tooltip: 'Notifications',
            ),
            const SizedBox(width: 4),
            _HeaderButton(
              icon: Icons.logout_rounded,
              onTap: onLogout,
              tooltip: 'Log out',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(subtitle, style: dmSubtitle(size: 13)),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool showDot;
  final String tooltip;

  const _HeaderButton(
      {required this.icon,
      required this.tooltip,
      this.onTap,
      this.showDot = false});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: panel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 19, color: softWhite),
            if (showDot)
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: red,
                      shape: BoxShape.circle,
                      border: Border.all(color: panel2, width: 1.4)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pills & labels
// ---------------------------------------------------------------------------

/// Small rounded status/label chip.
class DmPill extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool solid;

  const DmPill(
      {super.key,
      required this.label,
      this.color,
      this.icon,
      this.solid = false});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final color = this.color ?? muted;
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: solid ? 0 : 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
              child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.3,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: fg),
          )),
        ],
      ),
    );
  }
}

/// Section title with an optional trailing action ("See all", count, …).
class DmSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const DmSectionHeader(
      {super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: red),
            ),
          ),
          if (action != null)
            DmTapScale(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Text(action!,
                        style: dmCaption(size: 11).copyWith(color: muted)),
                    Icon(Icons.chevron_right_rounded, size: 15, color: muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

/// Large gradient card used as the focal point of a dashboard.
class DmHeroCard extends StatelessWidget {
  final String label;
  final String title;
  final String body;
  final Color accent;
  final Widget? leading;
  final List<Widget> footer;
  final List<Color>? gradient;

  const DmHeroCard({
    super.key,
    required this.label,
    required this.title,
    required this.body,
    required this.accent,
    this.leading,
    this.footer = const [],
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient ?? [accent.withValues(alpha: 0.22), panel],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10.3,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                            color: accent),
                      ),
                      const SizedBox(height: 7),
                      Text(title, style: dmHeading(size: 21)),
                      const SizedBox(height: 7),
                      Text(body, style: dmSubtitle(size: 12.6)),
                    ],
                  ),
                ),
              ],
            ),
            if (footer.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...footer,
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular progress ring (profile completion / verification).
class DmStatusRing extends StatelessWidget {
  final double value; // 0.0 – 1.0
  final Color color;
  final String label;
  final String? caption;
  final double size;

  const DmStatusRing({
    super.key,
    required this.value,
    required this.color,
    this.label = '',
    this.caption,
    this.size = 84,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => CustomPaint(
          painter: _RingPainter(animated, color),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: size * 0.23,
                      fontWeight: FontWeight.w800,
                      color: softWhite,
                      height: 1.0),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: muted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;

  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = hairline,
    );

    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

// ---------------------------------------------------------------------------
// Online / offline
// ---------------------------------------------------------------------------

/// Availability switch for a driver. Locked (and visibly explained) until the
/// account is approved - approval and availability are different states.
class DmOnlineToggle extends StatelessWidget {
  final bool online;
  final bool locked;
  final ValueChanged<bool>? onChanged;
  final String lockedNote;
  final String onlineNote;
  final String offlineNote;

  const DmOnlineToggle({
    super.key,
    required this.online,
    this.locked = false,
    this.onChanged,
    this.lockedNote = 'Only an approved driver can go online.',
    this.onlineNote = 'You can receive eligible booking requests.',
    this.offlineNote = 'You will not receive booking requests.',
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final active = online && !locked;
    final accent = active ? success : muted;

    return DmTapScale(
      onTap: locked ? null : () => onChanged?.call(!online),
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active ? [const Color(0xFF10241C), panel] : [panel, panel2],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: active ? success.withValues(alpha: 0.42) : hairline),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: success.withValues(alpha: 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: active ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.power_settings_new_rounded,
                size: 21,
                color: accent,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (active) ...[
                        const DmPulse(color: success),
                        const SizedBox(width: 7)
                      ],
                      Flexible(
                          child: Text(
                        locked
                            ? 'Locked'
                            : (online ? 'You are online' : 'You are offline'),
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    locked ? lockedNote : (online ? onlineNote : offlineNote),
                    style: dmCaption(size: 11.4),
                  ),
                ],
              ),
            ),
            Switch(
              value: active,
              onChanged: locked ? null : (v) => onChanged?.call(v),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats & actions
// ---------------------------------------------------------------------------

/// Compact metric tile.
class DmStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const DmStatTile({
    super.key,
    required this.label,
    required this.value,
    this.note = '',
    required this.icon,
    this.accent = red,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(height: 11),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.0))),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dmCaption(size: 10.8)),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: dmCaption(size: 9.8)
                    .copyWith(color: muted.withValues(alpha: 0.65)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square icon tile used in quick-action grids.
class DmActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final Color accent;
  final String? badge;

  const DmActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.caption,
    this.onTap,
    this.accent = red,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const Spacer(),
                if (badge != null)
                  DmPill(label: badge!, color: warning, solid: true),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (caption != null) ...[
              const SizedBox(height: 3),
              Text(caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: dmCaption(size: 10.6)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-width list row: icon, title, body, chevron.
class DmListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final VoidCallback? onTap;
  final Widget? trailing;

  const DmListCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.accent = red,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.6, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(body, style: dmCaption(size: 11.6)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(Icons.chevron_right_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Empty state card: "nothing here yet" with an honest explanation.
class DmEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DmEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: panel3,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: red.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, size: 24, color: red),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: dmCaption(size: 11.6)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: red.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Earnings summary for the driver dashboard.
///
/// The numbers are zero until the booking phase goes live, and the card says so
/// instead of pretending to have data.
class DmEarningsCard extends StatelessWidget {
  final String today;
  final String week;
  final String month;
  final String note;

  const DmEarningsCard({
    super.key,
    this.today = '₹0',
    this.week = '₹0',
    this.month = '₹0',
    this.note =
        'Your completed trips and calculated earnings will appear here.',
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFF1A1114), panel]),
        borderRadius: BorderRadius.circular(radiusCard + 2),
        border: Border.all(color: red.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 17, color: red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Earnings',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              DmPill(label: 'SOON', color: warning),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _Money(label: 'Today', value: today)),
              _vDivider(),
              Expanded(child: _Money(label: 'This week', value: week)),
              _vDivider(),
              Expanded(child: _Money(label: 'This month', value: month)),
            ],
          ),
          const SizedBox(height: 14),
          Text(note, style: dmCaption(size: 10.9)),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 34, color: hairline);
}

class _Money extends StatelessWidget {
  final String label;
  final String value;

  const _Money({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, style: dmCaption(size: 10.4)),
      ],
    );
  }
}
