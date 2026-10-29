> **V9.1 note:** the latest backend contract is API 10 and adds personal direct-UPI/manual confirmation. Use `DIRECT_UPI_PAYMENT.md` and the latest backend launcher. The V9 cash-only sections below describe the original V9 release.

# DriveMate V9 — implemented scope, setup and acceptance checks

**App 1.7.0+8 / API contract 9.** V9 contains all earlier update files. Install V9 over the existing project; do not stack older ZIPs on top of it.

Your selected integrations:

- **OpenStreetMap** map/pin selection, not Google Maps SDK.
- **Email OTP using your existing SMTP**; no SMS provider was selected.
- **Customer receives the trip code; assigned driver enters it.**
- **Cash/pay-after-trip**, not a card wallet or online gateway.

This is an Uber-inspired **DriveMate own-car driver platform**, not an exact copy of every Uber product. It does not provide Uber taxi/auto/moto/Eats, Uber One subscriptions, stored-value wallet top-ups, shared-family payment accounts, corporate expense-provider integrations or bank payouts. Those are not represented as fake working buttons.

## 1. What is implemented

| Area | Working behaviour |
|---|---|
| UI | New monochrome/light surfaces, blue navigation accent, new mark, Home–Services–Activity–Account composition, bundled Poppins with corrected theme/button font inheritance |
| Appearance | In-app Light/Dark toggle, persisted across restart; applies to auth, driver wizard and app screens, not just Account. Dark map tile rendering is client-side; attribution stays visible |
| Accessibility | Larger-text setting; English/Hindi core navigation/menu labels and Material controls. Some existing validation/help microcopy remains English |
| Authentication | Password login, emailed account verification, emailed login code, resend cooldown, password reset, verified email change with current-password confirmation |
| Email safety | Missing/failed SMTP returns an explicit error, not a false sent message. Signup rolls back on delivery failure. Codes are purpose-scoped, hashed, expiring, attempt-limited and one-use |
| Session security | Already-verified email alone cannot obtain tokens. Old/password-changed sessions are rejected; automatic refresh is pinned to the same backend. Server changes invalidate stale in-flight/login responses and cached account scope |
| Booking | Existing six own-car driver packages; time/duration; required map pickup pin (also validated by the V9 API); optional destination (required for outstation); account-owned car; guest/family contact; personal/business profile; claimed promotion; server-calculated quote |
| Map selection | Real OpenStreetMap tiles, explicit server-proxied search, tap a pin, optional current GPS, explicit reverse lookup and manual address confirmation. No fake autocomplete/nearby-driver pins |
| Driver request flow | Approved/available/capability filtering; real accept/decline, assigned trips, mandatory OTP start, complete, timeline and participant notifications |
| Driver contact | Actual assigned driver's mobile number shown after acceptance; tap opens OS dialer. No silent call and no CALL_PHONE permission |
| Trip-start code | Generated on acceptance, encrypted plus hashed at rest; customer-only read endpoint; email to customer; driver cannot retrieve it. No correct code = no ONGOING transition, including direct API requests |
| Code expiry | 20-minute code; customer can regenerate/resend. Five wrong guesses temporarily lock it. Regeneration invalidates the old value; start consumes it atomically |
| Location | Driver explicitly consents and grants location permission; GPS updates go to the assigned active booking. Customer sees position and last-update time. No simulated movement or fabricated ETA |
| Navigation | Driver can open pickup navigation in an external maps/browser app; this is distinct from the in-app OSM map provider |
| Activity | Upcoming/live and past tabs, actual driver/status/fare, start-code entry point, completed/cancelled history |
| Cash | Completion fixes the server quote as final ledger fare. Assigned driver separately confirms actual cash collection; confirmation is idempotent and customer is notified |
| Receipts | Participant-only PDF, phone share/save sheet, verified-recipient email, personal/business label and cash status. Unicode font bundled with its licence |
| Ratings | Completed-trip participants submit/update a 1–5 score and comment; one rating per author/trip, no prefilled fake rating history |
| Profile | Edit name/mobile, camera/gallery photo upload, private photo retrieval, verified email change, password reset |
| Garage | Server CRUD/default, active-booking edit/delete guard, read-only backend+account-scoped offline cache, explicit v6 local-car import |
| Saved places | Add/edit/remove Home/Work/Other locations with map coordinates and address; use saved pickup from Home |
| People/family | Add/edit/remove trusted people/emergency contacts, dial them and select a guest when booking. This is not a shared-money family wallet |
| Business | Owned company/department/employee profile metadata on trip records/receipts; foreign profiles are rejected |
| Promotions | Staff-created codes only; claim, expiry/usage checks, server-side discount (client cannot choose its amount), one use per customer/code unless cancelled before use |
| Invitations | Share an account invitation code and enter it at signup; actual verified referrals are counted. No automatic cash reward is promised |
| Safety | Mandatory start code information, assigned contact, trusted emergency people and explicit 112 dialer action. No automatic police/ambulance dispatch claim |
| Support | User-owned tickets, trip-linked categories, messages, real staff replies/close/reopen through the app; not a fake chatbot or guaranteed 24/7 service |
| Preferences | In-app trip-alert preference honoured by server; automatic emailed cash receipts can be switched off. Security codes remain mandatory |
| Privacy | Own-data export excluding auth secrets/private document files/start-code storage; password-confirmed account deactivation blocked while trips are active. Legal/support records are retained, not silently described as erased |
| Admin | Existing private document/application review; live booking counters/list; support inbox and responses. Promotions can be administered in Django admin |
| Phone tooling | Existing V8 ADB/USB/LAN safeguards retained; V9 backend version check; new backend launcher installs requirements, checks and migrates before starting |

