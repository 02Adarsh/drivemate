import json
import re
from datetime import timedelta
from unittest.mock import patch

from django.core import mail
from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import User, DriverProfile, EmailOTP
from accounts.views import issue_otp
from rides.models import Booking, Vehicle, TripStartCode, Notification, TripRating
from rides.trip_security import reveal_code
from .models import Preferences, SavedPlace, Contact, PromoCode, ClaimedPromo, BusinessProfile


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',SECRET_KEY='v9-test-key-which-is-long-private-and-only-used-in-tests')
class V9Tests(APITestCase):
    def setUp(self):
        cache.clear()
        self.customer=User.objects.create_user('v9-rider@example.com','V9 Rider','Strong@12345',role='CUSTOMER',phone='+919000001001',email_verified=True)
        self.driver=User.objects.create_user('v9-driver@example.com','V9 Driver','Strong@12345',role='DRIVER',phone='+919000001002',email_verified=True)
        DriverProfile.objects.create(user=self.driver,verification_status='APPROVED',is_available=True,manual_transmission=True,automatic_transmission=True,night_driving=True,outstation=True,licence_expiry=timezone.localdate()+timedelta(days=365))
        self.other=User.objects.create_user('v9-other@example.com','Other Rider','Strong@12345',role='CUSTOMER',phone='+919000001003',email_verified=True)
        self.staff=User.objects.create_superuser('v9-admin@example.com','Admin','Strong@12345')
        self.car=Vehicle.objects.create(owner=self.customer,make='Maruti',model='Dzire',registration='HR26AB1234')
        self.as_user(self.customer)

    def as_user(self,user):
        self.client.credentials()
        self.client.force_authenticate(user=user)

    def create(self,**overrides):
        self.as_user(self.customer)
        payload={'vehicle_id':self.car.pk,'service':'HOURLY','duration_hours':4,'pickup':'Sector 15 metro gate',
                 'pickup_latitude':'28.4595000','pickup_longitude':'77.0266000'}
        payload.update(overrides)
        response=self.client.post('/api/rides/bookings/',payload,format='json')
        self.assertEqual(response.status_code,201,response.data)
        return response.data['id']

    def accept(self):
        pk=self.create()
        self.as_user(self.driver)
        response=self.client.post(f'/api/rides/requests/{pk}/accept/')
        self.assertEqual(response.status_code,200,response.data)
        self.assertNotIn('otp',response.data)
        self.assertNotIn('code_ciphertext',response.data)
        return pk

    def code(self,pk):
        self.as_user(self.customer)
        response=self.client.get(f'/api/rides/bookings/{pk}/start-code/')
        self.assertEqual(response.status_code,200,response.data)
        return response.data['otp']

    def finish(self):
        pk=self.accept();code=self.code(pk);self.as_user(self.driver)
        started=self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':code},format='json')
        self.assertEqual(started.status_code,200,started.data)
        done=self.client.post(f'/api/rides/trips/{pk}/complete/')
        self.assertEqual(done.status_code,200,done.data)
        return pk

    def test_missing_wrong_and_correct_start_otp_are_server_enforced(self):
        pk=self.accept()
        missing=self.client.post(f'/api/rides/trips/{pk}/start/',{},format='json')
        self.assertEqual(missing.status_code,400)
        self.assertEqual(Booking.objects.get(pk=pk).status,'ACCEPTED')
        code=self.code(pk);self.as_user(self.driver)
        wrong=str((int(code)+1)%1000000).zfill(6)
        self.assertEqual(self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':wrong},format='json').status_code,400)
        result=self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':code},format='json')
        self.assertEqual(result.status_code,200)
        self.assertIsNotNone(result.data['otp_verified_at'])
        self.assertEqual(result.data['status'],'ONGOING')
        self.assertIsNotNone(TripStartCode.objects.get(booking_id=pk).consumed_at)
        self.assertEqual(self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':code},format='json').status_code,400)

    def test_otp_is_customer_only_and_encrypted_at_rest(self):
        pk=self.accept()
        self.assertEqual(self.client.get(f'/api/rides/bookings/{pk}/start-code/').status_code,404)
        self.as_user(self.other)
        self.assertEqual(self.client.get(f'/api/rides/bookings/{pk}/start-code/').status_code,404)
        code=self.code(pk)
        row=TripStartCode.objects.get(booking_id=pk)
        self.assertNotEqual(code,row.code_hash)
        self.assertNotIn(code,row.code_ciphertext)
        self.assertEqual(code,reveal_code(row))
        export=self.client.get('/api/hub/privacy/').content.decode()
        self.assertNotIn(row.code_hash,export)
        self.assertNotIn(row.code_ciphertext,export)

    def test_expiry_regeneration_and_attempt_lock(self):
        pk=self.accept();code=self.code(pk)
        TripStartCode.objects.filter(booking_id=pk).update(expires_at=timezone.now()-timedelta(seconds=1))
        self.as_user(self.driver)
        self.assertEqual(self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':code},format='json').status_code,400)
        self.as_user(self.customer)
        regenerated=self.client.post(f'/api/rides/bookings/{pk}/start-code/')
        self.assertEqual(regenerated.status_code,200)
        code=regenerated.data['otp'];wrong=str((int(code)+1)%1000000).zfill(6)
        self.as_user(self.driver)
        for _ in range(5): response=self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':wrong},format='json')
        self.assertEqual(response.status_code,429)
        self.assertEqual(self.client.post(f'/api/rides/trips/{pk}/start/',{'otp':code},format='json').status_code,429)
        self.assertEqual(Booking.objects.get(pk=pk).status,'ACCEPTED')

    def test_assignment_emails_only_customer_not_driver(self):
        pk=self.create();self.as_user(self.driver)
        with self.captureOnCommitCallbacks(execute=True):
            self.client.post(f'/api/rides/requests/{pk}/accept/')
        emails=[message for message in mail.outbox if 'start code' in message.subject]
        self.assertEqual(len(emails),1)
        self.assertEqual(emails[0].to,[self.customer.email])
        code=self.code(pk)
        self.assertIn(code,emails[0].body)

    def test_verified_email_alone_cannot_mint_a_token(self):
        self.client.force_authenticate(user=None)
        response=self.client.post('/api/auth/verify-otp/',{'email':self.customer.email,'otp':'000000'},format='json')
        self.assertEqual(response.status_code,400)
        self.assertNotIn('access',response.data)

    def test_email_login_code_replay_and_wrong_guess(self):
        self.client.force_authenticate(user=None)
        response=self.client.post('/api/auth/login/otp/',{'email':self.customer.email},format='json')
        self.assertEqual(response.status_code,200)
        code=re.search(r'\b(\d{6})\b',mail.outbox[-1].body).group(1)
        wrong=str((int(code)+1)%1000000).zfill(6)
        self.assertEqual(self.client.post('/api/auth/verify-otp/',{'email':self.customer.email,'otp':wrong},format='json').status_code,400)
        verified=self.client.post('/api/auth/verify-otp/',{'email':self.customer.email,'otp':code},format='json')
        self.assertEqual(verified.status_code,200)
        self.assertEqual(verified.data['user']['role'],'CUSTOMER')
        self.assertEqual(self.client.post('/api/auth/verify-otp/',{'email':self.customer.email,'otp':code},format='json').status_code,400)

    def test_reset_code_cannot_be_used_for_login(self):
        issue_otp(self.customer,purpose='RESET_PASSWORD')
        code=re.search(r'\b(\d{6})\b',mail.outbox[-1].body).group(1)
        self.client.force_authenticate(user=None)
        result=self.client.post('/api/auth/verify-otp/',{'email':self.customer.email,'otp':code},format='json')
        self.assertEqual(result.status_code,400)

    def test_missing_smtp_is_not_fake_delivery_and_registration_rolls_back(self):
        self.client.force_authenticate(user=None)
        with override_settings(EMAIL_BACKEND='django.core.mail.backends.console.EmailBackend'):
            response=self.client.post('/api/auth/register/',{'full_name':'New person','email':'new-v9@example.com','phone':'+919000001099','password':'Strong@12345','confirm_password':'Strong@12345','role':'CUSTOMER'},format='json')
        self.assertEqual(response.status_code,503)
        self.assertFalse(User.objects.filter(email='new-v9@example.com').exists())

    def test_saved_places_contact_and_business_are_owned(self):
        place={'label':'Home','address':'Sector 15 gate','latitude':'28.4595000','longitude':'77.0266000','kind':'HOME'}
        response=self.client.post('/api/hub/collections/places/',place,format='json')
        self.assertEqual(response.status_code,201,response.data)
        pk=response.data['id']
        self.assertEqual(self.client.post('/api/hub/collections/places/',{**place,'latitude':'91'},format='json').status_code,400)
        contact=self.client.post('/api/hub/collections/contacts/',{'name':'Family member','phone':'+919000000333','emergency':True},format='json')
        self.assertEqual(contact.status_code,201)
        self.as_user(self.other)
        self.assertEqual(self.client.get(f'/api/hub/collections/places/{pk}/').status_code,404)
        self.assertEqual(self.client.delete(f'/api/hub/collections/places/{pk}/').status_code,404)

    def test_cash_receipt_and_pdf_are_real_owned_records(self):
        pk=self.finish()
        self.as_user(self.customer)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/cash/').status_code,403)
        self.as_user(self.driver)
        for _ in range(2):self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/cash/').status_code,200)
        self.assertEqual(Booking.objects.get(pk=pk).events.filter(note__contains='confirmed cash').count(),1)
        pdf=self.client.get(f'/api/rides/bookings/{pk}/receipt/')
        self.assertEqual(pdf.status_code,200)
        content=b''.join(pdf.streaming_content)
        self.assertTrue(content.startswith(b'%PDF'))
        self.as_user(self.other)
        self.assertEqual(self.client.get(f'/api/rides/bookings/{pk}/receipt/').status_code,404)

    def test_receipt_email_only_uses_verified_participant_email(self):
        pk=self.finish();self.as_user(self.customer)
        response=self.client.post(f'/api/rides/bookings/{pk}/receipt/',{'email':'attacker@example.com'},format='json')
        self.assertEqual(response.status_code,200)
        self.assertEqual(mail.outbox[-1].to,[self.customer.email])
        self.assertTrue(mail.outbox[-1].attachments)

    def test_driver_location_is_private_validated_and_hidden_after_trip(self):
        pk=self.accept()
        self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/location/',{'latitude':'91','longitude':'77'},format='json').status_code,400)
        response=self.client.post(f'/api/rides/bookings/{pk}/location/',{'latitude':'28.4500000','longitude':'77.0200000'},format='json')
        self.assertEqual(response.status_code,200)
        self.as_user(self.other)
        self.assertEqual(self.client.get(f'/api/rides/bookings/{pk}/location/').status_code,404)
        self.as_user(self.customer)
        self.assertEqual(float(self.client.get(f'/api/rides/bookings/{pk}/location/').data['latitude']),28.45)
        Booking.objects.filter(pk=pk).update(status='COMPLETED')
        self.assertIsNone(self.client.get(f'/api/rides/bookings/{pk}/location/').data['latitude'])

    def test_rating_needs_completed_owned_trip_and_is_not_duplicated(self):
        pk=self.finish();self.as_user(self.customer)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/rating/',{'score':6},format='json').status_code,400)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/rating/',{'score':5,'comment':'Good drive'},format='json').status_code,200)
        self.client.post(f'/api/rides/bookings/{pk}/rating/',{'score':4},format='json')
        self.assertEqual(TripRating.objects.filter(booking_id=pk).count(),1)
        self.as_user(self.other)
        self.assertEqual(self.client.post(f'/api/rides/bookings/{pk}/rating/',{'score':5},format='json').status_code,404)

    def test_support_ticket_replies_and_staff_scope(self):
        created=self.client.post('/api/hub/tickets/',{'subject':'Payment question','description':'Please review my cash receipt.','category':'PAYMENT'},format='json')
        self.assertEqual(created.status_code,201)
        pk=created.data['id'];self.as_user(self.other)
        self.assertEqual(self.client.get(f'/api/hub/tickets/{pk}/').status_code,404)
        self.as_user(self.staff)
        response=self.client.post(f'/api/hub/tickets/{pk}/',{'text':'We are reviewing this.','status':'CLOSED'},format='json')
        self.assertEqual(response.status_code,200)
        self.assertEqual(response.data['status'],'CLOSED')
        self.assertTrue(response.data['messages'][0]['staff'])

    def test_promo_discount_is_server_computed_and_only_usable_once(self):
        promo=PromoCode.objects.create(code='SAVE50',description='Operator test promotion',amount='50')
        self.assertEqual(self.client.post('/api/hub/promotions/',{'code':'SAVE50'},format='json').status_code,200)
        pk=self.create(promo_code='SAVE50',discount_amount='574')
        booking=Booking.objects.get(pk=pk)
        self.assertEqual(booking.estimated_fare,525)
        self.assertEqual(booking.discount_amount,50)
        self.assertEqual(ClaimedPromo.objects.get(user=self.customer,promo=promo).used_booking_id,pk)

    def test_email_change_requires_code_and_never_changes_role(self):
        self.assertEqual(self.client.post('/api/hub/email/',{'email':'new-address@example.com','password':'Strong@12345'},format='json').status_code,200)
        code=re.search(r'\b(\d{6})\b',mail.outbox[-1].body).group(1)
        result=self.client.put('/api/hub/email/',{'otp':code,'role':'ADMIN'},format='json')
        self.assertEqual(result.status_code,200)
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.role,'CUSTOMER')
        self.assertEqual(self.customer.email,'new-address@example.com')

    def test_deactivation_blocks_active_trip_and_wrong_password(self):
        self.assertEqual(self.client.post('/api/hub/privacy/',{'password':'wrong'},format='json').status_code,400)
        self.create()
        self.assertEqual(self.client.post('/api/hub/privacy/',{'password':'Strong@12345'},format='json').status_code,400)
        Booking.objects.filter(customer=self.customer).update(status='CANCELLED')
        self.assertEqual(self.client.post('/api/hub/privacy/',{'password':'Strong@12345'},format='json').status_code,200)
        self.customer.refresh_from_db();self.assertFalse(self.customer.is_active)

    def test_map_proxy_is_user_triggered_cached_identified_and_validated(self):
        import io
        data=json.dumps([{'display_name':'Lucknow test location','lat':'26.8467','lon':'80.9462'}]).encode()
        with patch('hub.views.urllib.request.urlopen',return_value=io.BytesIO(data)) as call:
            first=self.client.get('/api/hub/map/search/?q=Lucknow')
            second=self.client.get('/api/hub/map/search/?q=Lucknow')
            self.assertEqual(first.status_code,200)
            self.assertEqual(first.data,second.data)
            self.assertEqual(call.call_count,1)
            self.assertIn('DriveMate',call.call_args.args[0].headers['User-agent'])
        self.assertEqual(self.client.get('/api/hub/map/search/?lat=91&lon=77').status_code,400)

    def test_in_app_trip_alert_preference_is_applied(self):
        pref,_=Preferences.objects.get_or_create(user=self.customer)
        pref.trip_updates=False;pref.save()
        before=Notification.objects.filter(user=self.customer).count()
        self.create()
        self.assertEqual(Notification.objects.filter(user=self.customer).count(),before)

    def test_known_user_cannot_get_another_users_data_or_profile(self):
        self.client.put('/api/hub/account/',{'name':'Changed rider','phone':'+919000001001','role':'ADMIN'},format='json')
        self.customer.refresh_from_db();self.assertEqual(self.customer.role,'CUSTOMER')
        result=self.client.get('/api/hub/privacy/')
        self.assertNotIn('password',result.data['user'])
        self.assertNotIn('code_hash',result.content.decode())

    def test_referral_is_real_registration_metadata_not_a_fake_wallet_reward(self):
        pref,_=Preferences.objects.get_or_create(user=self.customer)
        self.client.force_authenticate(user=None)
        response=self.client.post('/api/auth/register/',{'full_name':'Invited rider','email':'invited-v9@example.com','phone':'+919000001088',
          'password':'Strong@12345','confirm_password':'Strong@12345','role':'CUSTOMER','referral_code':pref.invite_code},format='json')
        self.assertEqual(response.status_code,201,response.data)
        code=re.search(r'\b(\d{6})\b',mail.outbox[-1].body).group(1)
        verified=self.client.post('/api/auth/verify-otp/',{'email':'invited-v9@example.com','otp':code},format='json')
        self.assertEqual(verified.status_code,200)
        self.as_user(self.customer)
        account=self.client.get('/api/hub/account/')
        self.assertEqual(account.data['referral_count'],1)
        self.assertNotIn('wallet_balance',account.data)

    def test_password_change_revokes_existing_access_token(self):
        token=str(RefreshToken.for_user(self.customer).access_token)
        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION='Bearer '+token)
        self.assertEqual(self.client.get('/api/hub/account/').status_code,200)
        self.customer.set_password('NewStrong@12345')
        self.customer.save(update_fields=['password'])
        self.assertEqual(self.client.get('/api/hub/account/').status_code,401)

    def test_foreign_business_profile_and_incomplete_guest_details_are_rejected(self):
        foreign=BusinessProfile.objects.create(owner=self.other,company='Not this customer')
        payload={'vehicle_id':self.car.pk,'service':'HOURLY','duration_hours':4,'pickup':'Sector 15 metro gate','business_id':foreign.pk}
        self.assertEqual(self.client.post('/api/rides/bookings/',payload,format='json').status_code,400)
        payload.pop('business_id');payload['passenger_name']='Guest without phone'
        self.assertEqual(self.client.post('/api/rides/bookings/',payload,format='json').status_code,400)

    def test_refresh_renews_active_session_but_cannot_revive_changed_password(self):
        refresh=str(RefreshToken.for_user(self.customer))
        self.client.force_authenticate(user=None)
        renewed=self.client.post('/api/auth/token/refresh/',{'refresh':refresh},format='json')
        self.assertEqual(renewed.status_code,200)
        self.assertIn('access',renewed.data)
        self.customer.set_password('ChangedSecret@12345');self.customer.save(update_fields=['password'])
        denied=self.client.post('/api/auth/token/refresh/',{'refresh':refresh},format='json')
        self.assertEqual(denied.status_code,401)

    def test_new_v9_booking_cannot_bypass_required_map_coordinates(self):
        payload={'vehicle_id':self.car.pk,'service':'HOURLY','duration_hours':4,'pickup':'Typed without map'}
        self.assertEqual(self.client.post('/api/rides/bookings/',payload,format='json').status_code,400)
        payload.update({'pickup_latitude':'28.4595000','pickup_longitude':'77.0266000','service':'OUTSTATION','duration_hours':8,'drop_address':'Destination without pin'})
        self.assertEqual(self.client.post('/api/rides/bookings/',payload,format='json').status_code,400)
