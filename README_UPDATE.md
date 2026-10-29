# DriveMate — update notes

Extract the zip into your existing `drivemate` folder (overwrite when asked).
Nothing was deleted, so an overwrite-merge is safe.

---

# v9.1 — driver receiving UPI + final-fare QR (manual confirmation)

**App 1.7.1+9 / API 10. Latest ZIP includes V9 and all older updates.**

You chose **personal direct UPI / manual confirmation**, paid to the driver.

## Added

- Driver Account -> **Receiving UPI & QR**: own UPI ID + gallery/camera receiving
  QR upload, password re-authentication and own-account attestation.
- Server decodes the image and rejects a mismatched ID/random/web QR. A QR/ID
  match is labelled as such; **bank ownership is not verified**.
- At completed-trip payment, a NEW QR is generated from the **server final fare**
  and receiving profile snapshot. Customer cannot submit/edit the invoice amount;
  uploaded QR old amount/reference and client-supplied receiver/amount are ignored.
- Customer/driver trip/receipt -> **Pay / view UPI QR** or **Show fare QR / review**.
  Same-phone Open UPI app and QR share/save are available. Payer authorizes in their
  UPI app; DriveMate never collects a UPI PIN or silently debits an account.
- Customer “I paid” records an **unconfirmed report** only. Assigned driver checks
  their OWN actual bank credit, enters received amount/reference and acknowledges
  the check. Wrong amount cannot become a paid record. Typed UTR/screenshot/app
  return is not independent verification.
- Cash/UPI records cannot both be confirmed; reference reuse, duplicate updates,
  participant privacy, immutable payee snapshots and audit records are enforced.
- Receipts/activity distinguish **UPI received — manually confirmed by driver**
  from cash. Optional email goes to the verified participant, not an arbitrary address.

## Important limit — do not mistake personal QR for a merchant gateway

**Amount is read-only in DriveMate and prefilled in QR/UPI intent. The external
UPI app MAY still allow editing.** We cannot force every bank/UPI app to disable
that control with a personal receiving ID. There is **no automatic bank/gateway
verification** in this selected mode. Strict bank-enforced amount-lock and
single-use verified QR payments require an approved merchant-provider integration.
Old personal QR images also remain payable at the bank after in-app closure or
confirmation. Check for prior debit/credit; never repeatedly pay/collect twice.
Closing the app record is NOT a bank cancellation/refund.

## Update/run

Back up first, stop old processes, extract the latest ZIP into the existing
`updated_drivemate` project and overwrite. Database/.env/uploads/.venv/signing
files are excluded. **Do not delete your database.** New QR/image dependencies
and the payments migration require backend setup first (Python 3.12+).

