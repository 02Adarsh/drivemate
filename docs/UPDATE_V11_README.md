# DriveMate update V11 — policy and server option

## Changes
- Server connection option removed from login and account screens in all builds. The internal connection code and developer tests still exist, but the screen is not linked from user navigation.
- Release builds discard saved custom-server overrides. If an old session is pinned to another host, the user is signed out; credentials are not sent to the new host. The release build uses its configured `API_BASE_URL` and does not try debug fallback hosts. For local USB debugging, the existing launcher provides an API URL and `adb reverse`.
- Terms & Conditions, Privacy Policy and background-verification consent draft text are in `frontend/lib/widgets/policy_sheet.dart`. They can be opened during registration, and Terms/Privacy are also accessible under Account → Privacy & security. Driver background consent is linked in driver registration.
- Operator name: DriveMate. Contact: signed-in Account → Help & Support. Cancellation/refund requests are case-by-case; app has no automatic refund.
- The requested target is **one year from each record's creation** for account, trip and driver-document records, except when longer retention is necessary for legal, dispute or security purposes. The policy makes clear that automatic deletion is **not implemented** and records can currently remain longer. Support can receive deletion/review requests; no automated fulfilment, scheduled deletion or compliance guarantee is added. Account deactivation does not erase data.

## Important before distributing an APK
- **This is a draft, not legal advice.** Have a qualified professional review the policies, operator identity and contact arrangements for applicable Indian laws before publishing. In-app-only support is unavailable before login/after deactivation: supply a real external privacy/grievance contact and a way to respond to requests if legally required. Give us real contact details to add; do not invent them.
- Design and implement a tested, legally reviewed retention/deletion process (including active accounts, related records, backups, holds and audit records) before promising one-year deletion. There is no automatic retention enforcement in this version.
- Registration checks terms acceptance on the client; the backend does not currently record customer policy version/time. Driver consent has a timestamp but not a policy version. Add and review server-side versioned consent records if required.
- Deployment and signed APK are not done. `frontend/lib/config.dart` still defaults to local `127.0.0.1`; configure your real Render HTTPS URL in the release build using `--dart-define=API_BASE_URL=https://YOUR-RENDER-HOST/api`. Do not distribute an APK with the placeholder. Production Android still has cleartext enabled and uses debug signing/`com.example.drivemate`; fix those before public release. See `docs/USER_APP_CLEANUP_V10.md` for the rest of the deployment checklist; V11 supersedes its statement that the server menu is available in debug builds and its old policy-notice description.
- Flutter SDK was unavailable in this workspace; Flutter analyze/build/device tests were not run. Backend tests are independent of these UI changes.

## Windows commands

Merge this ZIP into `C:\Users\adars\Downloads\updated_drivemate`; do not replace your `.env`, existing database, uploads or `.venv`. If upgrading from before V9, run migrations once:
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate
```

Backend terminal:
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 --noreload
```

Phone terminal:
```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

If a debug installation still has an old custom server saved, clearing the app's data or reinstalling it removes that local preference and signs the phone out. Do not clear your backend database.
