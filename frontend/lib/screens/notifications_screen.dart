import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/rides_service.dart';
import '../services/navigation.dart';
import 'booking_detail_screen.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_screen.dart';

/// NOTIFICATIONS — real events from the booking engine.
///
/// Every row is written by the server when something actually happens
/// (request sent, driver accepted, trip started, trip completed, payout added).
class NotificationsScreen extends StatefulWidget {
  final String role;
  const NotificationsScreen({super.key, this.role = 'Customer'});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotificationModel> _items = const [];
  int _unread = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await RidesService.notifications();
      if (!mounted) return;
      setState(() {
        _items = ((data['results'] as List?) ?? [])
            .whereType<Map>()
            .map((item) =>
                AppNotificationModel.fromJson(item.cast<String, dynamic>()))
            .toList();
        _unread = (data['unread'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _markAll() async {
    try {
      await RidesService.markAllRead();
      await _load();
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DmEntrance(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('INBOX',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: red)),
                      const SizedBox(height: 8),
                      Text('Notifications', style: dmHeading(size: 25)),
                      const SizedBox(height: 6),
                      Text(
                        _unread == 0
                            ? 'Everything is read.'
                            : '$_unread unread',
                        style: dmSubtitle(size: 12.8),
                      ),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh notifications'),
                if (_unread > 0)
                  DmTapScale(
                    onTap: _markAll,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: red.withValues(alpha: 0.35)),
                      ),
                      child: const Text('Mark all read',
                          style: TextStyle(
                              fontSize: 11.4,
                              fontWeight: FontWeight.w700,
                              color: red)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            DmErrorState(
                title: 'Could not load notifications',
                message: _error!,
                onRetry: _load)
          else if (_items.isEmpty)
            const DmEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Nothing yet',
              body:
                  'Booking updates land here: when a driver accepts, when your trip starts and when it is '
                  'completed.',
            )
          else
            ...dmStagger([
              for (final item in _items) ...[
                _NotificationCard(
                  notification: item,
                  onTap: () async {
                    try {
                      if (!item.isRead) await RidesService.markRead(item.id);
                      if (!mounted) return;
                      if (item.bookingId != null) {
                        await Navigator.of(this.context)
                            .push(dmRoute(BookingDetailScreen(
                          bookingId: item.bookingId!,
                          isDriver: widget.role == 'Driver',
                        )));
                      }
                      if (mounted) await _load();
                    } on ApiException catch (error) {
                      if (mounted) {
                        showDmMessage(this.context, error.message, error: true);
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],
            ]),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final unread = !notification.isRead;
    return DmTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: dmSurface(
            border:
                unread ? notification.color.withValues(alpha: 0.35) : hairline),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: notification.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child:
                  Icon(notification.icon, size: 19, color: notification.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 13.6,
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: notification.color,
                              shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(notification.body, style: dmCaption(size: 11.4)),
                  ],
                  if (notification.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(_relativeTime(notification.createdAt!),
                        style: dmCaption(size: 10.2)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    if (difference.inDays < 7) return '${difference.inDays} d ago';
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
