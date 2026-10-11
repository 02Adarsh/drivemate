# DriveMate Step 2 patch — apply to existing project

This ZIP contains only changed/new files. Extract into the existing `updated_drivemate` root folder and approve **Replace files**.

## What this update does
- Replaces the welcome/role page after onboarding with the login screen; signup has a Rider / Driver selector. No public Admin selector.
- Login/signup visuals follow the supplied charcoal + red reference, with animated transitions and a cinematic dark-road background image that gently pans/zooms. This is an animated still, not an MP4 video.
- Removes Apple option. Google button is intentionally inert as requested; no message or redirect. It does NOT provide Google authentication.
- Signup: name, email, phone, password, confirm password, and terms checkbox. Email OTP is still server-side SMTP when configured.
- OTP success enters profile onboarding. Customer can save address, city, emergency contact. Driver gets personal profile (DOB/18+ guard, address, city, emergency contact) then driving details (licence number/expiry, years, skills, languages, intro).
- Profiles persist to Django. Password remains Django-hashed; role comes from the selected signup option and profile endpoints require JWT authentication.

## Apply backend migration
Stop Django with Ctrl+C, then from `backend` with `.venv` active:
```powershell
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```
This applies `accounts.0002` (phone and role profile tables). Do not delete/reset the DB if you already have data.

## Apply Flutter update
In another terminal:
```powershell
cd frontend
flutter pub get
flutter run -d ZA223BDMZP
```
Keep your phone's IP in `frontend/lib/config.dart`. If you regenerated Android platform files already, keep them; use dev-only `android:usesCleartextTraffic="true"` in the application tag if needed for local HTTP.

## Important feature boundaries
Email OTP works via SMTP after Gmail App Password is configured in local `backend/.env`; without it OTP stays in the development backend console. The included Google button deliberately does nothing per the requested behavior. Forgot-password, profile photo upload, and private driver document file upload/admin approval are not included in this increment. Driver profile remains `INCOMPLETE` until its separate document-verification step; filling personal/driving fields does not approve or make a driver online. Review DOB/eligibility and onboarding policy for your jurisdiction before launch.
