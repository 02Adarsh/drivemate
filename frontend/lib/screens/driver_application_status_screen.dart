import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/step_progress.dart';
import 'driver_documents_screen.dart';
import 'driver_driving_details_screen.dart';
import 'driver_personal_profile_screen.dart';
import 'home_screen.dart';

/// DRIVER REGISTRATION - STEP 5 of 5: admin verification status.
///
/// Everything on this screen comes from the server (`/api/auth/driver/application/`),
/// including the tracker states and the reason for a rejection, so the app can
/// never claim a step is complete when the backend disagrees.
class DriverApplicationStatusScreen extends StatefulWidget {
  final String name;
  const DriverApplicationStatusScreen({super.key, required this.name});

  @override
  State<DriverApplicationStatusScreen> createState() =>
      _DriverApplicationStatusScreenState();
}

class _DriverApplicationStatusScreenState
    extends State<DriverApplicationStatusScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

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
      final data = await AuthService.driverApplication();
      if (!mounted) return;
      setState(() => _data = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _progress =>
      (_data?['progress'] as Map?)?.cast<String, dynamic>() ?? {};
  String get _status =>
      (_progress['verification_status'] ?? 'INCOMPLETE').toString();
  String get _nextStep =>
      (_progress['next_step'] ?? 'PERSONAL_PROFILE').toString();

  ({Color color, IconData icon, String title, String message}) get _hero {
    switch (_status) {
      case 'APPROVED':
        return (
          color: success,
          icon: Icons.verified_rounded,
          title: 'You are approved',
          message:
              'Your application passed verification. Going online and receiving booking requests arrives in the next build.',
        );
      case 'UNDER_REVIEW':
        return (
          color: info,
          icon: Icons.manage_search_rounded,
          title: 'Under review',
          message: 'A verification agent is checking your documents right now.',
        );
      case 'PENDING_REVIEW':
        return (
          color: warning,
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for review',
          message:
              'Your application is complete and queued for admin verification.',
        );
      case 'REJECTED':
        return (
          color: danger,
          icon: Icons.report_gmailerrorred_rounded,
          title: 'Action needed',
          message:
              'Your application needs a correction. Read the reason below, fix it and resubmit.',
        );
      case 'SUSPENDED':
        return (
          color: danger,
          icon: Icons.block_rounded,
          title: 'Account suspended',
          message: 'Your driver access is paused. Contact support for details.',
        );
      default:
        return (
          color: warning,
          icon: Icons.assignment_outlined,
          title: 'Application not submitted',
          message: 'Finish the remaining steps to enter admin verification.',
        );
    }
  }

  void _continueApplication() {
    switch (_nextStep) {
      case 'PERSONAL_PROFILE':
        Navigator.of(context).pushReplacement(
            dmRoute(DriverPersonalProfileScreen(name: widget.name)));
        break;
      case 'DRIVING_DETAILS':
        Navigator.of(context).pushReplacement(
            dmRoute(DriverDrivingDetailsScreen(name: widget.name)));
        break;
      default:
        Navigator.of(context)
            .pushReplacement(dmRoute(DriverDocumentsScreen(name: widget.name)));
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final hero = _hero;

    return DmScreen(
      showBack: true,
      // After approval (or when the stack was cleared) the dashboard is the
      // right place to land, so the arrow never leads to a dead end.
      onBack: () =>
          pushClean(context, HomeScreen(role: 'Driver', name: widget.name)),
      child: RefreshIndicator(
        onRefresh: _load,
        color: red,
        backgroundColor: panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StepHeader(
              step: 5,
              title: 'Verification status',
              subtitle: 'Track every step of your driver application.',
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              DmErrorState(
                title: 'Could not load your status',
                message: _error!,
                onRetry: _load,
                icon: Icons.cloud_off_rounded,
              )
            else ...[
              // ---------------------------------------------------- status hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [hero.color.withValues(alpha: 0.20), panel],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: hero.color.withValues(alpha: 0.40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: hero.color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(hero.icon, color: hero.color, size: 23),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hero.title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                (_progress['verification_status_label'] ?? '')
                                    .toString(),
                                style: dmCaption(size: 11.5),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                            label: _status.replaceAll('_', ' '),
                            color: hero.color,
                            icon: hero.icon),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(hero.message, style: dmSubtitle(size: 12.8)),
                    if ((_progress['rejection_reason'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DmInfoBox(
                        icon: Icons.info_outline_rounded,
                        color: danger,
                        text: 'Reason given: ${_progress['rejection_reason']}',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // ------------------------------------------------------- tracker
              const DmSectionLabel('Application progress'),
              ...((_data?['steps'] as List?) ?? []).map((step) {
                final map = (step as Map).cast<String, dynamic>();
                return TrackerTile(
                  title: (map['title'] ?? '').toString(),
                  detail: (map['detail'] ?? '').toString(),
                  state: (map['state'] ?? 'PENDING').toString(),
                  icon: _stepIcon((map['key'] ?? '').toString()),
                );
              }),
              const SizedBox(height: 12),
              // ----------------------------------------------------- documents
              const DmSectionLabel('Your documents'),
              ...((_data?['documents'] as List?) ?? []).map((document) {
                final map = (document as Map).cast<String, dynamic>();
                final review = (map['review_status'] ?? 'PENDING').toString();
                final color = review == 'APPROVED'
                    ? success
                    : review == 'REJECTED'
                        ? danger
                        : info;
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 18, color: muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (map['document_label'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 12.6, fontWeight: FontWeight.w600),
                        ),
                      ),
                      StatusPill(
                          label: review,
                          color: color,
                          icon: Icons.fact_check_outlined),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 18),
              // ------------------------------------------------------ training
              const DmSectionLabel('Training'),
              ...((_data?['training'] as List?) ?? []).take(6).map((module) {
                final map = (module as Map).cast<String, dynamic>();
                final done = map['status'] == 'COMPLETED';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: done ? success : muted,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          (map['label'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 12.4, color: done ? softWhite : muted),
                        ),
                      ),
                      if (map['is_required'] == true)
                        Text('required', style: dmCaption(size: 10.5)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 22),
              // ------------------------------------------------------- actions
              if (_status == 'APPROVED')
                DmPrimaryButton(
                  label: 'Go to driver dashboard',
                  icon: Icons.dashboard_outlined,
                  onPressed: () => pushClean(
                      context, HomeScreen(role: 'Driver', name: widget.name)),
                )
              else if (_nextStep == 'UNDER_REVIEW' || _nextStep == 'SUSPENDED')
                DmPrimaryButton(
                  label: 'Refresh status',
                  icon: Icons.refresh_rounded,
                  loading: _loading,
                  onPressed: _load,
                )
              else
                DmPrimaryButton(
                  label: _status == 'REJECTED'
                      ? 'Fix and resubmit'
                      : 'Continue application',
                  onPressed: _continueApplication,
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check verification status'),
                ),
              ),
              const SizedBox(height: 18),
              const DmInfoBox(
                icon: Icons.support_agent_rounded,
                text:
                    'Need help with verification? Open Help & support from your account to send a request.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _stepIcon(String key) {
    switch (key) {
      case 'ACCOUNT':
        return Icons.person_add_alt_1_outlined;
      case 'PERSONAL_PROFILE':
        return Icons.badge_outlined;
      case 'DRIVING_DETAILS':
        return Icons.directions_car_outlined;
      case 'DOCUMENTS':
        return Icons.folder_shared_outlined;
      default:
        return Icons.verified_user_outlined;
    }
  }
}
