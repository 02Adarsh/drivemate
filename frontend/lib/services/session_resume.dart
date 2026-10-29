import 'auth_service.dart';

/// Re-read registration progress from the server when an existing session
/// resumes. Cached user data is not proof that a profile is complete.
Future<Map<String, dynamic>> loadResumeState() async {
  final response = await AuthService.me();
  final rawUser = response['user'];
  if (rawUser is! Map) {
    throw ApiException('Could not check your account. Please try again.');
  }
  final user = rawUser.cast<String, dynamic>();
  final role = user['role'];
  if (role == 'CUSTOMER') {
    final data = await AuthService.getProfile();
    final profile = data['profile'];
    if (data['role'] != 'CUSTOMER' ||
        profile is! Map ||
        profile['profile_complete'] is! bool) {
      throw ApiException('Could not check your profile. Please try again.');
    }
    return {
      'user': {
        ...user,
        'next_step':
            profile['profile_complete'] == true ? 'DASHBOARD' : 'PROFILE',
      },
    };
  }
  if (role == 'DRIVER') {
    final progress = response['driver'];
    const validSteps = {
      'PERSONAL_PROFILE',
      'DRIVING_DETAILS',
      'DOCUMENTS',
      'UNDER_REVIEW',
      'FIX_AND_RESUBMIT',
      'SUSPENDED',
      'DASHBOARD',
    };
    if (progress is! Map || !validSteps.contains(progress['next_step'])) {
      throw ApiException('Could not check your application. Please try again.');
    }
    return {'user': user, 'driver': progress.cast<String, dynamic>()};
  }
  if (role == 'ADMIN') {
    return {
      'user': {...user, 'next_step': 'ADMIN_DASHBOARD'}
    };
  }
  throw ApiException('Could not check your account. Please sign in again.');
}