Terminal 1 (one line, leave running):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_backend.ps1
```

Terminal 2 (one line, authorized phone connected):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

Backend health must show API 10; the new app/launcher reject the older API 9.
No merchant key is needed for personal/manual mode. Existing SMTP and V9 OTP,
map, theme, account and support features remain included.

Full receiving setup, payment/driver-review walkthrough and limitations:
**`docs/DIRECT_UPI_PAYMENT.md`**. V9 feature/reference guide remains included.

## Verification

- **102 Flutter tests**, analyze clean (94 previous + 8 direct-UPI tests).
- **81 Django tests** (65 previous + 16 direct-UPI tests), no pending migrations.
- **85 mocked PowerShell assertions**, parser check for backend launcher.
- Real QR PNG encode/decode, image/ID mismatch, amount snapshot, unconfirmed
  customer report, driver-only exact-amount receipt, reference reuse, cash/UPI
  exclusivity and private access tested. Upgrade/source ZIP checks follow.
- No real bank transaction/UPI-app payment or actual Windows phone run is executed
  by this sandbox. Manual confirmations are human assertions, not bank facts.

---

# v9 — new Light/Dark UI, real map booking, mandatory start OTP and account tools

**App 1.7.0+8 / API 9. V9 contains all previous updates; install V9 only.**

Your choices are implemented as **OpenStreetMap + existing SMTP email + customer
trip code/driver verification + cash/pay-after-trip**. This is an Uber-inspired
DriveMate own-car driver app, not every product in Uber's global catalogue.

## What is new and wired

- Completely refreshed **Home / Services / Activity / Account**, monochrome
  surfaces with blue accent, new mark, corrected bundled Poppins font inheritance,
  and **app-wide persisted Light/Dark** (auth/wizard screens included).
- OSM map search/pin/GPS selection, saved Home/Work places and required pickup
  confirmation. Explicit, cached, rate-limited Nominatim lookups; attribution kept.
- **Mandatory trip-start code:** issued on driver acceptance, customer-only read,
  emailed to customer, encrypted + hashed at rest. Driver must enter the correct
  code; missing/wrong/expired/used code cannot start the trip on the API. Resend,
  attempt lock and regeneration are implemented. No raw code in driver payloads.
- Actual assigned-driver phone shown; tapping **opens the OS dialer**, not an
  automatic call. Optional private profile photo retrieval uses authenticated APIs.
- Opt-in driver GPS/location permission; participant map + last-update time;
  pickup navigation opens an external maps/browser app. No fabricated ETA/movement.
- Cash completion/confirmation records, protected PDF/share/email receipts and
  completed-trip ratings. No card wallet/top-up/bank charge or transfer is claimed.
- Account-owned profile/photo/email/password, garage, saved places, people/family
  contacts, guest booking, business metadata, operator promotions, invitation codes,
  notification/receipt preferences, support tickets/staff replies, own-data export
  and password-confirmed deactivation (active-trip guard).
- Working email-code login as well as password login. Account-code purposes cannot
  be cross-used/replayed. Missing/failed SMTP is an explicit failure; signup rolls
  back instead of reporting a fake send.
- Session security/revocation and same-server refresh for longer trips. Old/stale
  responses cannot reattach a session after switching backend. **Sign in once after
  upgrading**; server cars/trips/documents are not deleted.
- Admin verification is preserved; support/booking tools use real backend data.
  All displayed new menu entries open implemented forms/actions, not placeholder
  OAuth or fake-balance toasts. Unconfigured Google/Apple sign-in buttons removed.

## Install and run (important: new Python dependencies/migrations)

Back up first, stop the old app/backend, extract over the existing project and
replace files. **Do not delete db.sqlite3, .env, uploads, signing keys or .venv.**
The ZIP excludes them. V9 adds cryptography/ReportLab and account/rides/hub
migrations, so use the new backend launcher before running the phone app.

Terminal 1 — backend (one line; leave running):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_backend.ps1
```

Terminal 2 — phone (one line; detected/authorized Motorola connected):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

The first command uses the existing backend virtualenv, installs pinned tested
requirements, checks and migrates, then starts the server. The second retains
all V8 ADB safeguards and rejects an old backend without API contract 9. After
the first successful backend setup, `run_backend.ps1 -SkipInstall` is available.
A saved custom app server URL still overrides a source/build default: reset/change
it under Login/Account -> Server connection if necessary.

Full feature matrix, SMTP configuration names, two-phone checklist, map/location
privacy, security and limits: **`docs/V9_FEATURES_AND_RUN.md`**.

## Verified / honest boundaries

- **94 Flutter tests pass**, `flutter analyze` clean (low-memory runner uses
  `--concurrency=1`). Tests cover code/dialer/map/appearance/cash/account flows and
  same-server refresh boundaries.
- **65 Django API/model tests pass**, no pending migrations; source/data upgrade
  and package-integrity checks are performed before delivery.
- **85 PowerShell assertions** with mocked ADB/network/Flutter; syntax targets
  Windows PowerShell 5.1, tested helper runtime 7.4.6. Actual Windows execution,
  Android APK build/device GPS/camera/dialer and live SMTP delivery were not tested
  in this Linux sandbox.
- Live Nominatim city lookup returned HTTP 200. External service uptime is not
  guaranteed; map-pin/manual address confirmation remains available.
- Preview PNGs in `docs/previews/` are actual Flutter widget renders with **test
  fixtures**, not a physical-device run or seeded production trips.

Cash records are not bank settlements/GST invoices. GPS sharing is permission-
based and may stop if the OS kills the app; last-update time is shown. OTP locks
**app/API start**, not the physical vehicle. No automatic nearest-driver dispatch,
FCM/background push, accident/emergency control room, multi-reservation calendar,
Uber One/Eats/taxi/moto/shared-wallet/corporate-provider parity is claimed. Existing
one-live-booking/one-assigned-trip beta limits remain. Read the guide before any
real customer data or paid deployment; legal/safety/HTTPS/operational hardening
is still required.

