> **V9 users:** use `V9_FEATURES_AND_RUN.md` and `tools/run_backend.ps1` first. The current phone launcher requires API contract 9. This V8 article remains a hardware/LAN troubleshooting reference.

# DriveMate v8 — phone connection fix + server settings

**V8 includes all V7 booking features. Install V8 over your existing project; you do not need to apply V7 separately.** The separate V7 ZIP is kept as the original release, not the recommended connection fix.

## Your log: what actually happened

- `http://127.0.0.1:8000/api/health/` returned the correct DriveMate JSON: the backend was reachable **from the PC**.
- `List of devices attached` had no rows: ADB did not detect an authorized Android phone. There was no serial to reverse a port to or deploy Flutter on.
- `* daemon started successfully` is normal ADB startup output, not a failure.
- `Terminate batch job (Y/N)? Y` means the terminal command was manually interrupted; it is not a Django exception or a Flutter compile error.
- Your addresses were `192.168.56.1` and `10.26.0.206`. The first is commonly a virtual/host-only address. The number alone is not proof: V8 checks the actual physical adapter, UP status and default gateway instead of picking the first private IP.

**A code ZIP cannot repair a charge-only cable, disabled USB debugging, an unaccepted phone prompt or a missing Windows OEM driver.** V8 diagnoses the state and stops safely instead of continuing into a failed/wrong-target Flutter run.

## 1. Install/update safely

1. Stop the old Flutter run and backend terminal.
2. Back up the project/database. Extract `drivemate_update_v8.zip` into `C:\Users\adars\Downloads\updated_drivemate` and overwrite files. `frontend`, `backend` and `tools` must merge with the existing folders.
3. `.env`, your database, uploaded files, virtual environment and SDKs are not included or overwritten. **Do not delete the database.**
4. Start the backend and apply included V7 migrations if you have not installed V7 yet. V8 itself adds no database migration.

Terminal 1, one line; leave it running:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate; if ($LASTEXITCODE -eq 0) { .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 }
```

## 2. Fix the empty ADB list first

1. Unlock the Android phone.
2. Enable **Developer options → USB debugging**.
3. Try a known **data-capable cable** and a direct USB port. Some cables can charge but have no working data connection. Avoid a hub/dock while diagnosing.
4. Try **File transfer / MTP** mode to check the USB data connection. MTP is a diagnostic step, not a universal requirement for ADB.
5. Accept **Allow USB debugging?** if it appears. There is no popup to accept if the cable/driver does not expose the device at all.
6. Open **Windows Device Manager**. If the phone appears as an unknown Android/USB device or MTP works but ADB does not, check the official manufacturer ADB driver for the exact phone model. Do not install random driver packs or turn off antivirus/Play Protect.

Check with the installed ADB executable from your log (no PATH edit required):

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

What the state means:

| ADB output | Meaning/action |
|---|---|
| No rows | Check cable, data connection, debugging and Windows driver first |
| `unauthorized` | Unlock phone and accept the authorization prompt; if absent, reconnect and consider revoking USB debugging authorizations on the phone, then reconnect |
| `offline` | Reconnect/unlock, try a direct port and check the ADB installation |
| A real serial + `device` | Ready for the USB launcher |
| Only `emulator-...` | That is an emulator, not the physical phone |
| Multiple ready phones | Use an actual serial with `-DeviceId`; V8 refuses to guess |

Do not type a made-up serial. Copy the serial returned by `adb devices -l`.

### Safe USB run — Terminal 2

After a physical phone shows state `device`, use **this single launcher**, not the old semicolon chain:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

It does these in order:

1. Finds ADB and parses the physical-phone state.
2. Chooses the one ready phone, or requires `-DeviceId` if there are several.
3. Tests the exact DriveMate health response.
4. Runs `adb -s SERIAL reverse tcp:8000 tcp:8000` for that phone and verifies the mapping.
5. Writes the source default using explicit UTF-8 and passes the selected address with `--dart-define=API_BASE_URL=...`.
6. Runs `flutter pub get`, checks its exit code, then `flutter run --release -d SERIAL`.

If any prerequisite fails, Flutter is not started. The launcher does **not** silently choose a Windows desktop, Chrome or an emulator.

**Why the old line continued:** PowerShell `;` separates commands; it does not mean “only if successful.” An external script returning a nonzero exit code cannot stop the next command in a manually pasted semicolon chain. The new launcher keeps the checks and run in one controlled script.

## 3. No usable USB? Build/install an APK manually over LAN

**Building an APK does not need an ADB device.** It still needs Flutter, the Android SDK/JDK/build tools/licences and initial dependency downloads. Installing the APK and reaching the backend are separate steps.

First make sure the backend listens on `0.0.0.0:8000` and permits the actual LAN host.

For the IP shown in your current log, the relevant line in `backend/.env` can be:

```dotenv
ALLOWED_HOSTS=localhost,127.0.0.1,10.0.2.2,10.26.0.206
```

Edit that **in the .env file, not in PowerShell**, preserve any other hosts you already need, and restart Django. This IP is from your log; if your Wi-Fi changes, discover/use the new actual IP. Do not use `ALLOWED_HOSTS=*` as a fix.

Then, from a new terminal:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Lan -BuildApk -LanIp 10.26.0.206
```

The helper verifies that the address belongs to a suitable UP physical adapter with a gateway. If your current IP differs, it will reject the stale IP rather than build against the wrong adapter. You can omit `-LanIp` when exactly one suitable physical address is available.

