# Updated files / apply this patch

Extract this ZIP directly into the existing `updated_drivemate` project folder and choose **Replace files** when Windows asks. It contains only changed/new files, not the entire project.

## Included
- Supplied logo crop as app brand mark; branded splash then three swipe onboarding pages and slide-to-start.
- Premium dark charcoal + red UI across role choice, email signup/login, OTP, and initial dashboard.
- Animated local night-drive backdrop (illustrative animation, not an MP4 video); no external network asset needed.
- OTP sender uses SMTP settings when configured; otherwise remains console-only development mail.
- Corrects the Django registration constructor bug by removing the nonexistent `username` field.
- Adds Django initial account migration for clean installs.

## Enable OTP delivery by email (not Google OAuth)
Set in `backend/.env` using Gmail App Password (not normal Gmail password):
```env
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_HOST_USER=your-sender@gmail.com
EMAIL_HOST_PASSWORD=your-16-character-google-app-password
DEFAULT_FROM_EMAIL=DriveMate <your-sender@gmail.com>
```
Make a Gmail App Password after turning on Google 2-Step Verification. Restart Django after editing. Leave credentials unset only if you want development OTP in the server console. Keep `.env` private.

## After applying
Backend terminal: stop server with Ctrl+C, then from `backend` with `.venv` activated:
```powershell
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```
Frontend terminal:
```powershell
cd frontend
flutter pub get
flutter run -d ZA223BDMZP
```
Keep the physical phone's IP configured in `frontend/lib/config.dart`. If Android blocks local HTTP in debug, put `android:usesCleartextTraffic="true"` on the `<application>` element in `frontend/android/app/src/main/AndroidManifest.xml` (development only). For production use HTTPS and remove it.

Google OAuth is not included or needed; this uses email plus OTP. The background is a replaceable animated illustration, not an actual video file. Customer/driver profiles and booking workflow remain later feature increments.