---

# v8 — phone connection fix, safe launcher and in-app server settings

**Version 1.6.0+7. V8 includes V7; install only the V8 ZIP for the latest code.**
The original `drivemate_update_v7.zip` remains a separate unchanged archive.

## Your current blocker

Your backend health response was OK, but `adb devices` had **no device rows**.
The ADB daemon startup was normal. Windows did not have an authorized physical
Android target. A ZIP cannot repair a cable/USB-driver/debugging setting; V8
reports the exact state and does not pretend that `adb reverse` succeeded.

## New in V8

- **`tools/run_phone.ps1 -Usb`**: one guarded launcher. Detect phone -> verify
  backend -> reverse/verify the selected serial -> pub get -> run on that exact
  phone. Missing/unauthorized/offline/multiple-device and backend failures stop
  before Flutter. No accidental desktop/emulator target.
- **LAN**: uses an UP **physical** private-network adapter with a default gateway;
  VirtualBox/host-only/VPN addresses are excluded. Multiple valid adapters require
  an explicit `-LanIp`; it does not guess the first `192.168.*` entry.
- **No ADB alternative**: `-Lan -BuildApk` builds an APK for manual installation.
  Building needs no connected phone; using it still needs phone-to-PC LAN access.
- **Login and Account -> Server connection**: enter/test/save a trusted URL without
  editing Dart. Correct DriveMate health JSON is required; HTTP 400/404, another
  app's 200, HTML and redirects do not count as healthy.
- Credentials are sent only to the selected server. Sessions/custom URLs are
  pinned; changing the server clears the login, and stale login responses cannot
  restore it. Garage cache is backend + account scoped. **V7 users sign in once
  after upgrading**, because old tokens had no recorded server pin. Server data
  is not deleted.
- Explicit UTF-8 source writes and a build-time `API_BASE_URL` define. A saved
  runtime server pin takes precedence until changed/reset in the app.
- V7 garage/booking/trip/admin/notification/ledger features remain included.

## Run now

Extract V8 into the existing project, overwrite files, keep your database/.env.
Back up first. Stop old processes, then Terminal 1 (one line, leave running):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate; if ($LASTEXITCODE -eq 0) { .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 }
```

Phone unlock + USB debugging ON + known data cable + authorize the prompt.
Check the ADB list with this exact installed path:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

Once an actual serial shows `device`, Terminal 2 (one line):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

Do **not** use the old `connect_phone.ps1; cd frontend; flutter ...` chain:
PowerShell semicolons continue even when an earlier external command fails.

No USB? The current IP from your log was `10.26.0.206`. After permitting this
exact host in `backend/.env` ALLOWED_HOSTS and restarting Django, build via LAN:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Lan -BuildApk -LanIp 10.26.0.206
```

If your IP changed, use the new physical adapter IP. Output:
`frontend\build\app\outputs\flutter-apk\app-release.apk`. Transfer/install it
manually, test `/api/health/` **on the phone**, then use app Server connection.
Setting LAN alone cannot make `flutter run` find a nonexistent ADB device.

Full troubleshooting, .env host example, narrow firewall guidance, multiple-phone
selection, SDK notes and safety limits: **`docs/V8_PHONE_CONNECTION.md`**.

## Verification

- Flutter 3.47.7 / Dart 3.13.5: **75 tests pass**, analysis clean.
- Django 5.2.18: **40 tests pass**, no new V8 migration/dependency.
- **83 PowerShell assertions** under 7.4.6 using mocked ADB/network/Flutter.
  Source is written for Windows PowerShell 5.1 compatibility; real Windows 5.1
  hardware execution and Android APK build were not available in this sandbox.
- ZIP is source/tooling, **not an APK or a phone USB driver**. No GPS/radius
  dispatch, background push or real payments/settlements were added.

---

# v7 — booking beta: requests, trips, synced garage and real server ledger

**App version: 1.5.0+6.** The v6 photo UI/dark-red brand is kept. This release
connects previously prototype-only screens to the new Django `rides` app.

