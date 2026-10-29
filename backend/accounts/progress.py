"""Driver application progress + verification status engine.

This module is the single source of truth for:
  * what counts as "complete" for each registration step,
  * which step the driver must do next,
  * when an application becomes PENDING_REVIEW, and
  * how admin approve / reject / suspend decisions are recorded.

The REST API and the Django admin both call these helpers, so the mobile app can
never mark a step complete on its own.

Terminology note: being APPROVED and being ONLINE are two different things.
Approval only means the application passed review. Going online (and receiving
booking requests) is a later phase and needs a separate availability check.
"""

import re
from datetime import date

from django.conf import settings
from django.utils import timezone

from .models import DriverProfile, DriverTraining

# ---------------------------------------------------------------------------
# Rules (edit these in one place when the operating policy changes)
# ---------------------------------------------------------------------------

MIN_DRIVER_AGE = 18

# PIN code rule. India: 6 digits, cannot start with 0. Adjust this single
# function when the service opens in another country.
PINCODE_PATTERN = re.compile(r'^[1-9][0-9]{5}$')


def is_valid_pincode(value: str) -> bool:
    return bool(PINCODE_PATTERN.match((value or '').strip()))

# Overridable from settings (environment variables) so the operating policy can
# change per service area without touching code.
REQUIRED_DOCUMENTS = tuple(getattr(settings, 'DRIVER_REQUIRED_DOCUMENTS', ('LICENCE_FRONT', 'LICENCE_BACK', 'IDENTITY')))
OPTIONAL_DOCUMENTS = tuple(getattr(settings, 'DRIVER_OPTIONAL_DOCUMENTS', ('ADDRESS_PROOF',)))

# Modules a driver must finish before the application can be submitted.
# The remaining DriverTraining.Module values are optional extras.
REQUIRED_TRAINING = tuple(
    getattr(settings, 'DRIVER_REQUIRED_TRAINING', ('SAFE_DRIVING', 'CUSTOMER_SERVICE', 'VEHICLE_INSPECTION'))
)

TRAINING_CONTENT = {
    'SAFE_DRIVING': [
        'Follow traffic rules and posted speed limits at all times.',
        'Keep a safe following distance and avoid sudden braking.',
        'Never drive under the influence of alcohol or drugs.',
        'Stop and report any accident, however minor.',
    ],
    'CUSTOMER_SERVICE': [
        'Greet the customer politely and confirm the trip plan before starting.',
        'Do not smoke, eat or take personal calls while driving the customer\'s car.',
        'Discuss route changes and extra stops with the customer first.',
        'Respect the customer\'s privacy and do not share trip details.',
    ],
    'VEHICLE_INSPECTION': [
        'Photograph the vehicle from all required angles before and after the trip.',
        'Record fuel level and odometer reading at handover.',
        'Point out and photograph existing damage before driving.',
        'Confirm with the customer that the inspection is complete.',
    ],
    'AUTOMATIC_TRANSMISSION': ['Understand P/R/N/D positions and parking brake use.'],
    'MANUAL_TRANSMISSION': ['Smooth clutch control and gear changes, especially on slopes.'],
    'HIGHWAY_DRIVING': ['Lane discipline, safe overtaking and merging.'],
    'NIGHT_DRIVING': ['Headlight use, glare handling and reduced-speed judgement.'],
    'EMERGENCY_PROCEDURES': ['What to do at an accident scene and how to call for help.'],
    'APP_USAGE': ['Go online, accept requests, verify the trip PIN and end the trip correctly.'],
}


# ---------------------------------------------------------------------------
# Step completion checks
# ---------------------------------------------------------------------------

def calculate_age(date_of_birth: date | None) -> int | None:
    if not date_of_birth:
        return None
    today = date.today()
    years = today.year - date_of_birth.year
    if (today.month, today.day) < (date_of_birth.month, date_of_birth.day):
        years -= 1
    return years


def personal_profile_complete(profile: DriverProfile) -> bool:
    """Step 2: photo, DOB (age eligible), address, state, city, PIN code,
    emergency contact and languages."""
    age = calculate_age(profile.date_of_birth)
    return bool(
        profile.user.profile_photo_key
        and age is not None
        and age >= MIN_DRIVER_AGE
        and profile.address.strip()
        and profile.state.strip()
        and profile.city.strip()
        and is_valid_pincode(profile.pincode)
        and profile.emergency_contact_name.strip()
        and profile.emergency_contact_phone.strip()
        and profile.languages.strip()
    )


def driving_details_complete(profile: DriverProfile) -> bool:
    """Step 3: licence details, experience and at least one capability per group."""
    has_transmission = profile.manual_transmission or profile.automatic_transmission
    has_vehicle_class = profile.sedan or profile.suv or profile.luxury
    licence_valid = bool(profile.licence_number.strip()) and bool(
        profile.licence_expiry and profile.licence_expiry > date.today()
    )
    return bool(licence_valid and has_transmission and has_vehicle_class and profile.experience_years > 0)


