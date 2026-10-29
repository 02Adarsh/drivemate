# Run & test — VS Code commands (backend + Flutter on a USB phone)

Everything below is typed in the VS Code terminal (**Terminal → New Terminal**).
On Windows use Command Prompt or PowerShell; the commands are the same except
where noted.

---

## 1. Start the Django backend

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r requirements.txt

# create your environment file
copy .env.example .env        # Windows
cp .env.example .env          # macOS / Linux

python manage.py migrate
python manage.py seed_demo_data            # optional demo accounts (development only)
python manage.py createsuperuser --email admin@drivemate.in --full_name "Platform Admin"

python manage.py runserver 0.0.0.0:8000
```

* `createsuperuser` automatically gets the `ADMIN` role, which is what the app's
  admin sign-in expects.
* `runserver 0.0.0.0:8000` (not `127.0.0.1`) is what lets a phone reach it.
* Migration `0006` maps an older single `LICENSE` document to `LICENCE_FRONT`,
  so existing data is preserved.

Quick checks:

```bash
python manage.py test accounts -v 1     # 8 tests: signup, step gating, review, uploads
python manage.py check
```

---

## 2. Point the app at your computer

Open `frontend/lib/config.dart` and set the base URL.

**Option A — USB cable (recommended, no Wi-Fi needed)**

```bash
# with the phone connected and USB debugging allowed
adb reverse tcp:8000 tcp:8000
```

then in `config.dart`:

```dart
const String apiBaseUrl = 'http://127.0.0.1:8000/api';
```

`adb reverse` forwards the phone's port 8000 to your computer over the cable.
Run it again whenever you reconnect the phone.

**Option B — same Wi-Fi**

```bash
# Windows
ipconfig
# macOS
ipconfig getifaddr en0
# Linux
hostname -I
```

Set `apiBaseUrl` to `http://<that-ip>:8000/api`, add the same IP to
`ALLOWED_HOSTS` in `backend/.env`, and allow port 8000 in your firewall.

Android emulator: `http://10.0.2.2:8000/api`.
iOS simulator: `http://127.0.0.1:8000/api`.

> Cleartext HTTP is already allowed in `AndroidManifest.xml` for local
> development. Remove that flag when you have HTTPS.

---

## 3. Run the app on the phone over USB

Phone setup: **Settings → About phone → tap "Build number" 7 times** to unlock
Developer options, then **Developer options → USB debugging → on**. Connect the
USB cable and tap **Allow** on the phone prompt.

```bash
cd frontend
flutter pub get
flutter devices                 # your phone must appear here
flutter run                     # builds, installs and starts with hot reload
```

Install a standalone debug APK (no `flutter run` needed afterwards):

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If you have no `adb` on PATH, install "Android SDK Platform-Tools"
(or use Android Studio → Device Manager). `flutter doctor` tells you what is
missing.

Useful while developing:

```bash
flutter analyze                  # static checks
flutter test                     # 10 widget/unit tests
flutter clean                    # when a build behaves strangely
flutter run --release            # judge smoothness with this, not the debug build
flutter build apk --release      # installable, fast APK
```

> **Performance tip:** a `flutter run` debug build is JIT-compiled and feels much
> slower than the real thing. Always compare with `--release` before deciding the
> app is laggy. See `docs/PERFORMANCE_AND_ANIMATIONS.md` for what was optimised.

---

## 4. Walk through the flow

### Customer

1. Onboarding → **Log in / Create account** → **Rider**.
2. Create an account, read the 6-digit code in the **backend terminal**
   (development email backend prints it), verify.
3. Complete the rider profile (photo, address, city, emergency contact).
4. You land on the rider dashboard. Booking is the next build and is labelled as
   such on screen.

### Driver (all five steps)

1. **Create account** → switch to **Driver**.
2. **Step 2** — personal profile: photo, DOB (18+), address, city, emergency
   contact, languages.
3. **Step 3** — driving details: licence number + expiry, experience,
   at least one transmission and one vehicle type.
