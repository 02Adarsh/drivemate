# DriveMate — Phase 1: Splash + role selection + email auth

A Flutter mobile app with a Django REST backend. This first increment intentionally implements only the entry/authentication flow; customer and driver dashboards/profile steps come next.

## Included
- Branded splash and original vector-style DriveMate mark (no image upload was present in the workspace).
- Role choice: Customer, Driver, Admin. Admin is sign-in only and is never granted by public signup.
- Email/password signup and login, email OTP verification, resend OTP.
- Django password hashing, JWT access/refresh tokens, rate limiting, validation, role separation.
- Development mode logs OTP to Django console. This is not real email delivery.

## Backend setup (Python 3.10+)
```bash
cd backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
copy .env.example .env   # Windows; macOS/Linux: cp .env.example .env
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```
The API defaults to development SQLite. For an Android emulator use `http://10.0.2.2:8000/api`; for a physical phone use your computer's LAN IPv4 address (same Wi-Fi), e.g. `http://192.168.1.20:8000/api`. Set `API_BASE_URL` in `frontend/lib/config.dart` accordingly. Allow port 8000 through the computer firewall if needed.

## Flutter setup and USB phone
Install Flutter SDK and Android Studio/Android SDK; enable Developer options > USB debugging on the phone, connect USB and accept the authorization prompt. From `frontend`:
```bash
flutter pub get
flutter devices
flutter run
```
For an installable debug APK: `flutter build apk --debug`; APK is at `build/app/outputs/flutter-apk/app-debug.apk`.

## Test
1. Start backend, then Flutter app.
2. Select Customer or Driver, choose Create account, use an email and password (min 8 chars).
3. Read the OTP in the backend terminal (DEVELOPMENT ONLY), enter it, then login.
4. Admin is sign-in only; create an admin using Django shell and set role to ADMIN, never by public registration.

## Production integration roadmap
- Replace console email with verified SMTP/provider in environment variables; configure SPF/DKIM and abuse controls.
- Google sign-in requires OAuth client IDs, Android SHA fingerprints and backend token verification; the button is intentionally marked as a future hookup and does not claim to authenticate yet.
- Use PostgreSQL via `DATABASE_URL`, HTTPS, secure secret management, production CORS, monitoring and account recovery before launch.
- Add subsequent features incrementally: driver personal profile, driving details, private documents and admin review, then customer vehicles and booking flow. Policies and eligibility rules must be reviewed for the launch jurisdiction.

## Folder layout
`frontend/` Flutter app. `backend/` Django REST API. See `.env.example` for backend settings.
