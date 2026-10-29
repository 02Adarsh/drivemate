import io
import tempfile
from decimal import Decimal
from urllib.parse import urlsplit,parse_qs

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase
import qrcode,numpy as np,zxingcpp
from PIL import Image

from accounts.models import User,DriverProfile
from rides.models import Booking,Vehicle
from .models import DriverUPIProfile,DirectUPIPayment,PaymentAudit
from .qr import make_payload

PASSWORD='Strong@12345'
VPA='qa.receiver@invalid'


def image_file(vpa=VPA,amount='999.00',name='QA Driver'):
    payload=make_payload(vpa,name,amount,'OLDREFERENCE',999)
    output=io.BytesIO();qrcode.make(payload).save(output,format='PNG')
    return SimpleUploadedFile('receiving-qr.png',output.getvalue(),content_type='image/png')


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class DirectUPITests(APITestCase):
    def setUp(self):
        cache.clear();self.storage=tempfile.TemporaryDirectory()
        self.override=override_settings(MEDIA_ROOT=self.storage.name);self.override.enable()
        self.customer=User.objects.create_user('upi-rider@example.com','UPI Rider',PASSWORD,role='CUSTOMER',email_verified=True)
        self.driver=User.objects.create_user('upi-driver@example.com','UPI Driver',PASSWORD,role='DRIVER',email_verified=True)
        self.other=User.objects.create_user('upi-other@example.com','Other',PASSWORD,role='CUSTOMER',email_verified=True)
        DriverProfile.objects.create(user=self.driver,verification_status='APPROVED',is_available=True,manual_transmission=True)
        self.vehicle=Vehicle.objects.create(owner=self.customer,make='Maruti',model='Dzire',registration='HR26AB1234')
        self.booking=Booking.objects.create(customer=self.customer,driver=self.driver,vehicle=self.vehicle,service='HOURLY',duration_hours=4,pickup='Test pickup',status='COMPLETED',estimated_fare=575,final_fare=575)
        self.auth(self.driver)

    def tearDown(self):
        self.override.disable();self.storage.cleanup();super().tearDown()

    def auth(self,user):self.client.force_authenticate(user=user)

    def configure(self,vpa=VPA):
        self.auth(self.driver)
        reply=self.client.post('/api/payments/driver/profile/',{'upi_id':vpa,'password':PASSWORD,'ownership_attested':True,'file':image_file(vpa)},format='multipart')
        self.assertEqual(reply.status_code,200,reply.data)
        return reply.data

    def request(self):
        self.configure();self.auth(self.customer)
        reply=self.client.post(f'/api/payments/trips/{self.booking.pk}/',{'amount':'1.00','receiver_upi_id':'wrong@invalid'},format='json')
        self.assertEqual(reply.status_code,201,reply.data)
        return reply.data

    def confirm(self,reference='RRN1234567890',amount='575.00'):
        self.auth(self.driver)
        return self.client.post(f'/api/payments/trips/{self.booking.pk}/review/',{'action':'confirm','checked_bank':True,'received_amount':amount,'bank_reference':reference},format='json')

    def test_matching_receiving_qr_is_required_but_not_bank_verified(self):
        data=self.configure()
        self.assertTrue(data['qr_matches_upi']);self.assertFalse(data['bank_ownership_verified'])
        self.assertEqual(data['upi_id'],VPA)
        self.assertTrue(DriverUPIProfile.objects.get(driver=self.driver).qr_storage_key.startswith('private/driver-upi/'))

    def test_password_attestation_and_driver_role_are_required(self):
        bad=self.client.post('/api/payments/driver/profile/',{'upi_id':VPA,'password':'wrong','ownership_attested':True,'file':image_file()},format='multipart')
        self.assertEqual(bad.status_code,400)
        bad=self.client.post('/api/payments/driver/profile/',{'upi_id':VPA,'password':PASSWORD,'ownership_attested':False,'file':image_file()},format='multipart')
        self.assertEqual(bad.status_code,400)
        self.auth(self.customer)
        self.assertEqual(self.client.get('/api/payments/driver/profile/').status_code,403)

    def test_mismatched_qr_and_web_qr_are_rejected(self):
        bad=self.client.post('/api/payments/driver/profile/',{'upi_id':'other@invalid','password':PASSWORD,'ownership_attested':True,'file':image_file()},format='multipart')
        self.assertEqual(bad.status_code,400)
        output=io.BytesIO();qrcode.make('https://example.com/not-a-upi-qr').save(output,format='PNG')
        bad=self.client.post('/api/payments/driver/profile/',{'upi_id':VPA,'password':PASSWORD,'ownership_attested':True,'file':SimpleUploadedFile('web.png',output.getvalue(),content_type='image/png')},format='multipart')
        self.assertEqual(bad.status_code,400)

    def test_generated_qr_uses_server_fare_not_uploaded_amount_or_client_amount(self):
        data=self.request()
        self.assertEqual(Decimal(data['amount']),Decimal('575'))
        fields=parse_qs(urlsplit(data['qr_payload']).query)
        self.assertEqual(fields['am'],['575.00']);self.assertEqual(fields['pa'],[VPA])
        self.assertFalse(data['amount_editable_in_drivemate'])
        self.assertFalse(data['external_upi_amount_lock_guaranteed'])
        self.assertFalse(data['bank_verified'])
        self.assertNotIn('OLDREFERENCE',data['qr_payload'])

    def test_new_qr_png_roundtrips_with_exact_amount(self):
        self.request();response=self.client.get(f'/api/payments/trips/{self.booking.pk}/qr/')
        self.assertEqual(response.status_code,200)
        content=b''.join(response.streaming_content)
        image=Image.open(io.BytesIO(content)).convert('RGB')
        found=zxingcpp.read_barcodes(np.asarray(image))
        fields=parse_qs(urlsplit(found[0].text).query)
        self.assertEqual(fields['am'],['575.00']);self.assertEqual(fields['cu'],['INR'])
        self.assertIn('no-store',response['Cache-Control'])

    def test_only_participants_can_get_request_and_profile_image_is_owner_only(self):
        self.request();self.auth(self.other)
        self.assertEqual(self.client.get(f'/api/payments/trips/{self.booking.pk}/').status_code,404)
        self.assertEqual(self.client.get(f'/api/payments/trips/{self.booking.pk}/qr/').status_code,404)
        self.assertEqual(self.client.get('/api/payments/driver/qr/').status_code,403)

    def test_before_completion_or_without_setup_no_payment_qr(self):
        self.auth(self.customer)
        self.assertEqual(self.client.post(f'/api/payments/trips/{self.booking.pk}/').status_code,400)
        self.configure();Booking.objects.filter(pk=self.booking.pk).update(status='ONGOING',final_fare=None)
        self.auth(self.customer)
        self.assertEqual(self.client.post(f'/api/payments/trips/{self.booking.pk}/').status_code,400)

    def test_opening_qr_twice_is_idempotent_and_payee_snapshot_does_not_change(self):
        first=self.request();second=self.client.post(f'/api/payments/trips/{self.booking.pk}/')
        self.assertEqual(second.status_code,200);self.assertEqual(first['id'],second.data['id'])
        self.configure('new.receiver@invalid');self.auth(self.customer)
        response=self.client.get(f'/api/payments/trips/{self.booking.pk}/')
        self.assertEqual(response.data['receiver_upi_id'],VPA)
        self.assertEqual(DirectUPIPayment.objects.count(),1)

    def test_i_paid_is_only_a_report_not_verified_or_paid(self):
        self.request();response=self.client.post(f'/api/payments/trips/{self.booking.pk}/report/',{'reference':'RRN1234567890'},format='json')
        self.assertEqual(response.data['status'],'REPORTED');self.assertFalse(response.data['bank_verified'])
        booking=self.client.get(f'/api/rides/bookings/{self.booking.pk}/').data
        self.assertFalse(booking['payment_received']);self.assertEqual(booking['payment_status'],'AWAITING_DRIVER_CONFIRMATION')
        self.auth(self.driver)
        self.assertEqual(self.client.post(f'/api/payments/trips/{self.booking.pk}/report/',{'reference':'RRN1234567890'},format='json').status_code,403)

    def test_customer_or_wrong_amount_cannot_confirm_paid(self):
        self.request()
        payload={'action':'confirm','checked_bank':True,'received_amount':'575','bank_reference':'RRN1234567890'}
        self.assertEqual(self.client.post(f'/api/payments/trips/{self.booking.pk}/review/',payload,format='json').status_code,403)
        self.assertEqual(self.confirm(amount='1.00').status_code,400)
        self.assertNotEqual(DirectUPIPayment.objects.get(booking=self.booking).status,'CONFIRMED')

    def test_driver_manual_confirmation_is_idempotent_and_receipt_is_upi_not_cash(self):
        self.request()
        for _ in range(2):self.assertEqual(self.confirm().status_code,200)
        row=DirectUPIPayment.objects.get(booking=self.booking)
        self.assertEqual(row.audit.filter(action='DRIVER_CONFIRMED').count(),1)
        self.assertEqual(Booking.objects.get(pk=self.booking.pk).events.filter(note__contains='manually confirmed direct UPI').count(),1)
        self.assertIsNone(Booking.objects.get(pk=self.booking.pk).cash_received_at)
        self.auth(self.customer)
        data=self.client.get(f'/api/rides/bookings/{self.booking.pk}/').data
        self.assertTrue(data['payment_received']);self.assertEqual(data['payment_method'],'UPI_DIRECT')
        self.assertEqual(data['payment_verification'],'manual_driver')
        self.assertIn('manually',data['payment_label'].lower())

    def test_same_bank_reference_cannot_confirm_two_trips(self):
        self.request();self.assertEqual(self.confirm().status_code,200)
        second=Booking.objects.create(customer=self.customer,driver=self.driver,vehicle=self.vehicle,service='HOURLY',duration_hours=4,pickup='Second trip',status='COMPLETED',estimated_fare=575,final_fare=575)
        self.auth(self.customer);self.client.post(f'/api/payments/trips/{second.pk}/')
        self.auth(self.driver)
        response=self.client.post(f'/api/payments/trips/{second.pk}/review/',{'action':'confirm','checked_bank':True,'received_amount':'575','bank_reference':'RRN1234567890'},format='json')
        self.assertEqual(response.status_code,400)

    def test_cash_and_upi_cannot_both_be_recorded_for_the_same_trip(self):
        self.request();self.auth(self.driver)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{self.booking.pk}/cash/').status_code,400)
        self.assertEqual(self.confirm().status_code,200)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{self.booking.pk}/cash/').status_code,400)
        response=self.client.get(f'/api/payments/trips/{self.booking.pk}/qr/')
        self.assertEqual(response.status_code,400)

    def test_close_in_app_before_cash_is_not_bank_cancellation(self):
        self.request();self.auth(self.driver)
        response=self.client.post(f'/api/payments/trips/{self.booking.pk}/cancel/',{'checked_no_payment':True},format='json')
        self.assertEqual(response.status_code,200)
        self.assertEqual(response.data['status'],'CANCELLED')
        self.assertIn('remain payable',response.data['notice'])
        self.assertEqual(self.client.post(f'/api/rides/bookings/{self.booking.pk}/cash/').status_code,200)
        self.auth(self.customer)
        self.assertEqual(self.client.post(f'/api/payments/trips/{self.booking.pk}/').status_code,400)

    def test_rejected_report_stays_unpaid_and_customer_can_report_again(self):
        self.request();self.client.post(f'/api/payments/trips/{self.booking.pk}/report/',{'reference':'RRN1234567890'},format='json')
        self.auth(self.driver)
        response=self.client.post(f'/api/payments/trips/{self.booking.pk}/review/',{'action':'reject','note':'Credit not found; check payment status before retrying.'},format='json')
        self.assertEqual(response.status_code,200);self.assertEqual(response.data['status'],'REJECTED')
        self.auth(self.customer)
        data=self.client.get(f'/api/rides/bookings/{self.booking.pk}/').data;self.assertFalse(data['payment_received'])
        again=self.client.post(f'/api/payments/trips/{self.booking.pk}/report/',{'reference':'RRN1234567891'},format='json')
        self.assertEqual(again.status_code,200)

    def test_driver_must_acknowledge_actual_bank_credit(self):
        self.request();self.auth(self.driver)
        response=self.client.post(f'/api/payments/trips/{self.booking.pk}/review/',{'action':'confirm','received_amount':'575','bank_reference':'RRN1234567890'},format='json')
        self.assertEqual(response.status_code,400)
