# DriveMate V21 — feature 5/5: Shopping / Errands Driver

Built incrementally on V20; commit V20 before applying this ZIP. Now or later, customer-owned car; destination optional. This is a driver service, not a shopping/delivery fulfilment service.

Admin: after backend deploy/migrations, open Django admin → Rides → Ride rates → Shopping / Errands Driver. Enter a base and hourly rate, then tick Enabled. The initial rate is disabled at zero; the admin form refuses to enable both zero. Fare is computed on the server as base + hourly rate × driver hours (1–14), not automatically measured or collected. Fuel, tolls, parking and extras are outside the estimate; confirm extras via support. Existing accepted estimates do not change when rates change. Future requests go to eligible online drivers immediately; matching is not distance-based and reservation isn't guaranteed. One active booking per customer/driver applies. No automatic payment is added.

Before production migration back up the actual PostgreSQL database and verify recovery. Render Free local uploads can disappear on restart/redeploy, so don't collect real driver documents until private durable storage is configured. Render Free database expiry and quotas still apply. The live database has not been migrated or modified by this package.

## One feature = one commit
First complete and commit V20. Merge V21 carefully into the existing project, preserving your secrets and any later local changes. From PowerShell (change author only when this person contributed; the email must be GitHub-verified):

```
cd C:\Users\adars\Downloads\updated_drivemate
git add backend/rides/models.py backend/rides/pricing.py frontend/lib/screens/book_driver_screen.dart frontend/lib/screens/driver_requests_screen.dart
git add frontend/lib/screens/explore_screen.dart frontend/pubspec.yaml frontend/test/support/api_fixture.dart frontend/test/v7_rides_test.dart
git add backend/rides/migrations/0010_alter_booking_service_alter_servicerate_service.py backend/rides/test_errands_service.py docs/UPDATE_V21_README.md
git --no-pager diff --cached --stat
git -c user.name="YuvrajKumar-005" -c user.email="Yuvrajkumar799129@gmail.com" commit -m "Add Shopping / Errands Driver service"
```

Review the staged diff before commit. Never stage `key.properties`, `.jks`, `.env`, `local.properties`, local databases or private uploads. If creating several ZIP commits, apply and commit **one version at a time**. Once backups are ready you can push the finished commits together with `git push origin main`; confirm Render runs migrations in order and check logs. New services must each be configured and enabled in Django admin. A production deployment can erase local uploads.

## Build APK
```
cd C:\Users\adars\Downloads\updated_drivemate\frontend
flutter build apk --release --dart-define=API_BASE_URL=https://drivemate-api-02adarsh.onrender.com/api
```
Use the same release keystore and install/test on a phone using dummy data. This is source, not an APK. The Android SDK/device and actual Render/PostgreSQL migration were not available to test here. Previous V17 ZIP accidentally included a sandbox `frontend/android/local.properties`; this ZIP excludes that file. Keep correct Windows-local SDK paths.

## Changed in this version
```
backend/rides/models.py
backend/rides/pricing.py
frontend/lib/screens/book_driver_screen.dart
frontend/lib/screens/driver_requests_screen.dart
frontend/lib/screens/explore_screen.dart
frontend/pubspec.yaml
frontend/test/support/api_fixture.dart
frontend/test/v7_rides_test.dart
backend/rides/migrations/0010_alter_booking_service_alter_servicerate_service.py
backend/rides/test_errands_service.py
docs/UPDATE_V21_README.md
```