## 2. Update your existing project

1. Back up the project and database.
2. Stop the old Flutter run and Django server.
3. Extract `drivemate_update_v9.zip` into `C:\Users\adars\Downloads\updated_drivemate`, overwriting files. Do not create nested `frontend/frontend` or `backend/backend` directories.
4. **Do not delete your database, .env, uploads, signing keys or virtualenv.** They are not in the archive.
5. V9 adds `cryptography` and `reportlab`, plus account/rides/hub migrations. Installing requirements before `migrate` is mandatory.
6. V9 asks you to sign in once again. Older access/refresh tokens lack the new revocation contract; your server account/cars/trips/documents are not deleted.

### Terminal 1 — backend (one line, leave running)

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_backend.ps1
```

Uses **your existing** `backend\.venv\Scripts\python.exe`. Installs the tested requirement versions, runs Django checks, applies the included migrations and starts `0.0.0.0:8000`. It stops on failure and never deletes data. After a successful first install, `-SkipInstall` avoids repeating dependency checks on every start.

Health URL on the PC:

```text
http://127.0.0.1:8000/api/health/
```

Response must include `"api_version": 9`. Health checks source reachability, not database correctness; the backend launcher does the migration step separately. The V9 phone launcher rejects an old V8/unversioned backend rather than pretending the new endpoints exist.

### Terminal 2 — connected phone (one line)

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

Your Motorola is already detected in the last successful ADB log. Keep it unlocked/authorized. The helper checks the selected device/backend, verifies `adb reverse`, runs pub get, and targets the actual phone. Package-update notices are informational; first Android builds may download additional SDK/Gradle artifacts.

For multiple phones, add `-DeviceId` with a real serial from `adb devices -l`. Each USB phone needs its own reverse mapping. Do not paste a fictitious serial.

If the app retained an old custom URL: **Login → Server connection → reset/change** to the trusted working backend. A runtime pin intentionally overrides build defaults. See `V8_PHONE_CONNECTION.md` for LAN/manual APK setup and Windows/OEM-driver diagnosis.

### Tested development stack

- Flutter **3.47.7**, bundled Dart **3.13.5** (matches the Dart version in your pub log).
- Python **3.13.16** in this sandbox; code is intended for your Python **3.12** environment too.
- Tested backend package versions are pinned in `backend/requirements.txt` (Django 5.2.18, DRF 3.18.3, SimpleJWT 5.5.1, cryptography 46.0.7, ReportLab 4.5.1, plus CORS/dotenv).
- Flutter dependency lock is included. Node.js is not needed.
- Native map/location/dialer/share plugins need a compatible Android SDK/JDK/Gradle setup; keep the current Flutter 3.47 Android template/tooling. Do not blindly downgrade plugins or upgrade the entire SDK when seeing a package-update notice.
- **No actual Android APK build, Motorola GPS/camera/dialer run or live SMTP delivery was performed in this Linux sandbox.** Widget/platform calls are mocked where required. Rebuild and perform the device checklist below on your PC.

## 3. Email OTP / SMTP

You selected **SMTP ready**. Your local `backend/.env` is deliberately preserved, not embedded in the ZIP. V9 uses those existing settings.

Relevant variable names (keep your real values private):

```dotenv
EMAIL_HOST=smtp.example.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_HOST_USER=your-real-sender@example.com
EMAIL_HOST_PASSWORD=your-private-app-password
DEFAULT_FROM_EMAIL=DriveMate <your-real-sender@example.com>
```

These are configuration names/examples, not live credentials. Use the actual settings for your provider. The default console/dummy backend is **not** reported as real email delivery in V9. A correctly accepted SMTP send can still land in Spam/bounce later; check Inbox/Spam and your provider's delivery logs.

- Registration and login codes are account secrets—never share them.
- The **trip-start code** is separate: show/share it only with the assigned driver when you meet.
- Password-reset codes cannot be used as login codes, and consumed codes cannot be replayed.
- Email change requires your current password plus a code sent to the new address.
- A password change revokes old access/refresh sessions.
- A receipt is emailed only to the authenticated participant's verified address, never a client-supplied arbitrary recipient.

## 4. Two-phone acceptance walkthrough

Use a real verified customer and an approved driver on the same backend; do not operate a real paid journey solely on the basis of these development tests.

1. **Customer:** sign in (password or emailed login code), open Account → Your vehicles, add a car.
2. Toggle Light/Dark on Home or Account → Appearance; restart to confirm persistence.
3. Account → Saved places → Add place. Search explicitly or tap an OSM pin; confirm an address and save Home/Work.
4. Optionally add a trusted person and an owned business profile. Operator may create a promotion in Django admin; customer claims it under Promotions.
5. Home/Services → Book. Choose package, valid duration, time, pickup pin/address, destination pin for outstation, car and review.
6. **Driver:** go online (approval/current-licence/capability rules still apply), open Requests and accept.
7. **Customer:** open Activity/trip. Actual driver name and phone appear; tap the number and confirm the OS dialer opens. No automatic call is made.
8. Customer sees the protected six-digit trip-start code; configured SMTP also sends it to the customer—not the driver.
9. **Driver:** Start trip → enter an incorrect code. Status must remain ACCEPTED. Enter the customer's correct code; only then may status become ONGOING.
10. If code expired, customer uses Regenerate/resend. Five wrong guesses temporarily lock it. Do not share an account-login/reset code instead of a trip code.
11. Driver may opt into live location from the trip screen. Grant phone Location permission and inspect the foreground notification/settings. Customer sees position plus last-update time. Turn sharing off and confirm updates stop; do not expect invented movement.
12. Driver completes only when the drive is finished. Cash is still DUE/unconfirmed.
13. After actual collection, driver opens the receipt and confirms cash received. Repeat requests do not duplicate the record. Customer sees the record on refresh.
14. Participants open/share/save the PDF or email their own receipt. It is a cash/trip record, **not a GST invoice or bank-transfer proof**.
15. Rate the completed trip; changing the rating updates the existing author/trip record.
16. Create a linked payment/trip support ticket. Staff opens Account/Home → Support inbox, replies and closes/reopens it; owner sees the response.
17. Test profile/photo/email-change flows. Email change must not replace the email before its code is verified.
18. Invite another user with the displayed code at signup; only actual verified referrals count. No fake money/reward is credited.
19. Privacy export excludes password hashes/start-code storage/private document contents. Deactivation requires a current password and no active booking.

With one phone, you can switch between customer/driver accounts to exercise server state; location testing needs a device that has the relevant permission. Server state survives app restarts.

## 5. Maps, navigation and location boundaries

- OSM is the selected provider. Google Maps SDK, Places SDK and Google Cloud billing keys are not used.
- Search/reverse lookup uses Nominatim through the authenticated backend. It is **explicit button/pin lookup**, not keystroke autocomplete or bulk geocoding. Results are cached; a global two-second request slot and per-user rate limit are applied.
- `GEOCODING_USER_AGENT` identifies the app. Follow OSM/Nominatim usage and privacy policies. Typed searches are sent to the geocoding provider; do not enter secrets in map searches.
- OSM attribution is visible and links to copyright information. Do not bulk prefetch/scrape map tiles or remove attribution. Production-scale traffic needs an appropriate hosted/self-hosted tile/geocoding service and shared rate-limit/cache infrastructure, not unlimited reliance on community endpoints.
- A live Nominatim lookup for the city Lucknow returned HTTP 200 during verification. This is not a future uptime guarantee. If lookup is unavailable, tap a map pin and confirm the address manually; no fabricated suggestion is shown.
- Driver navigation opens an external maps/browser app. In-app OSM display is not a complete turn-by-turn/traffic/ETA engine.
- Location sharing is opt-in, participant-scoped and tied to an active assigned trip. The driver location stream is cancelled when the trip completes or its screen is disposed. Android foreground-service configuration improves continuity when switching apps, but the OS may stop it; keep the trip screen active for reliable tests.
- Killing the app, denying location, switching accounts, poor GPS or missing network can stop updates. The customer sees last-update time; stale/missing positions are not represented as current movement.
- There is no background push/FCM, automatic accident detection, guaranteed nearest-driver dispatch or public live-trip-tracking website in this build. Share trip details sends a user-selected static summary, not a fake live URL.
- OTP prevents the **app/API trip-start transition**. It does not physically immobilize a customer's car or guarantee that a person will obey instructions.

## 6. Account/payment/service boundaries

- Cash mode means **manual collection records**. No bank/UPI/card charge, stored-value wallet, automatic payout or refund is performed.
- Final ledger fare equals the server quote; pricing remains configurable base + hourly rate with service minimums. It does not measure actual distance/driving time, waiting, surge, tolls or GST. Operator must configure lawful commercial pricing before launch.
- One live booking per customer and one assigned/running trip per driver remain beta constraints, including scheduled requests. This is not a multi-reservation dispatch calendar.
- History/feed/export lists are bounded (up to 60 trip-history rows, 40 offers, 100 saved collection/ticket rows, 200 export trips). Full enterprise pagination/reporting is not claimed.
- Family/people entries are account-owned contacts/guest details, not linked teen/senior accounts or shared payment authorizations.
- Business profiles are owned receipt metadata, not company reimbursement or expense-provider integrations.
- Coupons must be created by actual staff; discounts are calculated by the backend, not trusted from the client.
- Invitations record a verified referral; they do not promise or transfer a cash reward.
- Help tickets need your platform staff to respond. The app does not invent support replies or run a 24/7 emergency control room.
- Deactivation disables login and retains necessary support/legal history. It is not advertised as instantaneous erasure of all data.

## 7. Security/deployment notes

- New migrations: accounts email-code purposes, rides OTP/location/cash/rating fields, and `hub` account tools. Apply included migrations; do not regenerate/delete them on the user's machine.
- Trip code hash + encrypted retrievable ciphertext; only owning customer can read/regenerate. Driver/admin trip payloads contain no raw code/hash/ciphertext. Old-code regeneration and single-use start are enforced server-side.
- Role, ownership, car/business ownership, participant file access, status transitions and cash confirmation are server checks.
- Email/login failures are explicit. No verified-email-only token minting; password changes and disabled accounts cannot be revived through refresh.
- Session refresh retries one authenticated 401 on the same pin. It does not loop or forward credentials/old payloads to fallback hosts after a server switch.
- Private uploaded documents/photos/receipts are not public storage URLs. No secrets are in the ZIP. Keep `DJANGO_SECRET_KEY` stable/private; production DEBUG=false rejects short/placeholder keys.
- Before real customer data/paid operation: HTTPS (remove unrestricted Android cleartext), secure device-token storage, strong secrets, hardened/private storage/backups, monitoring, distributed throttling/cache, data-retention rules, licences/insurance, staff procedures and applicable financial/privacy/legal review are required. A development test suite is not a production safety certification.

## 8. Verification artifacts

- `flutter analyze`: clean.
- **94 Flutter tests**, including prior regressions plus V9 theme/map/code/dialer/contact/business/cash UI and session-refresh boundaries.
- **65 Django API/model tests**, including OTP expiry/attempt/replay/role boundaries, email-purpose separation, registration rollback, session revocation, owned CRUD, promotion maths, location privacy, cash idempotence, PDF/email receipts, support scope, referrals and the two-driver acceptance race.
- **85 PowerShell assertions** under PowerShell 7.4.6 with ADB/network/Flutter mocked; Windows 5.1-compatible source. Native phone hardware/Windows execution is not claimed.
- Fresh/upgrade migration and packaged-archive integrity checks are performed separately before delivery.
- `docs/previews/v9_home_light.png`, `v9_home_dark.png` (and Account preview if included) are actual Flutter widget renders with test fixtures, not photos of a physical-phone run or seeded production data.
