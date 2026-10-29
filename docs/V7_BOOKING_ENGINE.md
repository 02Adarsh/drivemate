# DriveMate v7 — Booking beta

DriveMate books a **driver who drives the customer's own car**. This is not a taxi/car-dispatch app.

v7 keeps the v6 dark/red photo UI and connects the garage, bookings, driver availability, request inbox, trip controls, timeline, in-app notifications and earnings ledger to Django.

## 1. Install over your existing project

1. Stop the old Flutter run and Django server.
2. Back up your project/database before any update.
3. Extract `drivemate_update_v7.zip` into `C:\Users\adars\Downloads\updated_drivemate`, replacing files when asked. `frontend` and `backend` must merge with those existing folders, not become nested inside them.
4. Your `.env`, `db.sqlite3`, uploaded files and virtual environment are **not in the ZIP**. They are not overwritten. Do not delete your database or rerun `makemigrations`; this release includes the migrations.
5. Start the backend with the command below, then rebuild the app. Hot reload is not a substitute for a rebuild.

### Terminal 1 — backend (leave this running)

Run this **one line**, not a Markdown link or a terminal prompt:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate; if ($LASTEXITCODE -eq 0) { .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 }
```

Uses your existing `.venv`; no new backend dependency was added. If that virtual environment does not exist, use the environment guide in `docs/RUN_AND_TEST.md` before starting.

### Terminal 2 — USB phone + app

Turn on **USB debugging**, connect the cable and accept the phone's authorization popup. Then:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -ExecutionPolicy Bypass -File .\tools\connect_phone.ps1 -Usb; cd frontend; flutter pub get; flutter run --release
```

The helper locates `adb`, creates `adb reverse tcp:8000 tcp:8000`, and sets the app URL to `http://127.0.0.1:8000/api`. Run the helper again after unplugging/reconnecting the cable. With multiple devices connected, select the device explicitly with `adb -s SERIAL reverse tcp:8000 tcp:8000` and `flutter run -d SERIAL --release` (replace `SERIAL` with an ID from `adb devices` / `flutter devices`).

**If using two phones:** both must reach the same backend. ADB reverse must be set on each phone, or use the same Wi-Fi/LAN server address on both. For LAN instructions and the health check, see `docs/FIX_CANNOT_REACH_SERVER.md`.

### Environment verified for this release

- Flutter **3.47.7**, with its bundled Dart **3.13.5**. Do not install an unrelated Dart SDK for Flutter.
- Django **5.2.18**; automated backend tests ran with Python **3.13**. The code remains compatible with your Python **3.12** environment.
- Keep your Flutter SDK's `bin` on Windows PATH. Use `flutter --version`, `flutter doctor -v` and `flutter devices` to check the existing setup.
- Android Studio/Android SDK and platform-tools are needed to build/install on Android. First dependency downloads need internet; the bundled app photos/fonts do not.
- Node.js is **not required** for this Django + Flutter update.
- Verification here covers analysis, widget/API tests and clean migrations. No Android APK build or physical-phone run was performed here.

## 2. What works now

### Customer

- **Home / Explore → Book a driver:** service, duration, now/scheduled arrival, pickup, optional destination/notes, an account-owned car, then review and submit.
- Each step blocks Continue until valid. Outstation requires a destination; scheduling requires a future date/time; duration obeys the selected service's server minimum.
- The server creates the booking and calculates its quote. The client sends **no price** and cannot override the customer/driver role.
- **Activity:** ongoing/upcoming and history from the server. Tap a booking for its assigned driver, contact-copy control, vehicle snapshot, quote/final ledger fare and timeline.
- **Garage:** add/edit/delete/set default, synced across devices. Live-booking cars cannot be edited/deleted (the default flag can still change).
- **Notifications:** booking sent, driver assigned, trip started, completed or cancelled. Tap a notification to mark it read and open the linked booking.
- Cancel a REQUESTED or ACCEPTED booking with a reason. A running/completed trip cannot be cancelled in this beta.

