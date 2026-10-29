import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_animations.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_ui.dart';

/// ADMIN — live verification queue.
///
/// This screen is **fully functional**: it reads the real applications from
/// `GET /api/auth/admin/drivers/` and approves / rejects / suspends them through
/// `POST /api/auth/admin/drivers/<id>/review/`. It is the same workflow as the
/// Django admin panel, on the phone.
class AdminQueueScreen extends StatefulWidget {
  const AdminQueueScreen({super.key});

  @override
  State<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends State<AdminQueueScreen> {
  static final List<String> _filters = [
    'All',
    'Pending review',
    'Under review',
    'Approved',
    'Rejected',
    'Suspended'
  ];
  static final List<String> _statuses = [
    '',
    'PENDING_REVIEW',
    'UNDER_REVIEW',
    'APPROVED',
    'REJECTED',
    'SUSPENDED'
  ];

  final _search = TextEditingController();
  int _filter = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _drivers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AuthService.adminDrivers(
          status: _statuses[_filter], search: _search.text);
      final results = (data['results'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _drivers = results
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
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

  Future<void> _openDriver(Map<String, dynamic> driver) async {
    final userId = driver['user_id'] as int?;
    if (userId == null) return;
    final changed = await dmShowSheet<bool>(
      context,
      title: (driver['name'] ?? 'Driver').toString(),
      subtitle: '${driver['email'] ?? ''}',
      child: _DriverReviewSheet(userId: userId),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Verification queue',
                          style: dmHeading(size: 24))),
                  DmTapScale(
                    onTap: _load,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: dmSurface(color: panelLift, radius: 12),
                      child: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                  'Live data from the server. Approve, reject or suspend from here.',
                  style: dmSubtitle(size: 12.6)),
              const SizedBox(height: 14),
              DmSearchBar(
                hint: 'Search name or email',
                icon: Icons.search_rounded,
                trailing: _search.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _search.clear();
                          _load();
                        },
                        child:
                            Icon(Icons.close_rounded, size: 18, color: muted),
                      ),
                onTap: () => _searchSheet(),
              ),
              const SizedBox(height: 12),
              DmSegmentTabs(
                tabs: _filters,
                index: _filter,
                onChanged: (index) {
                  setState(() => _filter = index);
                  _load();
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: red,
            backgroundColor: panel,
            child: _body(),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          DmErrorState(
              title: 'Could not load the queue',
              message: _error!,
              onRetry: _load),
        ],
      );
    }
    if (_drivers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          DmEmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing in this list',
            body: _filter == 0
                ? 'No driver has submitted an application yet. Complete the driver registration on a test '
                    'account to see it here.'
                : 'No applications with the "${_filters[_filter]}" status.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      itemCount: _drivers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 11),
      itemBuilder: (context, index) => DmEntrance(
        delay: index * 40,
        child: _driverCard(_drivers[index]),
      ),
    );
  }

  void _searchSheet() {
    dmShowSheet<void>(
      context,
      title: 'Search applications',
      subtitle: 'Name or email address',
      child: Column(
        children: [
          DmField(
            controller: _search,
            hint: 'e.g. Ravi or ravi@example.com',
            icon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              Navigator.pop(context);
              _load();
            },
          ),
          const SizedBox(height: 14),
          DmPrimaryButton(
            label: 'Search',
            onPressed: () {
              Navigator.pop(context);
              _load();
            },
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _search.clear();
              Navigator.pop(context);
              _load();
            },
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  Widget _driverCard(Map<String, dynamic> driver) {
    final status = (driver['verification_status'] ?? 'INCOMPLETE').toString();
    final color = _statusColor(status);
    final progress =
        (driver['progress'] as Map?)?.cast<String, dynamic>() ?? {};
    final steps = [
      'account_complete',
      'personal_complete',
      'driving_complete',
      'documents_complete',
      'consents_complete',
      'training_complete'
    ].where((flag) => progress[flag] == true).length;

    return DmTapScale(
      onTap: () => _openDriver(driver),
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: dmSurface(border: color.withValues(alpha: 0.35)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DmAvatar(
                    name: (driver['name'] ?? 'Driver').toString(), size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (driver['name'] ?? 'Driver').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.4, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (driver['email'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dmCaption(size: 11.2),
                      ),
                    ],
                  ),
                ),
                DmPill(label: status.replaceAll('_', ' '), color: color),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                _meta(Icons.location_city_rounded,
                    (driver['city'] ?? '—').toString()),
                const SizedBox(width: 14),
                _meta(
                    Icons.folder_outlined, '${driver['documents'] ?? 0} docs'),
                const SizedBox(width: 14),
                _meta(Icons.checklist_rounded, '$steps/6 steps'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Tap to review the full application',
                      style: dmCaption(size: 11)),
                ),
                Icon(Icons.chevron_right_rounded, size: 19, color: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 5),
        Text(text, style: dmCaption(size: 11)),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return success;
      case 'REJECTED':
      case 'SUSPENDED':
        return danger;
      case 'PENDING_REVIEW':
      case 'UNDER_REVIEW':
        return warning;
      default:
        return muted;
    }
  }
}

/// Full application view + the review actions. Everything here talks to the API.
class _DriverReviewSheet extends StatefulWidget {
  final int userId;
  const _DriverReviewSheet({required this.userId});

  @override
  State<_DriverReviewSheet> createState() => _DriverReviewSheetState();
}

class _DriverReviewSheetState extends State<_DriverReviewSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;
  bool _changed = false;

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
      final data = await AuthService.adminDriverApplication(widget.userId);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _decide(String action, {String reason = ''}) async {
    setState(() => _busy = true);
    try {
      final result = await AuthService.adminReviewDriver(widget.userId, action,
          reason: reason);
      if (!mounted) return;
      _changed = true;
      showDmMessage(
          context, (result['message'] ?? 'Status updated.').toString());
      await _load();
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reasonSheet(String action) async {
    final controller = TextEditingController();
    final confirmed = await dmShowSheet<bool>(
      context,
      title: action == 'reject' ? 'Reject application' : 'Suspend driver',
      subtitle: 'The driver sees this reason in the app, so be specific.',
      child: Column(
        children: [
          DmField(
            controller: controller,
            hint: action == 'reject'
                ? 'e.g. Licence photo is blurred'
                : 'e.g. Repeated no-shows',
            icon: Icons.edit_note_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          DmPrimaryButton(
            label:
                action == 'reject' ? 'Reject and ask to fix' : 'Suspend driver',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (controller.text.trim().length < 5) {
      if (mounted) {
        showDmMessage(context, 'A reason of at least 5 characters is required.',
            error: true);
      }
      return;
    }
    await _decide(action, reason: controller.text.trim());
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          DmErrorState(
              title: 'Could not load this application',
              message: _error!,
              onRetry: _load),
        ],
      );
    }

    final data = _data ?? {};
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final progress = (data['progress'] as Map?)?.cast<String, dynamic>() ?? {};
    final documents =
        ((data['documents'] as List?) ?? []).whereType<Map>().toList();
    final profile = (data['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = (progress['verification_status'] ?? 'INCOMPLETE').toString();
    final approved = status == 'APPROVED';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child:
                    Text('${user['name'] ?? ''}', style: dmHeading(size: 17))),
            DmPill(
                label: status.replaceAll('_', ' '),
                color: approved ? success : warning),
          ],
        ),
        const SizedBox(height: 4),
        Text('${user['email'] ?? ''}  •  ${user['phone'] ?? ''}',
            style: dmCaption(size: 11.4)),
        const SizedBox(height: 16),
        const DmSectionLabel('Profile'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: dmSurface(),
          child: Column(
            children: [
              DmInfoRow(
                  label: 'City',
                  value:
                      '${profile['city'] ?? '—'}, ${profile['state'] ?? ''}'),
              Divider(color: dividerSoft, height: 16),
              DmInfoRow(
                  label: 'PIN', value: (profile['pincode'] ?? '—').toString()),
              Divider(color: dividerSoft, height: 16),
              DmInfoRow(
                  label: 'Licence',
                  value: (profile['licence_number'] ?? '—').toString()),
              Divider(color: dividerSoft, height: 16),
              DmInfoRow(
                  label: 'Experience',
                  value: '${profile['experience_years'] ?? 0} years'),
              Divider(color: dividerSoft, height: 16),
              DmInfoRow(
                  label: 'Languages',
                  value: ((profile['languages'] as List?) ?? []).join(', ')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const DmSectionLabel('Steps complete'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in [
              ['account_complete', 'Account'],
              ['personal_complete', 'Personal'],
              ['driving_complete', 'Driving'],
              ['documents_complete', 'Documents'],
              ['consents_complete', 'Consent'],
              ['training_complete', 'Training'],
            ])
              DmPill(
                label: entry[1],
                color: progress[entry[0]] == true ? success : muted,
                icon: progress[entry[0]] == true
                    ? Icons.check_rounded
                    : Icons.remove_rounded,
              ),
          ],
        ),
        const SizedBox(height: 16),
        const DmSectionLabel('Documents'),
        if (documents.isEmpty)
          Text('No documents uploaded yet.', style: dmCaption(size: 11.6))
        else
          for (final document in documents)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: dmSurface(),
              child: Row(
                children: [
                  Icon(
                    document['review_status'] == 'APPROVED'
                        ? Icons.verified_rounded
                        : Icons.description_outlined,
                    size: 18,
                    color: document['review_status'] == 'APPROVED'
                        ? success
                        : muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            (document['document_label'] ??
                                    document['document_type'] ??
                                    '')
                                .toString(),
                            style: const TextStyle(
                                fontSize: 12.8, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${document['review_status'] ?? ''} • ${document['document_number'] ?? 'no number'}',
                          style: dmCaption(size: 10.8),
                        ),
                      ],
                    ),
                  ),
                  if (document['id'] is int)
                    TextButton(
                      onPressed: () async {
                        // Capture the messenger before the await so the context
                        // is never used across an async gap.
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await AuthService.adminReviewDocument(
                              document['id'] as int, 'approve');
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(
                                content: Text('Document approved.'),
                                duration: Duration(seconds: 1)),
                          );
                          await _load();
                        } on ApiException catch (error) {
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text(error.message),
                                duration: const Duration(seconds: 2)),
                          );
                        }
                      },
                      child: const Text('Approve',
                          style: TextStyle(fontSize: 11.6)),
                    ),
                ],
              ),
            ),
        const SizedBox(height: 18),
        const DmSectionLabel('Decision'),
        if (_busy)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator()))
        else ...[
          if (!approved)
            DmPrimaryButton(
              label: 'Approve driver',
              onPressed: () => _decide('approve'),
            ),
          if (approved)
            DmPrimaryButton(
              label: 'Move back to under review',
              onPressed: () => _decide('under_review'),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _reasonSheet('reject'),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: danger.withValues(alpha: 0.6))),
                    child: const Text('Reject',
                        style: TextStyle(
                            fontSize: 12.8,
                            fontWeight: FontWeight.w700,
                            color: danger)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _reasonSheet('suspend'),
                    child: const Text('Suspend',
                        style: TextStyle(
                            fontSize: 12.8, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const DmInfoBox(
            text:
                'Approve is only allowed when all six steps are complete - the server enforces this. '
                'Reject and suspend always require a reason; the driver sees it in their app.',
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context, _changed),
            child: Text(_changed ? 'Close (queue refreshed)' : 'Close',
                style: dmCaption(size: 11.8)),
          ),
        ),
      ],
    );
  }
}
