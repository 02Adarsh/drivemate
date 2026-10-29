import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Header used by every driver registration step:
///
///   DRIVER APPLICATION            STEP 2 OF 5
///   Personal profile
///   Photo, date of birth, address and emergency contact.
///   ● ● ▬ ▬ ▬      (done / current / pending)
class StepHeader extends StatelessWidget {
  final int step; // 1-based
  final int total;
  final String title;
  final String subtitle;
  final String eyebrow;

  const StepHeader({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    this.total = 5,
    this.eyebrow = 'Driver application',
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(eyebrow.toUpperCase(), style: dmSectionLabel())),
            Text(
              'STEP $step OF $total',
              style: dmCaption(size: 10.5)
                  .copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(title, style: dmHeading(size: 26)),
        const SizedBox(height: 6),
        Text(subtitle, style: dmSubtitle(size: 13)),
        const SizedBox(height: 16),
        Row(
          children: List.generate(total, (index) {
            final number = index + 1;
            final isDone = number < step;
            final isCurrent = number == step;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: number == total ? 0 : 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDone
                        ? red.withValues(alpha: 0.55)
                        : isCurrent
                            ? red
                            : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// One row of the application tracker ("Account created", "Admin approval", ...).
class TrackerTile extends StatelessWidget {
  final String title;
  final String detail;
  final String
      state; // DONE | IN_PROGRESS | ACTION_REQUIRED | REJECTED | PENDING
  final IconData icon;

  const TrackerTile({
    super.key,
    required this.title,
    required this.detail,
    required this.state,
    required this.icon,
  });

  ({Color color, IconData icon, String label}) get _visuals {
    switch (state) {
      case 'DONE':
        return (color: success, icon: Icons.check_rounded, label: 'Done');
      case 'IN_PROGRESS':
        return (
          color: info,
          icon: Icons.hourglass_top_rounded,
          label: 'In review'
        );
      case 'ACTION_REQUIRED':
        return (
          color: warning,
          icon: Icons.priority_high_rounded,
          label: 'Action needed'
        );
      case 'REJECTED':
        return (color: danger, icon: Icons.close_rounded, label: 'Rejected');
      default:
        return (color: muted, icon: Icons.schedule_rounded, label: 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final visual = _visuals;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: visual.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    _StatePill(
                        color: visual.color,
                        icon: visual.icon,
                        label: visual.label),
                  ],
                ),
                const SizedBox(height: 5),
                Text(detail, style: dmCaption(size: 11.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  const _StatePill(
      {required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// Standalone status pill (verification status on the driver dashboard).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const StatusPill(
      {super.key,
      required this.label,
      required this.color,
      this.icon = Icons.verified_outlined});

  @override
  Widget build(BuildContext context) =>
      _StatePill(color: color, icon: icon, label: label.toUpperCase());
}
