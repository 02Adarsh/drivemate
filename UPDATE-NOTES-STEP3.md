# DriveMate Step 3 — updated files only

Extract this archive into the existing project root `updated_drivemate` and choose **Replace files**. This is a patch archive; it does not contain the entire Flutter/Android scaffold.

## Changes
- Fixed onboarding slider: drag anywhere on the full slider track; reaching the end opens Login with a slide+fade route. PageView uses animated page transitions.
- Login/Register visual refresh based on the new reference, custom DriveMate logo, red/black cinematic night-road image with subtle slow parallax, Rider/Driver selector on login and signup. No Administrator option in the public mobile UI. Google button intentionally stays on the same page with no action; no Apple button.
- Animated signup/login switch and page routes; rider/driver signup includes required name/email/phone/password/confirm/terms.
- Email OTP, profile setup with required photo and required fields; driver DOB under 18 is blocked, driving details require values and at least one capability.
- Driver documents (licence + identity, PDF/JPG/PNG/WebP up to 5 MB) upload to private local storage. Admin reviews in Django `/admin`; private download link requires admin session. Both docs approved + complete profile are required for driver APPROVED state.
- Email OTP password reset request + confirm endpoints and UI.

## Apply updates
Stop Django with Ctrl+C. From `backend` in active `.venv`:
```powershell
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```
The new `accounts.0003` migration adds profile photo and reviewer data. Keep the existing database; do not delete it.

In another PowerShell window:
```powershell
cd frontend
flutter pub get
flutter run -d ZA223BDMZP
```
Keep your existing `frontend/lib/config.dart` phone IP and local Android platform directory.

## Admin review
Create an admin once:
```powershell
cd backend
python manage.py createsuperuser
```
Sign in at `http://127.0.0.1:8000/admin/`. Open Driver documents, use the secure download link, set each document to APPROVED or REJECTED and save. Both required document records must be approved and the profile complete for the driver profile to become APPROVED. This is a local Django admin verification console, not yet an in-app admin dashboard.

## Email delivery
SMTP OTP/password reset sends to the user only if the private `backend/.env` has Gmail SMTP settings with a fresh App Password; revoke any App Password previously pasted into a chat and create a new one. Do not add `.env` to the archive. Without SMTP credentials this prototype prints messages in the backend console.

## Boundaries
Private uploads use local `private_uploads/` storage in development and have no public media URL. Production should replace it with private object storage, scan uploads, enforce retention, HTTPS, jurisdiction-specific documents and review policies. The cinematic background is a slowly animated image, not a video. Google button is purposefully inert per request. UI files were syntax parsed and Django checks/migrations validated; build/run on the user's installed Android SDK to confirm device/plugin configuration.