## What changed

- **Garage:** account-owned vehicles on the server; CRUD/default handling; per-user
  read-only offline cache. Old v6 cars need an explicit **They are mine** import
  confirmation; they are never silently attached to a different login.
- **Customer booking:** five validated steps → server request → Activity/detail.
  Server-owned fares, required own car/pickup, service minimums, future scheduling,
  outstation destination validation and a retry key that prevents duplication.
- **Driver availability:** online/offline is persisted on the server. Only approved,
  online, suitably skilled drivers can accept. Expired licences cannot take new work.
- **Driver inbox:** accept/decline really work. My trips → Start → Complete (with
  confirmation). Controls are near the top, not hidden below the timeline.
- **Timeline and notifications:** real state events; in-app inbox, mark-read/read-all,
  and tap-to-open booking. Visible detail/request pages poll every 8 seconds and
  stop on background/disposal. No background push or instantaneous-delivery claim.
- **Earnings:** today/week/lifetime/chart from completed bookings. **Ledger only,
  not settled or paid funds.** Completed fare equals the quote in this beta.
- **Admin:** existing verification queue remains live; open/active booking counters
  and booking-list access are added. Read-only booking/event inspection in Django
  admin prevents silent edits that bypass the transition audit.
- **Guards:** one live booking/customer and one assigned trip/driver; role/ownership
  checks; request contact/plate redaction before assignment; atomic transitions and
  database constraints; immutable car snapshots; suspension forces offline.

## Required install step

Extract over the existing project and overwrite files. The archive does **not**
contain `.env`, `db.sqlite3`, uploads, virtualenvs or caches. Back up first and
**do not delete your database**. Included migrations are applied with `migrate`;
you do not need `makemigrations`.

Terminal 1 — backend, leave running (one line):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate; if ($LASTEXITCODE -eq 0) { .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 }
```

Terminal 2 — USB phone + rebuild (a separate terminal, one line):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -ExecutionPolicy Bypass -File .\tools\connect_phone.ps1 -Usb; cd frontend; flutter pub get; flutter run --release
```

USB debugging/authorization must be enabled. Multiple devices need an explicit
ADB serial. Full setup, demo steps, API map, pricing and troubleshooting:
**`docs/V7_BOOKING_ENGINE.md`**. No new runtime dependency or Node.js requirement.

