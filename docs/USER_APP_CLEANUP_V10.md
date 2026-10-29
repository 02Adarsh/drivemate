# DriveMate V10 — user-facing text cleanup

## What changed
- Removed/reworded prototype/development text on booking, onboarding, training, verification, earnings, support and account screens. Removed obsolete placeholder support email from the verification screen and point users to in-app support.
- Error and email messages no longer show end users local computer, USB, SMTP or source-code setup commands.
- The server-connection menu is retained in debug/profile builds for development, and hidden from login and account in release builds. This is a presentation change, not a security boundary.
- Demo/sample accounts and bookings remain clearly labelled as **not real**. Safety, PIN, direct UPI and manual payment warnings remain. No automatic payment or settlement was added.
- Policies are currently unavailable notices; no terms or privacy policy have been invented. The app still has registration/consent flows: **do not distribute it as a real service until actual terms, privacy policy and verification consent have been reviewed and added, and the consent flows have been reviewed**. Training consists of brief acknowledgements; get real training content before making stronger claims.

## Before a public APK or Render launch — still required
1. Set up the production backend and database on Render (or Azure where required). Deploy with `DEBUG=false`, a private random Django secret, HTTPS, allowed hosts, production email/OTP provider and persistent private storage. Render deployment is not performed in this update. Render local disk can be ephemeral; do not rely on it for the database or uploads.
2. Configure the Flutter release build using the **real HTTPS** API base ending in `/api`, for example `flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-RENDER-HOST/api` after replacing YOUR-RENDER-HOST. Current default is `127.0.0.1`; without a real build-time URL the installed user APK will not reach Render. Test the actual health endpoint and full flow first. Do not distribute this example as-is.
3. Android currently allows cleartext HTTP in `frontend/android/app/src/main/AndroidManifest.xml` and the release build currently uses the **debug signing key** and `com.example.drivemate` application ID (`frontend/android/app/build.gradle.kts`). These must be fixed and tested for a production release, including secure key backup and an appropriate application ID. A release-signed APK was not built here.
4. Provide genuine legal policies, applicable support details, staff review procedures, driver verification and meaningful training before onboarding users. Current driver approval does not enforce approval of each document; staff must check document statuses manually.
5. Test a release APK on real devices: registration/OTP, customer and driver login, uploads/downloads, booking, review, support, cash and manual UPI, network failure and HTTPS. Verify payment details in the UPI app and never claim calculated 18% is a settled transfer.
6. Test with production-like security settings, review logs/backups, use a proper database firewall and private storage, and complete the project submission requirements documented in `docs/submission/PROJECT_STATUS_HINDI.md`.

## Local run (Windows)

Back up existing data. Merge ZIP contents without replacing `.env`, existing database, `private_uploads` or `.venv`. If upgrading from a version before V9, run migrations once:
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate
```

Backend (terminal 1):
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 --noreload
```

Phone via USB (terminal 2):
```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

Tests: 85 Django backend tests passed on SQLite in this workspace. Flutter SDK was not available, so Flutter analyze/build/device testing was not run.