### Driver

- **Online/Offline** is saved to the server, not just a visual switch. Approval does not put a driver online automatically.
- Approval + current licence + availability + driving capabilities determine which requests can be taken. A manual car requires manual capability; night/outstation requests require those capabilities.
- **Requests → Open requests:** car type, pickup, service, duration, quoted fare and projected driver ledger amount. Accept assigns the driver; decline hides it from that driver's feed, leaving it available to others.
- **My trips:** assigned/running/history. Tap a trip; **Start trip / Complete trip** controls are near the top. Completing requires confirmation.
- **Earnings:** today, this week, lifetime, seven-day chart and completed trips, calculated from completed bookings. These are ledger amounts, **not paid balances**.
- A suspended driver cannot take/start new work. An already running assigned trip may still be completed, so it is not stranded in progress.

### Admin

- The existing live verification queue still works. Revoking approval also forces availability offline.
- Home adds open-request/active-trip counters and opens the server booking list.
- Django admin adds Rides & bookings. Bookings, fares, timestamps and events are inspection/read-only there; use the API for transitions so audit history is not bypassed.

## 3. Status flow and limits

```text
REQUESTED → ACCEPTED → ONGOING → COMPLETED
     ↓          ↓
  CANCELLED  CANCELLED
```

- At most **one live booking per customer** and **one assigned/running trip per driver**, including scheduled requests. This is a deliberately limited beta, not a scheduling calendar.
- Acceptance uses a conditional database update inside a transaction. Partial unique constraints enforce the one-live-booking/trip rules, including on SQLite.
- A stable client retry key returns the existing request instead of creating duplicate bookings/notifications after a lost response.
- Duplicate start/complete actions are rejected; events and earnings are not counted twice.
- Timeline events are append-only through the API. Each transition and its notifications are committed together.
- Historical car details are snapshotted, so deleting/editing a car later does not rewrite completed trip history.
- Open requests do not expose a customer's phone/email or number plate. Assigned parties can copy the relevant contact number. No private driver document is exposed in a booking response.
- Request/detail pages refresh every **8 seconds while foregrounded and visible**, and support manual refresh. Polling stops on background/disposal; older refresh replies cannot overwrite newer successful actions.
- Feeds/history/notifications are bounded in this beta: up to 40 open offers, 60 history rows and 60 notification rows. Full pagination, dispatch queues and archival reporting are later work.

## 4. Pricing is configurable sample pricing, not a payment gateway

Source of truth: `backend/rides/pricing.py`.

| Service | Base ₹ | Per hour ₹ | Minimum hours |
|---|---:|---:|---:|
| Book now | 99 | 129 | 1 |
| Hourly | 99 | 119 | 2 |
| Full day | 199 | 109 | 8 |
| Airport | 149 | 139 | 2 |
| Outstation | 249 | 149 | 6 |
| Night | 129 | 139 | 2 |

Quote = base + hourly rate × chosen duration. The server validates duration (1–14 hours and service minimum). The app reads the server table for its preview; booking creation recalculates it independently. The configured platform share is **18%**.

For example: Hourly × 4h = ₹575; platform share ₹103.50; driver ledger amount ₹471.50.

In this beta, completing a trip freezes the quote as its final ledger fare. Actual driving time/distance, tolls, waiting, surge, taxes, discounts, refunds, invoices and payment reconciliation are **not implemented**. **No money is charged or transferred.** This is not ready for a commercial launch.

## 5. v6 local garage migration

The v6 garage was stored without an account owner in `dm_vehicles_v1`. It must not silently be attached to whoever logs in next.

1. Open **Garage** while signed into your customer account.
2. If old cars exist, tap **Import cars from v6**.
3. Confirm **They are mine** only if those cars belong to you.
4. Cars upload to that account. Duplicate registrations are skipped. If connectivity fails, local copies remain and retry is safe.

