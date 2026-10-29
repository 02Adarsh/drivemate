# DriveMate V18 — Feature 2/5: Wedding / Event Driver

Adds a separate Wedding / Event Driver option to Services and the booking flow. The customer requests a driver for their own car, selects a future start date/time, pickup pin, duration (1–14 hours), and may add destination and notes. An approved available driver can see the event start time before accepting. The server computes the estimate from that service's admin-managed base and hourly amounts; customer-supplied prices are ignored. This is a request, not a guaranteed reservation or automatic payment. Requests are visible immediately even for a future event; the existing system allows only one active booking per customer/driver. Fuel, tolls, parking and other extras are not included; confirm extras through support.

## Configure the rate
After deploying backend migrations, open Django admin → Rides → Ride rates → Wedding / Event Driver. Enter the base and hourly rate and tick Enabled. The migration creates the service rate with both amounts zero and Disabled; enabling it with both amounts zero is rejected. While disabled it is not offered for booking and the server refuses direct booking requests. Existing booking estimates remain unchanged when rates are edited. All existing services, including V17 Outstation Getaways, remain separate.

## Before V18: commit the earlier uncommitted frontend files
The earlier GitHub push 88fd8d7 contained only four V16 files; V17 was later pushed in 4b18b9b. Some V12 resume flow, V13 release signing, and V15 logo files were still only on the Windows laptop. With V17 already pushed, first check `git status --short` and `git diff --cached --stat`. If anything unexpected is staged, inspect it before committing. After checking that the files exist and contain the intended updates, stage them without including secrets:

```
cd C:\Users\adars\Downloads\updated_drivemate
git add frontend/android/app/build.gradle.kts frontend/android/app/src/main/AndroidManifest.xml
git add frontend/android/app/src/main/res/mipmap-mdpi/ic_launcher.png frontend/android/app/src/main/res/mipmap-hdpi/ic_launcher.png frontend/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png frontend/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png frontend/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
git add frontend/android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png frontend/android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png frontend/android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png frontend/android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png frontend/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png frontend/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml frontend/android/app/src/main/res/values/ic_launcher_background.xml
git add frontend/lib/screens/driver_application_status_screen.dart frontend/lib/screens/driver_documents_screen.dart frontend/lib/screens/profile_setup_screen.dart frontend/lib/screens/splash_screen.dart frontend/lib/screens/session_resume_screen.dart frontend/lib/services/navigation.dart frontend/lib/services/session_resume.dart frontend/test/policy_display_test.dart frontend/test/session_resume_test.dart
git --no-pager diff --cached --stat
git commit -m "Add registration resume, release signing and app icon"
git push origin main
```

Use the actual contributor's verified GitHub email in `git -c user.name="..." -c user.email="..." commit ...` if attributing a commit to that person. Never commit `frontend/android/key.properties`, `.jks`/`.keystore`, `.env`, local database files, uploads, or `frontend/android/local.properties`.

**Correction:** earlier V17 ZIP accidentally included `frontend/android/local.properties` containing a sandbox Flutter SDK path. V18 deliberately excludes it. If V17 extraction overwrote the Windows file, check it locally; Flutter/Android Studio can regenerate it with the Windows Flutter and Android SDK paths. Do not copy the sandbox path or upload local.properties.

## Apply, stage and deploy V18 as a distinct commit
Apply V18 only after committing prior pending files. Compare/merge carefully so later local edits aren't overwritten. From the root of the existing V17 project, the V18 changed files are:

```
backend/rides/admin.py
backend/rides/models.py
backend/rides/pricing.py
backend/rides/serializers.py
backend/rides/views.py
backend/rides/migrations/0007_alter_booking_service_alter_servicerate_service.py
backend/rides/test_event.py
frontend/lib/screens/book_driver_screen.dart
frontend/lib/screens/driver_requests_screen.dart
frontend/lib/screens/explore_screen.dart
frontend/pubspec.yaml
frontend/test/support/api_fixture.dart
frontend/test/v7_rides_test.dart
docs/UPDATE_V18_README.md
```

Commands:

```
cd C:\Users\adars\Downloads\updated_drivemate
git add backend/rides/admin.py backend/rides/models.py backend/rides/pricing.py backend/rides/serializers.py backend/rides/views.py backend/rides/migrations/0007_alter_booking_service_alter_servicerate_service.py backend/rides/test_event.py
git add frontend/lib/screens/book_driver_screen.dart frontend/lib/screens/driver_requests_screen.dart frontend/lib/screens/explore_screen.dart frontend/pubspec.yaml frontend/test/support/api_fixture.dart frontend/test/v7_rides_test.dart docs/UPDATE_V18_README.md
git --no-pager diff --cached --stat
git commit -m "Add wedding and event driver service"
git push origin main
```

Backup and verify recovery for the production database before schema migrations. Render auto-deploy may run after push: check its logs and ensure `python manage.py migrate` succeeds against the actual production PostgreSQL database. Enable and set the Wedding rate after migration. Render free local uploads are ephemeral: redeploy/restart can erase them; do not collect real driver documents until private durable storage is ready. Free PostgreSQL expiry and service limits remain applicable.

Build the APK with the same release keystore on Windows:

```
cd C:\Users\adars\Downloads\updated_drivemate\frontend
flutter build apk --release --dart-define=API_BASE_URL=https://drivemate-api-02adarsh.onrender.com/api
```

Install and test using dummy data. This ZIP is source, not an APK. Android build/device tests and Render/PostgreSQL migration were not run here. Automated tests: 94 Django tests on SQLite, 125 Flutter tests, Flutter analyze clean. Price audit trigger preservation checked by the backend tests.