## Optional demo — development only

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django seed_demo_data --with-rides
```

Only with DEBUG=true. Customer `rider@demo.drivemate.local`, approved driver
`driver@demo.drivemate.local`; password **Demo@12345**. This explicitly seeds demo
bookings/history and puts only the demo driver online. Fake documents/data are
labelled; without `--with-rides`, the seed keeps its old accounts-only behaviour.

## Verification / scope

- **44 Flutter tests pass** (25 existing + 19 new), `flutter analyze` clean.
- **40 Django tests pass** (11 accounts + 29 rides, including a two-driver race).
- Fresh-database migration/seed and v6-overlay checks; ZIP integrity verified.
- Tested toolchain: Flutter 3.47.7 / Dart 3.13.5 / Django 5.2.18.
- No physical-phone run or APK build was performed here; rebuild on your machine.

**Not shipped:** GPS maps/radius matching, nearest-driver dispatch, background
push, trip OTP, real payment collection, bank/UPI settlement, refunds or invoices.
This is a capability-filtered beta request board, not geographically restricted
production dispatch. There is no guaranteed ETA and no money is charged/moved.
One live booking per customer also limits scheduled requests. Do not operate
real paid journeys on this build; production safety/payments/hardening are later work.

---

# v6 — poora naya UI (Uber-style feel), photos, aur saare features khule

## 1. Naya design language

* **Photos:** 6 nayi images app ke andar bundled hain (`assets/images/`) - a
  verified chauffeur, airport kerb, highway, city drive, night drive aur driver
  portrait. Sab app ke andar hain (koi internet download nahi), total ~440 KB.
* **Naye components:** `lib/widgets/dm_ui.dart` - photo hero cards, photo tiles,
  search bar, segmented filter tabs, option rows, info rows, step rail, avatar,
  copy rows aur ek honest bar chart. `lib/theme/dm_surfaces.dart` - card/sheet
  decoration helpers (ek hi jagah se poora look).
* Cards ab content ke hisaab se **badhte hain** - lamba text kabhi card se bahar
  nahi nikalta (ye bug test se pakda gaya tha aur fix hua).

## 2. Saare features dashboard se khule

**Customer — 4 tabs: Home / Explore / Activity / Account**

| Screen | Kya kaam karta hai |
|---|---|
| Home | Search bar, photo hero, "Popular right now" carousel, aapki gaadi, how-it-works |
| Explore | 6 services with photos, why-DriveMate, safety centre links |
| **Book a driver** | 5-step flow: service → timing + duration → pickup/drop + notes → car → review. Continue **disabled** rehta hai jab tak step poora na ho. Estimate `base + per-hour × hours` se live calculate hota hai. Aakhir mein honest screen: matching abhi live nahi hai |
| **Your vehicles** | Add / edit / remove / set-default; registration, fuel, transmission, seats validation. **Device par save** hota hai (screen ye saaf likhta hai) |
| Activity | Bookings + garage strip + safety links |
| **Safety centre** | 112 / 100 / 1091 / 1073 / 108 / 14567 - tap karke copy |
| Account | Profile, role, driver status, garage, support, build info, log out |

**Driver — 4 tabs: Home / Requests / Earnings / Account**

* Home: Online–Offline switch (approval tak locked), application card with photo,
  today's snapshot, quick actions (requests, earnings, documents, training)
* **Requests:** sample request preview (clearly "SAMPLE", accept/decline mock) -
  asli matching live nahi hai, screen ye batata hai
* **Earnings:** real zeros, 7-day bar chart, how-you-get-paid steps, incentives
  aur payout clearly `SOON` marked

**Admin — 3 tabs: Home / Queue / Account**

* **Verification queue ASLI hai:** server se applications aati hain
  (`GET /api/auth/admin/drivers/`), search + status filters (All, Pending review,
  Under review, Approved, Rejected, Suspended), tap par poori application -
  profile, 6 step pills, per-document review, aur **Approve / Reject / Suspend**
  buttons (reason mandatory, server enforce karta hai).
* Home par live counters (pending / approved) real API se.

## 3. Naye API methods (app side)

`lib/services/auth_service.dart`: `adminDrivers`, `adminDriverApplication`,
`adminReviewDriver`, `adminReviewDocument` - Django panel wale hi endpoints.

## 4. Naya local storage

`lib/services/vehicle_store.dart` - garage device par SharedPreferences mein
(`dm_vehicles_v1`). Pehli gaadi automatic default ho jaati hai.

## 5. Tests

* App: `test/dashboard_test.dart` (4 tests) + `test/v6_ui_test.dart` (5 tests) +
  purane 16 = **25 tests, all passing**; `flutter analyze` clean.
* Backend: **11 tests OK**.
* ⚠️ Purana `frontend/test/dashboard_test.dart` is zip se **overwrite** ho jaata
  hai - usme v4 dashboard ke purane assertions the, isliye usko replace karna
  zaroori hai.

## 6. Chalane ka tareeka (wahi, kuch nahi badla)

```powershell
# Terminal 1 - backend
cd C:\Users\adars\Downloads\updated_drivemate\backend; .\.venv\Scripts\Activate.ps1; python manage.py migrate; python manage.py runserver 0.0.0.0:8000
```
```powershell
# Terminal 2 - app (naya terminal)
cd C:\Users\adars\Downloads\updated_drivemate\frontend; flutter pub get; flutter run --release
```

`pubspec.yaml` badla hai (nayi photos) isliye **`flutter pub get` zaroori** hai,
aur chunki assets badle hain `flutter run --release` se rebuild karein.

---

# v5 — "Cannot reach the DriveMate server" ka pakka fix

## 1. App ab khud sahi server address dhoondh leti hai

Pehle: `config.dart` mein ek IP likha tha. Wi-Fi badla, hotspot badla, ya router
restart hua → IP badal gaya → app "Cannot reach the DriveMate server" dikhane lagi.

Ab: app **start hote waqt** (splash par) teen addresses try karti hai aur jo
jawab de usi par chali jaati hai:

1. `config.dart` ka `apiBaseUrl` (aapka LAN IP),
2. `http://127.0.0.1:8000/api` — USB cable + `adb reverse tcp:8000 tcp:8000`,
3. `http://10.0.2.2:8000/api` — Android emulator.

