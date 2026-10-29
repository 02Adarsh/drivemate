# DriveMate V17 — Feature 1/5: Outstation Getaways

Built on V16. This adds a separate **Outstation Getaways** service for a driver to drive the customer's own car on a multi-day trip. Start and return date/time, destination pin, and the customer's expected **total driver hours** are required. Estimate is computed on the server as `base + per_hour × entered hours`; the hours are not automatically measured. The existing one-live-booking constraint applies, and requests are sent to eligible drivers immediately even for future trips. Drivers need the existing outstation skill. This is not a guaranteed reservation, shift scheduler, actual-hours tracker, automatic expense settlement, or payment collection.

The customer pays fuel, tolls, parking and driver stay/food separately; the app discloses these costs are outside the estimate. Return must be on a later calendar day, at most 31 days after start, and entered hours must be 1–744 and not exceed the rounded-up trip duration. A long trip's estimated fare must fit the database's monetary limit. Changing rates does not recalculate existing bookings.

## Admin must configure it before customers can book
After the backend deploy and migration, open Django admin → **Rides → Ride rates → Outstation Getaways**. Set the base and per-hour rupee amounts and tick **Enabled**. A newly installed migration creates this rate **disabled** with zero values, so there is no unintended free booking. The admin form rejects enabling it when both amounts are zero. The pricing endpoint hides disabled services; the server also rejects attempts to book them. Other service rates gain an Enabled toggle and stay enabled by default.

## Update and deploy carefully
1. Compare/apply only the V17 files listed below into the existing V16 project. Avoid overwriting later local work. Do not delete or upload `.env`, databases, uploads, `frontend/android/key.properties`, or the signing keystore. This ZIP includes no such secrets.
2. Back up the production database before schema changes and verify a recovery plan. Render free local files are ephemeral: a deploy/restart can lose uploads. Do not use real driver documents until private durable storage is set up. Free PostgreSQL expiry/limits still apply.
3. Commit these V17 files on top of the already-committed V16:

```
backend/rides/admin.py
backend/rides/models.py
backend/rides/pricing.py
backend/rides/serializers.py
backend/rides/views.py
backend/rides/migrations/0006_booking_return_at_servicerate_enabled_and_more.py
backend/rides/test_getaway.py
frontend/lib/screens/book_driver_screen.dart
frontend/lib/screens/booking_detail_screen.dart
frontend/lib/screens/driver_requests_screen.dart
frontend/lib/screens/explore_screen.dart
frontend/lib/services/rides_service.dart
frontend/pubspec.yaml
frontend/test/support/api_fixture.dart
frontend/test/v7_rides_test.dart
docs/UPDATE_V17_README.md
```

4. Render must deploy the backend change and run `python manage.py migrate` against the actual Render PostgreSQL database. If auto-deploy is on, the commit may trigger it; check the deployment logs for migration success. Do not run local SQLite migration and assume Render was updated. Existing Render build previously recommended: `pip install -r requirements.txt -r requirements-cloud.txt gunicorn whitenoise && python manage.py collectstatic --noinput && python manage.py migrate`, when root directory is `backend`. Check current actual settings first; keep any additional existing commands.
5. Set and enable the rate in admin, then build a signed release APK using the same keystore as prior releases:

```
cd C:\Users\adars\Downloads\updated_drivemate\frontend
flutter build apk --release --dart-define=API_BASE_URL=https://drivemate-api-02adarsh.onrender.com/api
```

APK output: `frontend\build\app\outputs\flutter-apk\app-release.apk`. Install/update and test with dummy customer, car, and outstation-qualified driver. An earlier install signed with another key or in another phone profile can block updates; back up local data before uninstalling anything. Android SDK was unavailable in the build workspace, so no APK or physical-device/Render/PostgreSQL migration was tested here. Full automated run: 90 Django tests on SQLite, 123 Flutter tests, Flutter analyze clean. The new migration preserves the existing SQLite rate audit trigger after table rebuild.

## V17-only Git staging example (assuming V16 already committed)

```
cd C:\Users\adars\Downloads\updated_drivemate
git add backend/rides/admin.py backend/rides/models.py backend/rides/pricing.py backend/rides/serializers.py backend/rides/views.py backend/rides/migrations/0006_booking_return_at_servicerate_enabled_and_more.py backend/rides/test_getaway.py
git add frontend/lib/screens/book_driver_screen.dart frontend/lib/screens/booking_detail_screen.dart frontend/lib/screens/driver_requests_screen.dart frontend/lib/screens/explore_screen.dart frontend/lib/services/rides_service.dart frontend/pubspec.yaml frontend/test/support/api_fixture.dart frontend/test/v7_rides_test.dart docs/UPDATE_V17_README.md
git diff --cached --stat
git commit -m "Add multi-day outstation getaways"
git push origin main
```

Review staged changes and author before committing. For attribution to another genuine contributor, use their verified GitHub email with `git -c user.name="..." -c user.email="..." commit ...` for that commit; this does not require sharing passwords and does not prove identity.