The new offline cache is keyed by user ID/email. Signing out or switching accounts cannot show someone else's cached garage. Offline garage editing is disabled; reconnection is required for writes. Bookings need a confirmed server car, not an unsynced local record.

## 6. Optional development demo

This is **opt-in**, requires DEBUG=true and creates fake development documents/clearly labelled demo rides. Do not run it on production or use the credentials for real users.

With the backend terminal's environment configured, open a separate terminal and run:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django seed_demo_data --with-rides
```

- Customer: `rider@demo.drivemate.local`
- Approved driver: `driver@demo.drivemate.local`
- Password for both: `Demo@12345`
- Pending driver for the admin queue: `driver.pending@demo.drivemate.local`

The command seeds a car, a demo open request and a demo completed history trip, and puts **only the demo approved driver** online. Re-running does not duplicate rides or reset a finished trip. Without `--with-rides`, the command keeps its old accounts-only behaviour. `--reset` deletes/recreates demo accounts and their related rows; use it only when you intentionally want to reset demo state.

### Two-phone test

1. Sign into the customer on phone A and the approved driver on phone B, both connected to the same backend.
2. The driver opens Requests, accepts the seeded open request and opens My trips.
3. The customer opens Activity/detail: status becomes Driver assigned on refresh; their inbox gets an assignment notification.
4. The driver starts and completes, confirming that the drive is finished.
5. Customer Activity moves it to history; driver's Earnings ledger increases.
6. To test a new request, finish/cancel the existing live request first, then book from the customer Home.

With one phone, you can sign out/in between the two roles: status is kept on the server and survives app restarts. Demo data is marked in booking detail and the earnings/dashboard ledger.

## 7. API map

All paths below are under `/api/rides/` and require JWT/session authentication plus verified email. Ownership/role/approval checks run on the server.

| Method | Path | Purpose |
|---|---|---|
| GET | `pricing/` | Server pricing table/minimums |
| GET / POST | `vehicles/` | Customer garage / create a car |
| GET / PUT / DELETE | `vehicles/<id>/` | Own car / update / remove |
| GET / POST | `bookings/` | Own list (staff sees all) / customer request |
| GET | `bookings/<id>/` | Participant/staff detail; eligible online driver offer |
| POST | `bookings/<id>/cancel/` | Reason required; only before start |
| GET / POST | `availability/` | Driver's server availability |
| GET | `requests/` | Eligible online-driver feed; empty while busy/offline |
| POST | `requests/<id>/accept/` | Atomically claim a request |
| POST | `requests/<id>/decline/` | Hide the request for this driver |
| GET | `trips/` | Driver's assigned work/history |
| POST | `trips/<id>/start/` | Assigned approved driver's ACCEPTED → ONGOING |
| POST | `trips/<id>/complete/` | Assigned driver's ONGOING → COMPLETED |
| GET | `summary/` | Driver earnings ledger and chart |
| GET | `notifications/` | Own inbox/unread count |
| POST | `notifications/<id>/read/` | Mark own alert read |
| POST | `notifications/read-all/` | Mark own inbox read |
| GET | `admin/overview/` | Staff booking/driver counters |

## 8. Verification and remaining work

Verified in this release: **44 Flutter tests**, **40 Django tests**, clean `flutter analyze`, no pending migrations, fresh-database migration/seed checks. Flutter screen tests use deterministic HTTP fixtures; Django tests exercise the actual models/views/database, including a two-driver acceptance race.

Not shipped: live maps/GPS/radius matching, automatic nearest-driver dispatch, background push/FCM, trip OTP, phone dialling, payment gateways, paid settlements, refunds or production monitoring. The beta board is not geographically restricted; only driving-capability/availability rules filter offers. Do not claim a guaranteed arrival time or operate real paid journeys on it. Production needs HTTPS, a strong private SECRET_KEY (not the development default), DEBUG=False, SMTP, authenticated rate limits, deployment hardening, dispatch/safety policies and a completed payments/reconciliation layer.