4. **Step 4** — upload licence front/back and identity proof (camera, gallery or
   PDF), accept the three consents, complete the three required training
   modules, then **Submit for verification**.
5. **Step 5** — status screen: `PENDING_REVIEW` with the five-step tracker.

Close the app and log in again at any point: the server tells the app which step
to open, so you always resume in the right place.

### Approve the driver

* Django admin → `http://127.0.0.1:8000/admin/` → **Driver profiles** → select →
  action **APPROVE selected driver applications** (or open Documents first to
  approve single files).
* Or set `AUTO_APPROVE_DRIVERS_IN_DEV=true` in `backend/.env` and restart the
  server to skip the manual step while testing.

Then press **Check verification status** in the app: the driver dashboard
switches to `Approved`. Going online and accepting bookings is the next phase.

---

## 5. Demo accounts (development only)

`python manage.py seed_demo_data` creates these (password `Demo@12345`):

| Account | Email | State |
|---|---|---|
| Customer | `rider@demo.drivemate.local` | profile complete |
| Driver | `driver@demo.drivemate.local` | APPROVED |
| Driver | `driver.pending@demo.drivemate.local` | PENDING_REVIEW |
| Driver | `driver.new@demo.drivemate.local` | INCOMPLETE (fresh) |

`python manage.py seed_demo_data --reset` recreates them. The uploaded
"documents" are placeholder images, not real licences.

---

## 6. Common problems

| Symptom | Fix |
|---|---|
| App shows "Cannot reach the DriveMate server" | backend not running, wrong IP in `config.dart`, or firewall. With USB, run `adb reverse tcp:8000 tcp:8000`. |
| `SocketException` / connection refused | start the server with `0.0.0.0:8000`, and add your IP to `ALLOWED_HOSTS` in `backend/.env`. |
| "Verify your email first" on login | read the OTP in the backend terminal (or set up SMTP). |
| OTP never arrives | development prints it to the terminal instead of sending email. |
| Driver is stuck on "Action needed" | open the status screen — the rejection reason from the admin is shown there. |
| Photo/file upload fails | 5 MB limit; JPG/PNG/WebP/PDF only. Fixed in v3: the app now sends the correct file type and the server checks the file's real content, so a normal photo is accepted. |
| "Allowed file types: jpg, png, webp" on the profile photo | You are running an older build. Update `frontend/lib/services/auth_service.dart` (content type) and `backend/accounts/security_views.py` (content sniffing) — both are in v3. |
| Back arrow does nothing | Fixed in v3: every step screen has an explicit back target, and the arrow never dead-ends. Update the `lib/` folder. |
| Text shows in a different font / appears late | Fixed in v3: Poppins is bundled in `assets/fonts` and declared in `pubspec.yaml`. Run `flutter pub get` after extracting. |
| Swipe-back gesture does nothing | It comes from the theme (`CupertinoPageTransitionsBuilder`). Make sure you extracted `lib/theme/dm_theme.dart` and ran a full rebuild (`flutter clean && flutter run`). |
| Phone can't install the APK | enable "Install via USB" in Developer options. |

---

## 7. Later: connecting the real services

Nothing below is required for today's build; each one is an isolated change.

| Service | Where to plug it in |
|---|---|
| Real email for OTP | `EMAIL_*` values in `backend/.env` (Gmail app password, SES, etc.) |
| PostgreSQL | `DB_*` values in `backend/.env` (the settings file already reads them) |
| Object storage for documents | swap Django `STORAGES` to S3/R2/GCS; the private-key layout stays the same |
| SMS OTP | add an `SmsService` next to `issue_otp()` and call it from the same place |
| Google / Apple sign-in | OAuth client IDs + a backend token-verification endpoint; the buttons say "(soon)" until then |
| Maps / GPS | a `MapService` abstraction is planned for the booking phase; the app never fakes coordinates |
| Payments (UPI/Razorpay/Stripe) | a `PaymentService` abstraction with a mock provider in development |
