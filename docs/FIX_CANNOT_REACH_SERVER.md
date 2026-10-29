> **V8 note:** A blank `adb devices` list is a separate phone-detection problem,
> even if PC backend health is OK. Use [`V8_PHONE_CONNECTION.md`](V8_PHONE_CONNECTION.md)
> and the single `tools/run_phone.ps1` launcher. Do not use older semicolon chains
> below to continue into Flutter after an ADB failure. No wildcard ALLOWED_HOSTS
> or global firewall disabling is required.

# "Cannot reach the DriveMate server" — poora fix

App screen par ye error aata hai jab phone, computer par chal rahe Django server
tak pahunch nahi paata. **Ye app ka bug nahi, network ka issue hai** — 99% cases
in chaar wajahon mein se ek hoti hai:

| # | Wajah | Pehchan |
|---|---|---|
| 1 | Backend band hai / `127.0.0.1:8000` par chala hai | PC browser mein `http://127.0.0.1:8000/api/health/` khulta hi nahi |
| 2 | LAN IP badal gaya (naya Wi-Fi, hotspot, router restart) | `ipconfig` ka IPv4 `config.dart` se alag |
| 3 | Phone dusre network par hai (mobile data / alag Wi-Fi) | Phone browser mein `http://<PC-IP>:8000/api/health/` nahi khulta |
| 4 | Windows Firewall port 8000 block kar raha hai | PC par chalta hai, phone par nahi |

---

## Step 0 — 10 second ka test (sabse pehle yahi karein)

**Phone ke browser (Chrome) mein kholein:**

```
http://<aapke-PC-ka-IP>:8000/api/health/
```

* **`{"status": "ok", ...}` dikha** → network theek hai, problem app ke address mein hai
  (Step 3 karein).
* **Page load hi nahi hua / timeout** → network ya firewall ka issue (Step 1–2 karein).

PC par IPv4 nikalne ke liye:

```powershell
ipconfig
```
`Wireless LAN adapter Wi-Fi` ke andar **IPv4 Address** — jaise `10.21.188.30`.

---

## Step 1 — Backend sahi tarah chalayein

Terminal 1 (chalta rehne dena):

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; .\.venv\Scripts\Activate.ps1; python manage.py runserver 0.0.0.0:8000
```

* `0.0.0.0:8000` **zaroori** hai — `127.0.0.1:8000` likha to sirf aapka computer
  sunta hai, phone nahi.
* PC browser mein test: `http://127.0.0.1:8000/api/health/` →
  `{"status": "ok", ...}` aana chahiye.

## Step 2 — Firewall (sirf Wi-Fi wale tareeke ke liye)

Pehli baar Windows ek popup dikhata hai → **Allow access** par click karein.
Popup aage aa gaya to manual rule (Admin PowerShell):

```powershell
New-NetFirewallRule -DisplayName "DriveMate 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

## Step 3 — App ka address (do tareeke, koi ek chuniye)

### ✅ Tareeka A — USB cable (recommended, Wi-Fi ki zaroorat nahi, IP kabhi nahi badalta)

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend
.\.venv\Scripts\Activate.ps1
$env:Path+=";$env:LOCALAPPDATA\Android\Sdk\platform-tools"
adb devices                    # phone dikhna chahiye
adb reverse tcp:8000 tcp:8000  # phone ka 8000 -> computer ka 8000
```

`lib\config.dart` mein:

```dart
const String apiBaseUrl = 'http://127.0.0.1:8000/api';
```

Phir: `flutter run --release`

> **v5 se ye automatically bhi ho jaata hai.** App start par `/api/health/` se
> check karti hai ki kaun sa address jawab de raha hai — `127.0.0.1` (USB
> tunnel), aapka LAN IP, ya `10.0.2.2` (emulator) — aur usi par chali jaati hai.
> `adb reverse` chal chuka ho to config.dart badalne ki zaroorat bhi nahi.

### 🌐 Tareeka B — Same Wi-Fi

1. `ipconfig` se IPv4 lein.
2. `lib\config.dart`: `const String apiBaseUrl = 'http://<IPv4>:8000/api';`
3. Phone **usi Wi-Fi** par ho (computer ka hotspot bhi chalega).
4. `flutter run --release`

---

## Ek command mein sab (helper script)

Repo ke saath `tools\connect_phone.ps1` ship hota hai:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate
powershell -ExecutionPolicy Bypass -File tools\connect_phone.ps1 -Usb
```

Ye script: backend check karta hai → LAN IP batata hai → adb reverse tunnel banata
hai → `config.dart` set karta hai → agla step print karta hai.

`-Lan` bhi chalta hai: `powershell -ExecutionPolicy Bypass -File tools\connect_phone.ps1 -Lan`

---

## "Tried: ..." wala naya error message

v5 se error khud hi batata hai ki kaun-kaun se address try kiye gaye, jaise:

```
Cannot reach the DriveMate server (tried http://10.21.188.30:8000/api).

On the computer, start it with:
  python manage.py runserver 0.0.0.0:8000

USB cable (recommended):
  adb reverse tcp:8000 tcp:8000
then set http://127.0.0.1:8000/api in lib/config.dart.
```

Isse turant pata chal jaata hai ki app kahan dhoondh raha tha.

---

## Common galtiyan

| Galti | Sahi tareeka |
|---|---|
| `runserver` bina `0.0.0.0` | `python manage.py runserver 0.0.0.0:8000` |
| config.dart badla par rebuild nahi kiya | `flutter run --release` dobara chalayein (hot reload release mein nahi chalta) |
| Phone mobile data par hai | Wi-Fi on karein ya USB + `adb reverse` use karein |
| `adb reverse` phone reconnect ke baad | Cable dobara lagne par `adb reverse tcp:8000 tcp:8000` phir chalayein |
| Backend band kar diya | Terminal 1 chalta rehna chahiye (`Ctrl + C` na dabayein) |
| `Allowed file types` type error | Ye alag issue hai — upload ka fix v3 se ship ho chuka hai |

---

## Quick checklist

- [ ] PC browser: `http://127.0.0.1:8000/api/health/` → `{"status": "ok"}`
- [ ] Phone browser: `http://<PC-IP>:8000/api/health/` → `{"status": "ok"}` (Wi-Fi tareeka) **ya** `adb reverse` chala hua
- [ ] `config.dart` ka address usi tareeke se match karta hai
- [ ] `flutter run --release` se rebuild kiya
- [ ] backend Terminal 1 mein chalta reh gaya
