from decimal import Decimal
from django.db import connection
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from accounts.models import User, DriverProfile, DriverDocument
from .models import ServiceRate, Booking
from .pricing import estimate_fare, platform_fee, driver_payout


class AdminChangesTests(TestCase):
    def test_rates_and_audit(self):
        rate = ServiceRate.objects.get(service='HOURLY')
        rate.base, rate.per_hour = 50, 200
        rate.save()
        self.assertEqual(estimate_fare('HOURLY', 2), Decimal('450'))
        self.assertEqual(platform_fee(450), Decimal('81.00'))
        self.assertEqual(driver_payout(450), Decimal('369.00'))
        with connection.cursor() as cursor:
            cursor.execute('SELECT old_base, new_base, old_per_hour, new_per_hour FROM rides_rate_change_audit WHERE rate_id = %s', [rate.pk])
            self.assertEqual(cursor.fetchone(), (99, 50, 119, 200))
            cursor.execute('SELECT COUNT(*) FROM rides_completed_analytics')
            self.assertEqual(cursor.fetchone()[0], 0)

    def test_document_review_is_staff_only_and_independent(self):
        staff = User.objects.create_user(email='staff@example.com', full_name='Staff', password='pass12345', is_staff=True)
        driver = User.objects.create_user(email='driver-doc@example.com', full_name='Driver', password='pass12345')
        profile, _ = DriverProfile.objects.get_or_create(user=driver)
        a = DriverDocument.objects.create(driver=profile, document_type='LICENCE_FRONT', private_storage_key='a.jpg')
        b = DriverDocument.objects.create(driver=profile, document_type='IDENTITY', private_storage_key='b.jpg')
        client = APIClient()
        client.force_authenticate(driver)
        url = reverse('admin-document-review', args=[a.pk])
        self.assertEqual(client.post(url, {'action':'approve'}).status_code, 403)
        client.force_authenticate(staff)
        self.assertEqual(client.post(url, {'action':'reject', 'reason':'bad'}).status_code, 400)
        self.assertEqual(client.post(url, {'action':'reject', 'reason':'Photo is blurred'}).status_code, 200)
        a.refresh_from_db(); b.refresh_from_db()
        self.assertEqual(a.review_status, 'REJECTED')
        self.assertEqual(b.review_status, 'PENDING')
        self.assertEqual(client.post(url, {'action':'pending'}).status_code, 200)
        a.refresh_from_db()
        self.assertEqual((a.review_status, a.rejection_reason), ('PENDING', ''))
        self.assertEqual(client.post(url, {'action':'approve'}).status_code, 200)
        a.refresh_from_db()
        self.assertEqual(a.review_status, 'APPROVED')
        self.assertEqual(a.reviewed_by_id, staff.pk)

    def test_grouped_admin_displays_document_inline(self):
        staff = User.objects.create_superuser(email='super@example.com', full_name='Staff', password='pass12345')
        driver = User.objects.create_user(email='group@example.com', full_name='Driver', password='pass12345')
        profile, _ = DriverProfile.objects.get_or_create(user=driver)
        DriverDocument.objects.create(driver=profile, document_type='IDENTITY', private_storage_key='a.jpg')
        self.client.force_login(staff)
        response = self.client.get(reverse('admin:accounts_driverdocumentgroup_change', args=[profile.pk]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Identity proof')

    def test_grouped_admin_saves_individual_status(self):
        staff = User.objects.create_superuser(email='admin2@example.com', full_name='Staff', password='pass12345')
        driver = User.objects.create_user(email='driver2@example.com', full_name='Driver', password='pass12345')
        profile, _ = DriverProfile.objects.get_or_create(user=driver)
        a = DriverDocument.objects.create(driver=profile, document_type='IDENTITY', private_storage_key='a.jpg')
        b = DriverDocument.objects.create(driver=profile, document_type='LICENCE_FRONT', private_storage_key='b.jpg')
        self.client.force_login(staff)
        response = self.client.post(reverse('admin:accounts_driverdocumentgroup_change', args=[profile.pk]), {
            'documents-TOTAL_FORMS': '2', 'documents-INITIAL_FORMS': '2',
            'documents-MIN_NUM_FORMS': '0', 'documents-MAX_NUM_FORMS': '1000',
            'documents-0-id': str(a.pk), 'documents-0-driver': str(profile.pk),
            'documents-0-review_status': 'REJECTED', 'documents-0-rejection_reason': 'Image is blurred',
            'documents-1-id': str(b.pk), 'documents-1-driver': str(profile.pk),
            'documents-1-review_status': 'APPROVED', 'documents-1-rejection_reason': '',
            '_save': 'Save',
        })
        self.assertEqual(response.status_code, 302, response.context and response.context.get('errors'))
        a.refresh_from_db(); b.refresh_from_db()
        self.assertEqual((a.review_status, a.reviewed_by_id), ('REJECTED', staff.id))
        self.assertEqual((b.review_status, b.reviewed_by_id), ('APPROVED', staff.id))
