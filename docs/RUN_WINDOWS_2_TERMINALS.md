# DriveMate — Windows pe chalane ka sahi tareeka (2 terminals)

> **Sabse badi galti jo hui:** dono blocks ek hi terminal mein paste kar diye gaye,
> aur `>>` / `# comment` lines bhi paste ho gayin.
> `>>` sirf PowerShell ka *continuation prompt* hai — aap use **kabhi type/paste nahi** karte.
> Har block **alag terminal** mein, **ek line at a time** (ya poora block ek saath, lekin sirf us block ki lines).

Folder structure (yaad rakhein):

```
C:\Users\adars\Downloads\updated_drivemate\
├── backend\        <- Terminal 1 yahan chalega
└── frontend\       <- Terminal 2 yahan chalega
```

`backend` aur `frontend` **bhai-behen** hain. Isliye `frontend` ke andar se `cd backend`
kaam nahi karega — poora (absolute) path dein.

---

## Terminal 1 — Backend (Django)

VS Code mein **Terminal → New Terminal** kholiye aur ye lines ek-ek karke chalayein:

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend
```

```powershell
.\.venv\Scripts\Activate.ps1
```

> Agar is line pe error aaye to neeche "venv problems" section dekhein.
> Prompt ke aage `(.venv)` dikhne lage to venv chalu ho gaya.

```powershell
python manage.py migrate
```

```powershell
python manage.py runserver 0.0.0.0:8000
```

Ab ye terminal **chalti rehne dena** hai. Server band karna ho to `Ctrl + C`.
Server chalne ka signal:

```
Starting development server at http://0.0.0.0:8000/
Quit the server with CTRL-BREAK.
```

> **Isi terminal mein aage kuch aur type nahi karna.** Server chalta rahega.

---

## Terminal 2 — Frontend (Flutter)

VS Code mein **Terminal → New Terminal** (naya terminal, `+` button) kholiye.
Pehle terminal 1 waise hi chalta rahega.

```powershell
cd C:\Users\adars\Downloads\updated_drivemate\frontend
```

```powershell
flutter clean
```

```powershell
flutter pub get
```

Phone USB se laga hai? pehle check karein:

```powershell
flutter devices
```

Aapka phone list mein dikhna chahiye (jaise `SM G990E (mobile) • ... • android-arm64`).
Ab chalayein:

```powershell
flutter run --release
```

> `--release` zaroori hai. Debug mode mein har Flutter app slow lagti hai — lag ki
> jo feeling aati hai wo debug ka JIT hai, app ka bug nahi.

---

## Phone ko backend se kaise jodein? (do tareeke — koi ek chuniye)

### Tareeka A — USB tunnel (`adb reverse`) — **recommended**, Wi-Fi ki zaroorat nahi

`adb` aapke PATH mein nahi hai, isliye pehle use session ke liye PATH mein add karein
(Terminal 2 mein hi, `flutter run` se pehle):

```powershell
$env:Path += ";$env:LOCALAPPDATA\Android\Sdk\platform-tools"
```

```powershell
adb devices
```

Phone dikh gaya? To tunnel banayein:

```powershell
adb reverse tcp:8000 tcp:8000
```

Ab `frontend\lib\config.dart` mein ye line set karein:

```dart
const String apiBaseUrl = 'http://127.0.0.1:8000/api';
```

Phir `flutter run --release`.

**Agar `adb` ab bhi "not recognized" de** — platform-tools kahin aur pada hai, dhoondiye:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
              "C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe",
              "$env:USERPROFILE\Android\Sdk\platform-tools\adb.exe" -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty FullName
```

Jo path mile, usi ka folder `$env:Path += ";<WO_FOLDER>"` mein daal dein.
Kuch na mile to Android Studio → **SDK Manager → SDK Tools → Android SDK Platform-Tools**
install karein. Ya seedha Tareeka B use karein — adb bilkul zaroori nahi hai.

### Tareeka B — Same Wi-Fi + LAN IP (adb ki zaroorat nahi)

1. Computer pe IP nikaalein:
   ```powershell
   ipconfig
   ```
   `Wireless LAN adapter Wi-Fi` ke andar **IPv4 Address** dekhein, jaise `192.168.1.20`.
2. `frontend\lib\config.dart` mein badlein:
   ```dart
   const String apiBaseUrl = 'http://192.168.1.20:8000/api';   // apna IP daalein
   ```
3. Phone **usi Wi-Fi** pe ho jo computer pe hai (mobile hotspot bhi chalega: computer ko
   phone ke hotspot se jodein).
4. Windows Firewall ko port 8000 allow karne dein (pehli baar popup aata hai → **Allow**).
   Manual:
   ```powershell
   New-NetFirewallRule -DisplayName "DriveMate 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
   ```
   (Admin PowerShell chahiye)
5. `flutter run --release`

> `config.dart` badalne ke baad **app dobara build hoti hai** — `flutter run --release`
> phir se chalayein (hot reload release mein kaam nahi karta).

---

## venv problems (Terminal 1)

| Error | Hal |
|---|---|
| `.\.venv\Scripts\Activate.ps1 : running scripts is disabled` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` chalayein, phir `Activate.ps1` dobara |
| `Cannot find path ...\backend\.venv` | venv nahi hai. `python -m venv .venv` → `.\.venv\Scripts\Activate.ps1` → `pip install -r requirements.txt` |
| `[Errno 13] Permission denied: '.venv\Scripts\python.exe'` | venv already exist karta hai — dobara `python -m venv .venv` **mat** chalayein, seedha activate karein |
| `ImproperlyConfigured: DATABASES ... ENGINE` | `backend\.env` mein `DB_ENGINE=` line **poori delete** kar dein (khali chhodna bhi problem hai purane code mein) |

---

## Quick checklist

- [ ] Terminal 1: backend `runserver 0.0.0.0:8000` chal raha hai (band nahi karna)
- [ ] `flutter pub get` chal chuka hai (fonts + http_parser ke liye zaroori)
- [ ] `python manage.py migrate` chal chuka hai (state/pincode columns)
- [ ] Phone USB debugging ON ya same Wi-Fi pe hai
- [ ] `flutter run --release` (debug nahi)
- [ ] `config.dart` ka URL aapke connection se match karta hai (`127.0.0.1` for adb reverse, ya LAN IP)