* Naya file: `lib/config.dart` mein `apiFallbackBaseUrls` + `apiProbeTimeout`.
* `lib/services/auth_service.dart`: har request par addresses failover ho jaate
  hain, jo chala wo yaad rakha jaata hai (`AuthService.activeBaseUrl`).
* Dead address 4 second mein skip ho jaata hai — screen freeze nahi hoti.
* Error message ab batata hai **kaun-kaun se address try kiye gaye** aur kya karna hai.

## 2. Naya health endpoint (10-second diagnosis)

```
GET /api/health/   ->   {"status": "ok", "service": "drivemate-api", "time": "..."}
```

Phone ke Chrome mein `http://<PC-IP>:8000/api/health/` kholiye:
chal gaya = network theek, problem app address mein tha. Nahi chala = firewall /
Wi-Fi / server band (detail: `docs/FIX_CANNOT_REACH_SERVER.md`).

## 3. Helper script — `tools/connect_phone.ps1`

```powershell
cd C:\Users\adars\Downloads\updated_drivemate
powershell -ExecutionPolicy Bypass -File tools\connect_phone.ps1 -Usb
```

Ye: backend check karta hai → LAN IP batata hai → `adb reverse` tunnel banata hai
→ `config.dart` ko `127.0.0.1` par set karta hai → agla command batata hai.
(`-Lan` flag se same-Wi-Fi wala address set hota hai.)

## 4. Tests

* Backend: `test_health_endpoint_is_public_and_reachable` → **11 tests OK**.
* App: `test/api_config_test.dart` (address order/dedupe) → **18 tests pass**,
  `flutter analyze` clean.

---

# v4 — clean dashboard, back arrow fixed properly, superuser command

## 1. Back arrow fixed at the root (this one is the real fix)

**Cause found:** the top-left arrow on **login, register, OTP and forgot-password**
was wired to `Navigator.maybePop(context)`. `maybePop` **silently does nothing**
when there is no screen underneath — and those screens are opened with
`pushClean` / `pushReplacement` after sign-in, so there was often nothing
underneath. Result: a dead arrow that no amount of tapping could fix.

**Fix:**
* New `lib/widgets/dm_back_button.dart` — `DmBackButton`. It runs an explicit
  action if given, otherwise pops, otherwise **replaces the screen with a
  fallback** (login → introduction pages, register → login, OTP → login,
  forgot-password → login). It can never be dead.
* `goBackOr()` also gained a `result` argument, and `DmScreen` gained
  `backResult` + `PopScope`: the **phone's own back button / gesture** now does
  the same thing as the arrow (no more "back closes the app" surprises).
* Registration steps 2–4 pop back with `true`, and the dashboard refreshes
  itself when a step reports a change.
* Driver step 2 and step 3 now **restore your saved details** from the server
  when you reopen them, so going back and forth never means retyping.
* Login screen was missing the `onboarding_screen.dart` import entirely — that
  alone made its arrow point at a class that did not exist.
* New `test/back_button_test.dart` (3 tests) locks all of this down.

## 2. Dashboard v4 — cleaner + fully animated (same theme)

* New `lib/widgets/dm_dashboard.dart`: greeting header, hero card with a
  **completion ring**, online/offline card, earnings card, stat tiles,
  quick-action tiles, list rows and empty states — all on the existing
  navy/red Poppins theme.
* **Driver:** status ring (x/6 steps), honest status card (approved / under
  review / action needed / suspended), Online–Offline switch (locked until
  approval), earnings preview marked `SOON`, at-a-glance stats, quick actions
  (documents, training, application, safety) and a recent-requests empty state.
* **Customer:** "Book a driver" hero with trust chips, 6 service tiles,
  vehicles empty state, recent bookings, safety centre.
* **Admin:** review-console card with the live Django endpoints.
* Bottom navigation now switches tabs with a fade+slide (no rebuild jank) and
  the Profile tab shows your account, role, driver status, support and log out.
