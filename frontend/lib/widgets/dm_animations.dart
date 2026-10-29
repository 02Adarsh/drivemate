import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Small, cheap animation helpers used across the app.
///
/// They are deliberately lightweight: one short controller per item, nothing
/// that keeps animating in the background, so scroll and navigation stay smooth.

/// Fade + slide-up entrance. Give each item in a list a small [delay] (60–90 ms
/// steps) to get a staggered, premium feel without extra cost.
class DmEntrance extends StatefulWidget {
  final Widget child;
  final int delay; // milliseconds
  final double offset; // how far it slides up (in logical pixels)
  final Duration duration;
  final bool enabled;

  const DmEntrance({
    super.key,
    required this.child,
    this.delay = 0,
    this.offset = 14,
    this.duration = const Duration(milliseconds: 340),
    this.enabled = true,
  });

  @override
  State<DmEntrance> createState() => _DmEntranceState();
}

class _DmEntranceState extends State<DmEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    // The stagger delay is part of one controller's timeline (an Interval)
    // instead of a separate timer. That means one ticker per item, no pending
    // timers, and the animation is trivially testable with pumpAndSettle().
    final total = widget.duration.inMilliseconds + widget.delay;
    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: total));
    final start = total == 0 ? 0.0 : widget.delay / total;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    _fade = curved;
    _slide = Tween<Offset>(begin: Offset(0, widget.offset), end: Offset.zero)
        .animate(curved);

    if (!widget.enabled) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _fade.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: _slide.value, child: child),
      ),
      child: widget.child,
    );
  }
}

/// Wraps a list of children with staggered [DmEntrance] animations.
List<Widget> dmStagger(List<Widget> children, {int step = 70, int start = 0}) {
  return [
    for (var index = 0; index < children.length; index++)
      DmEntrance(delay: start + index * step, child: children[index]),
  ];
}

/// Press feedback for anything tappable (cards, chips, custom buttons).
class DmTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius? borderRadius;

  const DmTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.975,
    this.borderRadius,
  });

  @override
  State<DmTapScale> createState() => _DmTapScaleState();
}

class _DmTapScaleState extends State<DmTapScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Fades + slides content when it is swapped (used for step changes, tab bodies
/// and status cards) so nothing "pops" on screen.
class DmSlideSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const DmSlideSwitcher(
      {super.key,
      required this.child,
      this.duration = const Duration(milliseconds: 300)});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
                  .animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A soft pulsing dot, used for "live"/"in review" indicators.
class DmPulse extends StatefulWidget {
  final Color color;
  final double size;
  const DmPulse({super.key, this.color = success, this.size = 9});

  @override
  State<DmPulse> createState() => _DmPulseState();
}

class _DmPulseState extends State<DmPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                widget.color.withValues(alpha: 0.45 + _controller.value * 0.55),
          ),
        ),
      ),
    );
  }
}