def documents_complete(profile: DriverProfile) -> bool:
    """Step 4a: every required document uploaded at least once."""
    uploaded = set(profile.documents.values_list('document_type', flat=True))
    return set(REQUIRED_DOCUMENTS).issubset(uploaded)


def consents_complete(profile: DriverProfile) -> bool:
    """Step 4b: background check consent, terms and data-accuracy declaration."""
    return bool(profile.consent_background_check and profile.consent_terms and profile.consent_data_accuracy)


def missing_required_training(profile: DriverProfile) -> list[str]:
    done = set(
        profile.training.filter(status=DriverTraining.Status.COMPLETED).values_list('module', flat=True)
    )
    return [module for module in REQUIRED_TRAINING if module not in done]


def training_complete(profile: DriverProfile) -> bool:
    return not missing_required_training(profile)


def ready_for_review(profile: DriverProfile) -> bool:
    return bool(
        personal_profile_complete(profile)
        and driving_details_complete(profile)
        and documents_complete(profile)
        and consents_complete(profile)
        and training_complete(profile)
    )


# ---------------------------------------------------------------------------
# Progress payload used by the API and the app
# ---------------------------------------------------------------------------

NEXT_STEP_ROUTES = {
    'PERSONAL_PROFILE': 'PERSONAL_PROFILE',
    'DRIVING_DETAILS': 'DRIVING_DETAILS',
    'DOCUMENTS': 'DOCUMENTS',
    'UNDER_REVIEW': 'UNDER_REVIEW',
    'FIX_AND_RESUBMIT': 'FIX_AND_RESUBMIT',
    'SUSPENDED': 'SUSPENDED',
    'DASHBOARD': 'DASHBOARD',
}


def next_step(profile: DriverProfile) -> str:
    status = profile.verification_status
    if status == DriverProfile.Status.APPROVED:
        return 'DASHBOARD'
    if status == DriverProfile.Status.SUSPENDED:
        return 'SUSPENDED'
    if status == DriverProfile.Status.REJECTED:
        return 'FIX_AND_RESUBMIT'
    if status in (DriverProfile.Status.PENDING_REVIEW, DriverProfile.Status.UNDER_REVIEW):
        return 'UNDER_REVIEW'
    if not personal_profile_complete(profile):
        return 'PERSONAL_PROFILE'
    if not driving_details_complete(profile):
        return 'DRIVING_DETAILS'
    return 'DOCUMENTS'


def driver_progress(profile: DriverProfile) -> dict:
    return {
        'account_complete': bool(profile.user.email_verified),
        'personal_complete': personal_profile_complete(profile),
        'driving_complete': driving_details_complete(profile),
        'documents_complete': documents_complete(profile),
        'consents_complete': consents_complete(profile),
        'training_complete': training_complete(profile),
        'missing_training': missing_required_training(profile),
        'profile_complete': bool(profile.profile_complete),
        'ready_for_review': ready_for_review(profile),
        'verification_status': profile.verification_status,
        'verification_status_label': profile.get_verification_status_display(),
        'is_approved': profile.is_approved,
        'rejection_reason': profile.rejection_reason,
        'submitted_at': profile.submitted_at,
        'reviewed_at': profile.reviewed_at,
        'approved_at': profile.approved_at,
        'next_step': next_step(profile),
    }


def application_steps(profile: DriverProfile) -> list[dict]:
    """The five-step tracker shown on the driver's application status screen."""
    progress = driver_progress(profile)
    status = profile.verification_status

    if status == DriverProfile.Status.APPROVED:
        review_state, review_detail = 'DONE', 'Approved by the verification team.'
    elif status == DriverProfile.Status.REJECTED:
        review_state, review_detail = 'REJECTED', profile.rejection_reason or 'Application rejected. Please fix the issues and resubmit.'
    elif status == DriverProfile.Status.SUSPENDED:
        review_state, review_detail = 'REJECTED', profile.rejection_reason or 'Account suspended. Contact support.'
    elif status == DriverProfile.Status.UNDER_REVIEW:
        review_state, review_detail = 'IN_PROGRESS', 'A verification agent is checking your documents.'
    elif status == DriverProfile.Status.PENDING_REVIEW:
        review_state, review_detail = 'IN_PROGRESS', 'Waiting in the verification queue.'
    else:
        review_state, review_detail = 'PENDING', 'Submit all steps to enter admin review.'

    docs_state = 'DONE' if progress['documents_complete'] else 'ACTION_REQUIRED'
    consent_state = 'DONE' if progress['consents_complete'] else 'ACTION_REQUIRED'
    training_state = 'DONE' if progress['training_complete'] else 'ACTION_REQUIRED'

    return [
        {
            'key': 'ACCOUNT',
            'title': 'Create account',
            'state': 'DONE' if progress['account_complete'] else 'ACTION_REQUIRED',
            'detail': 'Email verified.' if progress['account_complete'] else 'Verify your email address.',
        },
        {
            'key': 'PERSONAL_PROFILE',
            'title': 'Personal profile',
            'state': 'DONE' if progress['personal_complete'] else 'ACTION_REQUIRED',
            'detail': 'Photo, date of birth, address and emergency contact saved.'
            if progress['personal_complete'] else 'Photo, date of birth, address and emergency contact are required.',
        },
        {
            'key': 'DRIVING_DETAILS',
            'title': 'Driving details',
            'state': 'DONE' if progress['driving_complete'] else 'ACTION_REQUIRED',
            'detail': 'Licence details and driving capabilities saved.'
            if progress['driving_complete'] else 'Licence number, expiry, experience and capabilities are required.',
        },
        {
            'key': 'DOCUMENTS',
            'title': 'Documents, consent and training',
            'state': 'DONE' if (docs_state == 'DONE' and consent_state == 'DONE' and training_state == 'DONE') else 'ACTION_REQUIRED',
            'detail': 'Licence, identity proof, consents and training complete.'
            if (docs_state == 'DONE' and consent_state == 'DONE' and training_state == 'DONE')
            else 'Licence front/back, identity proof, required consents and training modules must be completed.',
        },
        {
            'key': 'REVIEW',
            'title': 'Admin verification',
            'state': review_state,
            'detail': review_detail,
        },
    ]