* Nothing is faked: every number is either real API data or clearly labelled
  "SOON".

## 3. Createsuperuser (admin) — one line

```powershell
$env:DJANGO_SUPERUSER_PASSWORD="Admin@12345"; python manage.py createsuperuser --noinput --email admin@drivemate.in --full_name "Platform Admin"
```

* `create_superuser` sets `is_staff`, `is_superuser`, `is_active`,
  `role=ADMIN` and `email_verified=True` automatically.
* Interactive version (asks for the password): `python manage.py createsuperuser --email admin@drivemate.in --full_name "Platform Admin"`
* Admin panel: `http://127.0.0.1:8000/admin/` → driver verification queue lives
  at `/admin/accounts/driverprofile/`.

## 4. Backend bug fixed on the way

`GET /api/auth/profile/` for a **customer** referenced request data that does
not exist on a GET (`if 'pincode' in data`), so the customer profile endpoint
raised a 500. The check now lives only in `PUT`, and
`test_profile_get_works_for_both_roles` protects it. Backend suite: **10 tests, all green**.

## 5. Two-terminal run (Windows)

Terminal 1 — backend (keep it running):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; .\.venv\Scripts\Activate.ps1; python manage.py migrate; python manage.py runserver 0.0.0.0:8000
```

Terminal 2 — app (VS Code **+** for a new terminal):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\frontend; flutter pub get; flutter run --release
```

Full troubleshooting (adb PATH, USB debugging, Wi-Fi instead of USB):
`docs/RUN_WINDOWS_2_TERMINALS.md`.

---

# v3 — upload fix, back button fix, state/city/PIN, dark theme, animations, speed

## 1. Image upload fixed (the "Allowed file types: jpg, png, webp" error)

**Cause:** Flutter's `MultipartFile.fromPath` sends no content type, so every
photo arrived at the server as `application/octet-stream` and was rejected.

**Fix (both sides, so it cannot come back):**
* App: `lib/services/auth_service.dart` now derives the real MIME type from the
  file extension (jpg/jpeg/png/webp/heic/heif/gif/pdf) and sends it.
* Server: `backend/accounts/security_views.py` verifies the **file's own bytes**
  (JPEG/PNG/WebP/PDF/GIF/HEIC signatures) instead of trusting the header, so a
  generic content type no longer blocks a perfectly good photo — while a
  disguised `.exe` is still rejected.
* New backend test proves both directions.

## 2. Back arrow always works

After OTP verification the navigation stack is cleared, so `Navigator.maybePop()`
had nothing to pop and the arrow looked dead.

* `DmScreen` gained `onBack` / `backFallback`.
* Step 2 → driver dashboard, step 3 → step 2, step 4 → step 3, step 5 → dashboard.
* Login/OTP/forgot-password/role screens all have a sensible back target.
* Steps are now **pushed** (not replaced), so back and swipe-back return to the
  previous step with its data intact.

## 3. State → City → PIN code in registration

* All 28 states + 8 union territories with their cities
  (`lib/data/india_locations.dart`).
* Pick a **state** first; the **city** dropdown unlocks and lists only that
  state's cities (searchable sheet, opens at the current selection).
* **PIN code** field with 6-digit validation (cannot start with 0).
* Added to the driver's step 2 **and** the rider profile screen, and enforced on
  the server: `state`, `city` and `pincode` are now required for profile
  completeness (`missing_fields` tells the app exactly what is left).
* Migration `0007_profile_state_pincode` adds the columns (old rows keep working;
  incomplete profiles are simply asked for the new fields).

## 4. Darker, richer theme

Background `#080A0D → #05070A`, cards `#14171D → #0F1318`, borders and secondary
surfaces deepened, accent tuned to `#F2403F`. Login/register keep the same
screenshot layout: deep near-black with a red glow, night-drive banner on login
only. Full table in `docs/PERFORMANCE_AND_ANIMATIONS.md`.

## 5. No more lag

| Cause | Fix |
|---|---|
| `google_fonts` downloaded Poppins at runtime | **Poppins is bundled** in `assets/fonts` (OFL) and the dependency was removed — text paints on the first frame |
| A looping scale animation repainted the whole background every frame | Backgrounds are static and wrapped in `RepaintBoundary` |
| The 1376 px JPEG was decoded at full size | `cacheWidth` decodes at screen resolution |
| Per-item timers for staggered animation | One controller per item with an `Interval` delay — no stray timers, no rebuild churn |

