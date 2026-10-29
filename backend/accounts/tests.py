"""End-to-end tests for the authentication + driver registration flow.

Run with:  python manage.py test accounts -v 2

They cover the rules the mobile app depends on:
  * OTP verification and role separation,
  * a driver cannot skip a registration step,
  * documents must be uploaded privately and with a valid type,
  * only staff can review applications, and only complete ones can be approved.
"""

import base64
import re

from django.core import mail
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APITestCase

from .models import DriverDocument, DriverProfile, DriverTraining, User
from .progress import ensure_training_rows

PNG_BYTES = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
)

PASSWORD = 'Str0ngPass!23'


def png_file(name='image.png'):
    return SimpleUploadedFile(name, PNG_BYTES, content_type='image/png')


def last_otp_for(email):
    """Read the newest verification code from the development email outbox."""
    for message in reversed(mail.outbox):
        if email in message.to:
            match = re.search(r'code is (\d{6})', message.body)
            if match:
                return match.group(1)
    raise AssertionError(f'No OTP email found for {email}')


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class RegistrationFlowTests(APITestCase):
    def setUp(self):
        super().setUp()
        from django.core.cache import cache
        cache.clear()

    def register(self, role, email, phone='+919000000123'):
        response = self.client.post(
            reverse('register'),
            {'full_name': 'Test Person', 'email': email, 'phone': phone,
             'password': PASSWORD, 'confirm_password': PASSWORD, 'role': role},
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response

    def verify(self, email):
        code = last_otp_for(email)
        response = self.client.post(reverse('verify-otp'), {'email': email, 'otp': code}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def auth(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    # ------------------------------------------------------------------ tests

    def test_public_signup_cannot_create_admin(self):
        response = self.client.post(
            reverse('register'),
            {'full_name': 'Sneaky Admin', 'email': 'sneaky@example.com', 'phone': '+919000000999',
             'password': PASSWORD, 'role': 'ADMIN'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    def test_customer_registration_otp_and_login(self):
        self.register('CUSTOMER', 'rider@example.com')
        payload = self.verify('rider@example.com')
        self.assertEqual(payload['user']['role'], 'CUSTOMER')
        self.assertFalse(payload['user']['profile_complete'])

        login = self.client.post(
            reverse('login'),
            {'identifier': 'rider@example.com', 'password': PASSWORD, 'role': 'CUSTOMER'},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)

        wrong_role = self.client.post(
            reverse('login'),
            {'identifier': 'rider@example.com', 'password': PASSWORD, 'role': 'DRIVER'},
            format='json',
        )
        self.assertEqual(wrong_role.status_code, 403)

    def test_driver_cannot_skip_registration_steps(self):
        self.register('DRIVER', 'driver@example.com')
        payload = self.verify('driver@example.com')
        self.assertEqual(payload['user']['next_step'], 'PERSONAL_PROFILE')
        self.auth(payload['access'])

        # Trying to jump straight to the driving step fails: step 2 is not done.
        response = self.client.put(
            reverse('profile'),
            {'step': 'DRIVING', 'licence_number': 'DL-12345', 'licence_expiry': '2030-01-01',
             'experience_years': 4, 'manual_transmission': True, 'sedan': True},
            format='json',
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('missing_fields', response.data)

        # Documents are step 4 and cannot be uploaded before steps 2 and 3.
        early_upload = self.client.post(
            reverse('driver-document-upload'),
            {'document_type': 'IDENTITY', 'file': png_file()},
            format='multipart',
        )
        self.assertEqual(early_upload.status_code, 400)

        # Completing step 2 without a photo is still refused (photo is required).
        response = self.client.put(
            reverse('profile'),
            {'step': 'PERSONAL', 'date_of_birth': '1995-05-12', 'address': '1 Test Road',
             'state': 'Uttar Pradesh', 'city': 'Lucknow', 'pincode': '226001',
             'emergency_contact_name': 'Contact', 'emergency_contact_phone': '+919000000321',
             'languages': 'Hindi, English'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('Profile photo', response.data['missing_fields'])

        # An invalid PIN code is refused with a clear message.
        bad_pin = self.client.put(
            reverse('profile'),
            {'state': 'Uttar Pradesh', 'city': 'Lucknow', 'pincode': '0123'},
            format='json',
        )
        self.assertEqual(bad_pin.status_code, 400)
        self.assertIn('PIN', bad_pin.data['detail'])

        photo = self.client.post(reverse('profile-photo'), {'file': png_file()}, format='multipart')
        self.assertEqual(photo.status_code, 201, photo.data)

        response = self.client.put(
            reverse('profile'),
            {'step': 'PERSONAL', 'date_of_birth': '1995-05-12', 'address': '1 Test Road',
             'state': 'Uttar Pradesh', 'city': 'Lucknow', 'pincode': '226001',
             'emergency_contact_name': 'Contact', 'emergency_contact_phone': '+919000000321',
             'languages': 'Hindi, English'},
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['next_step'], 'DRIVING_DETAILS')

    def test_full_driver_application_then_admin_approval(self):
        self.register('DRIVER', 'full.driver@example.com')
        payload = self.verify('full.driver@example.com')
        driver_token = payload['access']
        self.auth(driver_token)

        self.client.post(reverse('profile-photo'), {'file': png_file()}, format='multipart')
        step2 = self.client.put(
            reverse('profile'),
            {'step': 'PERSONAL', 'date_of_birth': '1992-03-04', 'address': '7 Sample Lane',
             'state': 'Uttar Pradesh', 'city': 'Lucknow', 'pincode': '226001', 'service_area': 'Lucknow',
             'emergency_contact_name': 'Kin', 'emergency_contact_phone': '+919000000555',
             'languages': 'Hindi, English', 'introduction': 'Professional driver.'},
            format='json',
        )
        self.assertEqual(step2.status_code, 200, step2.data)

        step3 = self.client.put(
            reverse('profile'),
            {'step': 'DRIVING', 'licence_number': 'UP32-2019-0001234', 'licence_expiry': '2031-08-30',
             'experience_years': 7, 'manual_transmission': True, 'automatic_transmission': True,
             'sedan': True, 'suv': True, 'highway': True, 'night_driving': True},
            format='json',
        )
        self.assertEqual(step3.status_code, 200, step3.data)
        self.assertEqual(step3.data['next_step'], 'DOCUMENTS')

        # Wrong document type is rejected (the app must send the real enum).
        bad = self.client.post(
            reverse('driver-document-upload'),
            {'document_type': 'LICENSE', 'file': png_file()},
            format='multipart',
        )
        self.assertEqual(bad.status_code, 400)

        for document_type in ('LICENCE_FRONT', 'LICENCE_BACK', 'IDENTITY'):
            upload = self.client.post(
                reverse('driver-document-upload'),
                {'document_type': document_type, 'file': png_file(f'{document_type}.png'),
                 'document_number': 'UP32-2019-0001234', 'expires_at': '2031-08-30'},
                format='multipart',
            )
            self.assertEqual(upload.status_code, 201, upload.data)

        consents = self.client.post(
            reverse('driver-consents'),
            {'consent_background_check': True, 'consent_terms': True, 'consent_data_accuracy': True},
            format='json',
        )
        self.assertEqual(consents.status_code, 200, consents.data)

        for module in ('SAFE_DRIVING', 'CUSTOMER_SERVICE', 'VEHICLE_INSPECTION'):
            done = self.client.post(reverse('driver-training-complete', kwargs={'module': module}))
            self.assertEqual(done.status_code, 200, done.data)

        application = self.client.get(reverse('driver-application'))
        self.assertEqual(application.status_code, 200)
        self.assertEqual(application.data['progress']['verification_status'], 'PENDING_REVIEW')
        self.assertTrue(all(step['state'] != 'ACTION_REQUIRED' for step in application.data['steps'][:4]))

        # Staff review
        staff = User.objects.create_superuser(email='staff@example.com', full_name='Staff', password=PASSWORD)
        self.assertEqual(staff.role, 'ADMIN')
        driver = User.objects.get(email='full.driver@example.com')

        no_access = self.client.post(
            reverse('admin-driver-review', kwargs={'user_id': driver.id}), {'action': 'approve'}, format='json'
        )
        self.assertIn(no_access.status_code, (401, 403))

        self.auth(self.verify_staff('staff@example.com'))
        approve = self.client.post(
            reverse('admin-driver-review', kwargs={'user_id': driver.id}), {'action': 'approve'}, format='json'
        )
        self.assertEqual(approve.status_code, 200, approve.data)
        self.assertEqual(approve.data['verification_status'], 'APPROVED')

        self.auth(driver_token)  # back to the driver's own session
        refreshed = self.client.get(reverse('driver-application'))
        self.assertEqual(refreshed.data['progress']['next_step'], 'DASHBOARD')

    def verify_staff(self, email):
        response = self.client.post(
            reverse('login'), {'identifier': email, 'password': PASSWORD, 'role': 'ADMIN'}, format='json'
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response.data['access']

    def test_incomplete_application_cannot_be_approved(self):
        self.register('DRIVER', 'incomplete@example.com')
        self.verify('incomplete@example.com')
        User.objects.create_superuser(email='staff2@example.com', full_name='Staff', password=PASSWORD)
        token = self.verify_staff('staff2@example.com')
        self.auth(token)
        driver = User.objects.get(email='incomplete@example.com')
        response = self.client.post(
            reverse('admin-driver-review', kwargs={'user_id': driver.id}), {'action': 'approve'}, format='json'
        )
        self.assertEqual(response.status_code, 400)

    def test_upload_size_and_type_validation(self):
        self.register('DRIVER', 'upload@example.com')
        payload = self.verify('upload@example.com')
        self.auth(payload['access'])

        too_big = SimpleUploadedFile('big.png', b'0' * (5 * 1024 * 1024 + 1), content_type='image/png')
        response = self.client.post(reverse('profile-photo'), {'file': too_big}, format='multipart')
        self.assertEqual(response.status_code, 400)

        wrong_type = SimpleUploadedFile('script.exe', b'bin', content_type='application/x-msdownload')
        response = self.client.post(reverse('profile-photo'), {'file': wrong_type}, format='multipart')
        self.assertEqual(response.status_code, 400)

    def complete_profile_steps(self):
        """Step 2 + step 3, so the driver reaches the documents step."""
        self.client.post(reverse('profile-photo'), {'file': png_file()}, format='multipart')
        step2 = self.client.put(
            reverse('profile'),
            {'step': 'PERSONAL', 'date_of_birth': '1994-02-02', 'address': '5 Helper Road',
             'state': 'Uttar Pradesh', 'city': 'Lucknow', 'pincode': '226001',
             'emergency_contact_name': 'Next Of Kin', 'emergency_contact_phone': '+919000000777',
             'languages': 'Hindi, English'},
            format='json',
        )
        self.assertEqual(step2.status_code, 200, step2.data)
        step3 = self.client.put(
            reverse('profile'),
            {'step': 'DRIVING', 'licence_number': 'DL-HELPER-1', 'licence_expiry': '2032-01-01',
             'experience_years': 5, 'automatic_transmission': True, 'sedan': True},
            format='json',
        )
        self.assertEqual(step3.status_code, 200, step3.data)

    def test_training_rows_are_created_for_new_drivers(self):
        self.register('DRIVER', 'training@example.com')
        self.verify('training@example.com')
        driver = User.objects.get(email='training@example.com')
        ensure_training_rows(DriverProfile.objects.get(user=driver))
        self.assertEqual(DriverTraining.objects.filter(driver__user=driver).count(), len(DriverTraining.Module.values))

    def test_health_endpoint_is_public_and_reachable(self):
        """The app probes /api/health/ at start-up to pick a working address."""
        response = self.client.get(reverse('health'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['status'], 'ok')

    def test_profile_get_works_for_both_roles(self):
        """GET /auth/profile/ must return the saved profile for a customer and
        for a driver. (Regression: the customer branch used to reference
        request data that does not exist on a GET, which raised a 500.)"""
        # Customer
        self.register('CUSTOMER', 'profile.customer@example.com', phone='+919000000471')
        token = self.verify('profile.customer@example.com')['access']
        self.auth(token)
        response = self.client.get(reverse('profile'))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['role'], 'CUSTOMER')
        self.assertIn('state', response.data['profile'])
        self.assertIn('pincode', response.data['profile'])

        # Driver
        self.client.credentials()
        self.register('DRIVER', 'profile.driver@example.com', phone='+919000000472')
        driver_token = self.verify('profile.driver@example.com')['access']
        self.auth(driver_token)
        driver_response = self.client.get(reverse('profile'))
        self.assertEqual(driver_response.status_code, 200, driver_response.data)
        self.assertEqual(driver_response.data['role'], 'DRIVER')
        self.assertIn('state', driver_response.data['profile'])
        self.assertIn('pincode', driver_response.data['profile'])
        self.assertIn('progress', driver_response.data)

    def test_upload_is_validated_by_file_content(self):
        """A real JPEG/PNG is accepted even when the client sends a generic
        content type - this is what mobile multipart uploads used to do, and it
        caused "Allowed file types: jpg, png, webp" on a perfectly good photo."""
        self.register('DRIVER', 'sniff@example.com')
        payload = self.verify('sniff@example.com')
        self.auth(payload['access'])

        generic = SimpleUploadedFile('photo.png', PNG_BYTES, content_type='application/octet-stream')
        accepted = self.client.post(reverse('profile-photo'), {'file': generic}, format='multipart')
        self.assertEqual(accepted.status_code, 201, accepted.data)

        not_an_image = SimpleUploadedFile('fake.png', b'this is not an image at all', content_type='image/png')
        rejected = self.client.post(reverse('profile-photo'), {'file': not_an_image}, format='multipart')
        self.assertEqual(rejected.status_code, 400)

    def test_documents_are_stored_under_private_keys(self):
        self.register('DRIVER', 'private@example.com')
        payload = self.verify('private@example.com')
        self.auth(payload['access'])
        self.complete_profile_steps()
        self.client.post(
            reverse('driver-document-upload'),
            {'document_type': 'IDENTITY', 'file': png_file()},
            format='multipart',
        )
        document = DriverDocument.objects.get(document_type='IDENTITY')
        self.assertTrue(document.private_storage_key.startswith('private/driver-documents/'))
        document.private_storage_key = ''  # keep the test database clean
