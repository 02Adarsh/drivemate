import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/dm_theme.dart';

/// "SLIDE TO GET STARTED" control.
///
/// Rebuilt from the earlier version, which could be swallowed by the
/// surrounding PageView's horizontal-drag gesture. Two fixes:
///   1. The drag is tracked with `details.delta.dx` (accumulated), so it does
///      not depend on where inside the track the finger landed.
///   2. The onboarding screen freezes the PageView on the last page, so no
///      parent gesture competes with this one.
///
/// A tap on the bar also completes it, so nobody can get stuck.
class SlideToStart extends StatefulWidget {
  final String label;
  final VoidCallback onCompleted;
  final bool enabled;

  const SlideToStart({
    super.key,
    required this.onCompleted,
    this.label = 'SLIDE TO GET STARTED',
    this.enabled = true,
  });

  @override
  State<SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<SlideToStart> {
  static const double _thumb = 52;
  static const double _pad = 5;

  double _x = 0;
  double _maxX = 0;
  bool _completed = false;

  void _complete() {
    if (_completed) return;
    _completed = true;
    HapticFeedback.mediumImpact();
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxX = (constraints.maxWidth - _thumb - _pad * 2)
            .clamp(0, double.infinity);
        final progress = _maxX == 0 ? 0.0 : (_x / _maxX).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _complete : null,
          onHorizontalDragStart: (_) {
            if (!widget.enabled) return;
            setState(() => _x = _x.clamp(0, _maxX));
          },
          onHorizontalDragUpdate: (details) {
            if (!widget.enabled || _completed) return;
            setState(() => _x = (_x + details.delta.dx).clamp(0, _maxX));
            if (_maxX > 0 && _x >= _maxX * 0.92) _complete();
          },
          onHorizontalDragEnd: (_) {
            if (_completed) return;
            setState(() => _x = 0); // spring back if not completed
          },
          onHorizontalDragCancel: () {
            if (!_completed) setState(() => _x = 0);
          },
          child: Container(
            height: _thumb + _pad * 2,
            decoration: BoxDecoration(
              color: panel3,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: hairline),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Progress fill that follows the thumb.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  height: _thumb + _pad * 2,
                  width: _x + _thumb + _pad,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(40),
                    gradient: LinearGradient(
                      colors: [
                        red.withValues(alpha: 0.30),
                        red.withValues(alpha: 0.10)
                      ],
                    ),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: progress > 0.35 ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: softWhite.withValues(alpha: 0.62),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.keyboard_double_arrow_right_rounded,
                            size: 16, color: softWhite.withValues(alpha: 0.45)),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 60),
                  curve: Curves.easeOut,
                  left: _pad + _x,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [red, redDeep],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: red.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: const Icon(Icons.double_arrow_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