Also: run **`flutter run --release`** when judging smoothness — a debug build is
JIT and always feels slower. See `docs/PERFORMANCE_AND_ANIMATIONS.md`.

## 6. Animations + swipe back everywhere

* Swipe-from-edge **back gesture** on Android and iOS (theme-level
  `CupertinoPageTransitionsBuilder`) with a smooth slide transition on every route.
* Staggered fade + slide-up entrance on every form field, step header and
  dashboard card.
* Press-scale feedback on cards, chips and the photo picker.
* Cross-fade when content swaps (steps, status).
* Pulsing indicator for the live verification status.
* All durations 110–380 ms; nothing animates forever except that tiny pulse.

## 7. OTP to the user's real email — full guide

New document: **`docs/OTP_EMAIL_SETUP.md`**. Short version:

```env
# backend/.env
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_HOST_USER=yourgmail@gmail.com
EMAIL_HOST_PASSWORD=your16characterapppassword   # Google app password, not your login password
DEFAULT_FROM_EMAIL="DriveMate <yourgmail@gmail.com>"
```

Restart the server — settings switch from the console backend to SMTP
automatically. Test without the app:

```bash
python manage.py shell
>>> from django.core.mail import send_mail
>>> send_mail('DriveMate SMTP test', 'It works!', None, ['you@example.com'], fail_silently=False)
```

For production use a transactional provider (Brevo/SendGrid/SES/Resend) with
**SPF + DKIM + DMARC** on a verified domain — the guide covers the errors you can
hit and the SMS-OTP extension point.

## 8. Tests

* Backend: **9/9** (`python manage.py test accounts`) — includes the new
  content-sniffing upload test and PIN code validation.
* Flutter: **10/10** (`flutter test`) — splash, login, register, slide-to-start,
  location data, and a phone-sized test that walks the state → city → PIN flow.
  It also caught a real overflow bug in the primary button (long labels now
  shrink instead of overflowing).
* `flutter analyze`: clean.

## Files changed in v3

```
frontend/pubspec.yaml                                   (fonts, http_parser)
frontend/assets/fonts/*.ttf + OFL.txt                   (new, bundled Poppins)
frontend/lib/theme/dm_theme.dart                        (darker palette, fonts, swipe-back)
frontend/lib/widgets/dm_animations.dart                 (new)
frontend/lib/widgets/dm_select_field.dart               (new: searchable dropdown)
frontend/lib/widgets/dm_screen.dart                     (back handling)
frontend/lib/widgets/auth_backdrop.dart                 (static, cached)
frontend/lib/widgets/hero_band.dart                     (cached image)
frontend/lib/widgets/dm_buttons.dart                    (label overflow fix)
frontend/lib/data/india_locations.dart                  (new: states + cities)
frontend/lib/utils/validators.dart                      (PIN code)
frontend/lib/services/auth_service.dart                 (upload content type)
frontend/lib/services/navigation.dart                   (goBackOr, dmRoute)
frontend/lib/screens/*.dart                             (step 2 profile, back targets, animations)
frontend/test/locations_test.dart                       (new)
backend/accounts/models.py + migrations/0007_*           (state, pincode)
backend/accounts/progress.py                            (state/pincode rules)
backend/accounts/views.py                               (validation + payloads)
backend/accounts/security_views.py                      (content sniffing)
backend/accounts/tests.py                               (new tests)
backend/accounts/management/commands/seed_demo_data.py  (demo profiles updated)
docs/OTP_EMAIL_SETUP.md                                 (new)
docs/PERFORMANCE_AND_ANIMATIONS.md                      (new)
docs/RUN_AND_TEST.md                                    (release-mode + troubleshooting)
```

## Commands after extracting

```bash
# backend
cd backend
python manage.py migrate                    # applies 0007 (state + pincode)
python manage.py runserver 0.0.0.0:8000

# app (new dependency + fonts, so a clean fetch is required)
cd ../frontend
flutter clean
flutter pub get
flutter run                                 # or: flutter run --release
```