Output on your PC:

```text
frontend\build\app\outputs\flutter-apk\app-release.apk
```

1. Transfer that self-built APK using a trusted local transfer/Bluetooth, or MTP if file transfer works even though the ADB driver does not.
2. Install it on the phone. Allow installation only for the trusted file source if Android asks; do not disable device-wide protections.
3. Put phone and PC on the same reachable LAN.
4. On the **phone browser**, open `http://10.26.0.206:8000/api/health/` (or your current chosen IP).
5. It must return DriveMate JSON on the phone too. PC success alone does not prove firewall/router/phone connectivity.
6. Open the app, select **Server connection** on Login, test the LAN address and save it.

**Setting LAN does not itself make `flutter run` find a phone.** `-Lan` without `-BuildApk` still requires a detected ADB phone for installation. The no-ADB alternative is explicitly **build APK + manual install**.

### Firewall / network checks

If the phone cannot load the health URL:

- Check both devices are on the same network; mobile data, guest/campus Wi-Fi or AP/client isolation can block peer access.
- The selected address must be the PC's physical Wi-Fi/Ethernet address, not VirtualBox, WSL, VPN or host-only networking.
- Django must bind `0.0.0.0`, not just loopback.
- HTTP 400 can mean the IP is missing from `ALLOWED_HOSTS`; add the exact IP and restart.
- On a trusted **Private** Windows network, an Admin PowerShell can add a narrowly scoped development rule if needed:

```powershell
New-NetFirewallRule -DisplayName "DriveMate dev 8000 Private LAN" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow -Profile Private -RemoteAddress LocalSubnet
```

Do not disable the firewall globally. A Private-profile rule does not apply to a Public network; choose an appropriate trusted network instead of blindly relaxing all profiles. Office/campus policy may still prevent peer connectivity—use a permitted USB or personal test-network setup.

## 4. New app screen: Login / Account → Server connection

- Available **before sign-in**, so a dead address no longer traps you behind login.
- Accepts a full trusted HTTP/HTTPS server root or `/api` base, with validation.
- **Test connection** sends only a public GET to `/api/health/`. It sends no JWT, password or user data.
- HTTP 400/404, redirects, HTML or another app's HTTP 200 response do not count as a healthy DriveMate server.
- Save is enabled only after the entered address passes the test. Editing the address invalidates the previous result.
- **Use this server** requires confirmation, persists the selected address and signs out the phone when it changes. Backend data is not deleted.
- A custom address is pinned; it is not silently replaced by fallback hosts. A signed-in session is also pinned to the backend that issued it.
- Old in-flight/login responses cannot restore a session after the server has changed. Offline car cache is scoped by backend + account.
- Use **Reset to built-in discovery** if you no longer want the custom server. A saved runtime pin overrides the source/build-time default until changed/reset.
- USB preset `127.0.0.1` needs an actual ADB reverse tunnel; emulator preset `10.0.2.2` is not for a normal phone.

**One-time V7 → V8 sign-in:** V7 tokens did not record a trusted backend pin. V8 asks you to sign in again rather than guessing where to send them. Your accounts, garage, bookings, documents and history remain on the backend. An old read-only phone cache is not a deleted server car; reconnect to sync it.

HTTP is for private development only. Do not enter production credentials into an untrusted host. Use HTTPS and production security configuration before any real launch. A service banner is a reachability check, not cryptographic proof, a database-migration check or a guarantee of driver availability.

## 5. Diagnostic-only command / parameters

Read-only report (no config/tunnel/driver/firewall/database changes):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\connect_phone.ps1 -Diagnose
```

Optional parameters:

- `-DeviceId`: use one actual physical-phone serial from the ADB list.
- `-LanIp`: use one actual detected physical private address with a gateway.
- `-AdbPath`: use an existing official `adb.exe` from a custom SDK installation.
- `-Port`: default 8000; must match the backend's port. No port is opened automatically.

`connect_phone.ps1 -Usb` or `-Lan` configures/checks only; `run_phone.ps1` is the guarded build/run launcher.

If the ADB list is still blank after checking cable/debugging, provide **phone brand/model + the new diagnostic output + a Device Manager screenshot**. That is needed to narrow the Windows/OEM-driver problem; changing Django code cannot identify an absent USB device.

## 6. Verification / unchanged scope

- Flutter **3.47.7** / Dart **3.13.5**: analysis clean; **75 tests** (44 existing + 31 V8).
- Django **5.2.18**: existing **40 tests** pass; no new migrations/dependencies.
- PowerShell helpers: **83 assertions** under PowerShell **7.4.6**, with ADB/network/Flutter mocked. Parser/state handling, empty/unauthorized/offline/multiple devices, virtual-adapter filtering, health identity, UTF-8 writes, per-serial reverse, fail-fast and APK-without-ADB paths are exercised. Scripts are written using Windows PowerShell 5.1-compatible syntax; actual Windows 5.1/hardware execution was not available here.
- **No physical Windows phone/USB driver or Android APK build was tested in this sandbox.** The ZIP contains source/tooling, not a prebuilt APK or an OEM driver.
- Node.js is not needed. Existing Flutter/Android SDK requirements remain.
- V7 booking/garage/trip/notification/ledger features are preserved. GPS/radius dispatch, background push and real payments/settlements are still not implemented. No money is charged/transferred by this beta.