# ---------------------------------------------------------------------------
# Status transitions (server side only)
# ---------------------------------------------------------------------------

def auto_approve_enabled() -> bool:
    """Development-only helper so the whole flow can be tested without an admin.

    Never enabled in production: it requires DEBUG=true and the explicit
    AUTO_APPROVE_DRIVERS_IN_DEV=true environment flag.
    """
    return bool(getattr(settings, 'DEBUG', False) and getattr(settings, 'AUTO_APPROVE_DRIVERS_IN_DEV', False))


def sync_driver_status(profile: DriverProfile, *, save: bool = True) -> DriverProfile:
    """Recompute completion flags and move the verification status forward.

    Rules:
      * INCOMPLETE -> PENDING_REVIEW when every required step is complete.
      * REJECTED   -> PENDING_REVIEW again after the driver fixes the issues.
      * PENDING_REVIEW -> back to INCOMPLETE if a required item disappears.
      * APPROVED / SUSPENDED / INACTIVE / UNDER_REVIEW are only changed by staff.
    """
    profile.profile_complete = bool(
        personal_profile_complete(profile) and driving_details_complete(profile)
    )

    ready = ready_for_review(profile)
    status = profile.verification_status

    if status in (DriverProfile.Status.INCOMPLETE, DriverProfile.Status.REJECTED) and ready:
        profile.verification_status = DriverProfile.Status.PENDING_REVIEW
        profile.submitted_at = timezone.now()
        profile.rejection_reason = ''
        profile.reviewed_at = None
        profile.reviewed_by = None
    elif status == DriverProfile.Status.PENDING_REVIEW and not ready:
        profile.verification_status = DriverProfile.Status.INCOMPLETE

    if save:
        profile.save()
        if (
            profile.verification_status == DriverProfile.Status.PENDING_REVIEW
            and auto_approve_enabled()
        ):
            apply_review_decision(
                profile,
                action='approve',
                reason='Automatically approved by DEVELOPMENT mode (AUTO_APPROVE_DRIVERS_IN_DEV). '
                       'This is a test shortcut, not a real verification.',
            )
    return profile


def apply_review_decision(profile: DriverProfile, *, action: str, reason: str = '', reviewer=None) -> DriverProfile:
    """Only place where verification status changes to a final value."""
    action = (action or '').lower()
    now = timezone.now()
    if action == 'approve':
        profile.verification_status = DriverProfile.Status.APPROVED
        profile.approved_at = now
        profile.rejection_reason = ''
    elif action == 'reject':
        profile.verification_status = DriverProfile.Status.REJECTED
        profile.rejection_reason = reason or 'Documents did not pass verification.'
        profile.approved_at = None
    elif action == 'suspend':
        profile.verification_status = DriverProfile.Status.SUSPENDED
        profile.rejection_reason = reason or 'Account suspended by admin.'
    elif action == 'reactivate':
        profile.verification_status = DriverProfile.Status.APPROVED
        profile.rejection_reason = ''
    elif action == 'inactive':
        profile.verification_status = DriverProfile.Status.INACTIVE
    elif action == 'under_review':
        profile.verification_status = DriverProfile.Status.UNDER_REVIEW
    elif action == 'pending_review':
        profile.verification_status = DriverProfile.Status.PENDING_REVIEW
    else:
        raise ValueError(f'Unknown review action: {action}')

    if reviewer is not None:
        profile.reviewed_by = reviewer
    profile.reviewed_at = now
    if profile.verification_status != DriverProfile.Status.APPROVED:
        profile.is_available = False
        profile.available_since = None
    profile.save()
    return profile


def ensure_training_rows(profile: DriverProfile) -> list[DriverTraining]:
    """Create any missing training rows, so the checklist is always complete."""
    existing = {row.module: row for row in profile.training.all()}
    created = []
    for module in DriverTraining.Module.values:
        if module not in existing:
            created.append(profile.training.create(module=module))
    if created:
        created = list(profile.training.order_by('id'))
    return list(profile.training.order_by('id'))
