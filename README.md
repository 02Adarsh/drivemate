> **Latest: V9.1 direct-UPI update (API 10).** Driver receiving QR/ID setup,
> final-fare QR and explicitly manual confirmation: read
> [`docs/DIRECT_UPI_PAYMENT.md`](docs/DIRECT_UPI_PAYMENT.md) and
> [`README_UPDATE.md`](README_UPDATE.md). Includes V9 UI/map/OTP/account features.
> Start with `tools/run_backend.ps1`, then `tools/run_phone.ps1 -Usb`.
> External UPI amount-edit controls/automatic bank verification are NOT guaranteed
> by a personal QR; merchant integration is needed for those.



# DriveMate

**A verified professional driver comes to you and drives the car you own.**
The customer never books a car from the platform — the customer's own vehicle is
the vehicle being driven.

This repository holds the Flutter mobile app and the Django REST backend.

## Current build

| Area | State |
|---|---|
| Customer registration, OTP, profile | ✅ done |
| Driver registration (5 steps: account → personal → driving → documents/consent/training → admin verification) | ✅ done |
| Admin verification (Django admin + staff API) | ✅ done |
| Login / register / onboarding / splash UI matched to the reference design | ✅ done |
| Driver dashboard, customer dashboard | 🟡 shell — says clearly what is live and what is next |
| Booking, 500 m matching, live GPS, timer, inspections, payments, ratings, disputes, admin dashboard | ⏭ next phases |

Nothing in this build fakes a feature. Where a real integration is missing
(maps, payments, SMS, push) the screen says so, and the code keeps a clean
service boundary for it.

## Quick start

```bash
# 1. backend
cd backend
python -m venv .venv
source .venv/bin/activate           # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                # Windows: copy .env.example .env
python manage.py migrate
python manage.py seed_demo_data     # optional demo accounts
python manage.py createsuperuser --email admin@drivemate.in --full_name "Platform Admin"
python manage.py runserver 0.0.0.0:8000

# 2. app (phone connected by USB with debugging enabled)
adb reverse tcp:8000 tcp:8000
cd ../frontend
flutter pub get
flutter run
```

Set `apiBaseUrl` in `frontend/lib/config.dart` (`http://127.0.0.1:8000/api`
after `adb reverse`, otherwise your computer's LAN IP).

## Tests

```bash
cd backend  && python manage.py test accounts -v 1   # 8 API tests
cd frontend && flutter analyze && flutter test       # clean + 5 widget tests
```

## Documentation

| File | Content |
|---|---|
| `docs/RUN_AND_TEST.md` | VS Code + USB phone commands, demo accounts, troubleshooting |
| `docs/API.md` | Every endpoint, payloads, error format |
| `docs/DRIVER_REGISTRATION.md` | The five steps, mandatory rules, statuses, admin review |
| `README_UPDATE.md` | What changed in the latest update |

## Project layout

```
backend/    Django REST API
  accounts/ models, progress rules, views, serializers, admin, tests, seed command
  config/   settings, urls
frontend/   Flutter app
  lib/theme      design tokens
  lib/widgets    reusable UI (brand header, fields, buttons, slider, step header)
  lib/services   API client + navigation rules
  lib/screens    splash, onboarding, login, register, OTP, driver 5-step wizard, dashboards
  lib/utils      validators
docs/       guides
```

## Safety and honesty notes

* Approval and "online" are separate states — approval alone never puts a driver
  in front of customers.
* Driver documents live in private storage; only staff can open them.
* Legal texts (terms, privacy, cancellation, damage policy) are clearly marked
  placeholders and must be reviewed for your launch jurisdiction.
* Verification rules (minimum age, required documents, required training) are
  configuration, not hard-coded law.
