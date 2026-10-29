# DriveMate — Subject-wise project status

Ye audit code aur local SQLite tests par based hai. **Implemented**, **partly implemented**, aur **deployment/evidence pending** alag rakhe gaye hain. Azure ya Power BI ka screenshot is package mein nahi hai. Automatic payment/split is version ke scope mein nahi hai.

## 1. System Design

| Requirement | Status | Project mein kahan |
|---|---|---|
| Functional requirements | Documented | `docs/submission/README.md` → System design → Functional requirements. Application functionality: `backend/accounts`, `backend/rides`, `backend/payments`, `frontend/lib/screens`. |
| Non-functional requirements | Documented; production targets/test pending | `docs/submission/README.md` → Non-functional requirements. Security, correctness aur transactions ka code available hai; load test, uptime target aur disaster-recovery evidence abhi nahi hai. |
| High-level architecture + data flow | Documented | `docs/submission/README.md` → Architecture and data flow (Mermaid diagram). Customer/driver app → Django API → database/private storage dikhaya gaya hai. |
| API list | Available | `docs/submission/README.md` → API list; complete URL definitions `backend/accounts/urls.py`, `backend/rides/urls.py`, `backend/payments/urls.py`, `backend/hub/urls.py`. |
| Written trade-off | Documented | `docs/submission/README.md` → Written trade-off: Django monolith versus services. |

## 2. RDBMS

| Requirement | Status | Project mein kahan |
|---|---|---|
| Kam se kam 5 related tables | Implemented | `accounts_user`, `accounts_driverprofile`, `accounts_driverdocument`, `rides_vehicle`, `rides_booking`, `rides_bookingevent`, `payments_directupipayment`. Models `backend/accounts/models.py`, `backend/rides/models.py`, `backend/payments/models.py`. |
| 3NF | **Full proof pending** | Core entities separate hain, par whole schema mein snapshots/JSON aur denormalised history bhi hai. `docs/submission/README.md` → RDBMS. Sab tables ki functional-dependency review ke bina full 3NF claim na karein. |
| PK, FK, constraints | Implemented in Django models/migrations | Upar ke model files aur `backend/*/migrations/`. Examples: driver + document type unique, unique service rate, active-booking constraints. |
| Joins | Available | `docs/submission/queries.sql`: driver + profile + document join. Django ORM bhi related models join karta hai. |
| One view | Implemented | `rides_completed_analytics`, `backend/rides/migrations/0005_analytics_rate_audit.py`. Completed rides ki calculated fee/share; payment settlement ka proof nahi. |
| Stored procedure or trigger | Implemented | Rate-change trigger in `backend/rides/migrations/0005_analytics_rate_audit.py`, SQLite/PostgreSQL ke liye. SQLite par test hua; live PostgreSQL par test pending. |
| Transaction | Implemented | `transaction.atomic()` aur `select_for_update()` in `backend/rides/views.py`. Demo transaction `docs/submission/queries.sql` mein `ROLLBACK` karta hai. |
| Indexes on searched columns | Partly implemented | Booking status/customer/driver indexes `backend/rides/models.py`; document type/status index `backend/accounts/models.py`. Har `icontains` search ko index se speed milne ki guarantee nahi—production PostgreSQL query plans review karne honge. |
| ER diagram, schema script, query file | Available | Diagram `docs/submission/README.md`; `docs/submission/schema_sqlite.sql` aur `docs/submission/queries.sql`. Schema export sirf empty SQLite DB ke liye hai; existing project par `migrate` use karein. |

## 3. DP-900 / Azure

| Requirement | Status | Project mein kahan / baaki kaam |
|---|---|---|
| Structured data | Classified | Users, profiles aur bookings database tables mein; classification `docs/submission/README.md` → DP-900. |
| Semi-structured data | Classified | Booking `vehicle_snapshot` JSON, UPI payload; `backend/rides/models.py`, `backend/payments/models.py`. |
| Unstructured data | Classified | Driver document images/PDF aur QR images; local private uploads, `backend/accounts/security_views.py`, `backend/payments/views.py`. |
| Azure-hosted relational database | **Configuration available; deployed/verified nahi** | `backend/config/settings.py` PostgreSQL configuration; cloud dependencies `backend/requirements-cloud.txt`. Azure Database for PostgreSQL provision karna, TLS/network set karna aur migrations chalana baaki. |
| Azure Blob/Cosmos | **Optional Blob integration configured; deployed/verified nahi** | `backend/config/settings.py` → `USE_AZURE_BLOB`; install `backend/requirements-cloud.txt` aur private container/credentials set karein. Purane local files automatically migrate nahi hote. |
| Analytics view / Power BI | **SQL view hai; Power BI report pending** | `rides_completed_analytics` migration mein hai. Azure se Power BI connect karke actual report banana aur screenshot lena baaki. Numbers calculated shares hain, money transfer nahi. |
| Azure resource screenshots | **Pending** | Azure PostgreSQL, database networking/firewall, private Blob aur Power BI ke real screenshots aapke deployed resources se lene honge. Fake screenshots provide nahi kiye gaye. |

Azure setup steps `docs/submission/README.md` → DP-900 / Azure evidence mein hain. Azure subscription, resource permissions, network access aur kharch ki zaroorat hogi.

## 4. Cloud Security

| Requirement | Status | Project mein kahan / baaki kaam |
|---|---|---|
| Login + role-based access | Implemented; full security review pending | `backend/accounts/views.py`, `backend/accounts/security_views.py`, `backend/config/settings.py`. JWT/session aur staff-only checks use hote hain. |
| Hashed passwords | Implemented | Django auth user model `backend/accounts/models.py`; password validation settings `backend/config/settings.py`. |
| HTTPS | Production configuration present; deployment pending | `backend/config/settings.py`: `DEBUG=false` par HTTPS redirect aur secure cookies. Real TLS certificate, reverse proxy aur trusted forwarded header configure/test karna hoga. |
| Secrets repository se bahar | Configuration and ignore rules present; review pending | `backend/.env.example`, `.gitignore`. Real `.env` kabhi commit na karein. Repo ka pehle se tracked `backend/db.sqlite3.bak` inspect karein; ZIP mein include nahi hai. Past history bhi review karein. |
| SQL injection / XSS validation | Partial protection | Django ORM, DRF serializers in `backend/*/serializers.py`, Django template escaping. Ye complete security audit ya har endpoint XSS-proof hone ka proof nahi. |
| Database firewall/network rule | **Pending deployment** | Azure networking mein restricted rule/private access set karke screenshot lena hoga; code se actual cloud firewall create nahi hua. |
| Activity log | Partial | `BookingEvent` in `backend/rides/models.py`, `PaymentAudit` in `backend/payments/models.py`, document reviewer/time, Django admin log aur rate trigger. Sab actions ka centralized immutable audit log nahi hai. |
| One-page threat model and checklist | Written with honest open items | `docs/submission/SECURITY.md`. Unchecked items complete karne ke baad hi submission mein complete mark karein. |

## Is version mein admin aur payment

- Django admin → **Accounts → Driver documents (grouped)** → ek driver select → har document ka alag status aur reason set → Save. Document file secure download se dekhein. Flutter verification queue mein bhi document-wise review menu hai, lekin actual file viewer nahi hai.
- Django admin → **Rides → Ride rates** → service ka base aur per-hour rate set karein. Fare = base + hourly rate × billable hours; service-wise minimum hours apply hote hain. Existing bookings ka fare nahi badalta.
- 18% fee aur 82% driver share sirf calculated values hain. Direct UPI full fare driver ko bhejta hai aur driver manually payment confirm karta hai. **Automatic transfer abhi nahi hai, aur is update mein nahi joda gaya.**

## Windows par update aur run

ZIP ke andar ki files `C:\Users\adars\Downloads\updated_drivemate` ke existing project mein copy/merge karein. Apna existing `.env`, database, `private_uploads` aur `.venv` delete/replace na karein. Pehle database aur uploads ka backup lein.

**Sirf update ke baad ek baar migration:**
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django migrate
```

**Terminal 1 — backend:**
```powershell
cd C:\Users\adars\Downloads\updated_drivemate\backend; $env:DJANGO_SETTINGS_MODULE="config.settings"; .\.venv\Scripts\python.exe -m django runserver 0.0.0.0:8000 --noreload
```

**Terminal 2 — USB phone:**
```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

Backend SQLite tests passed in the workspace; Flutter build and real Azure/PostgreSQL were not tested here. In commands ko apne existing project path ke hisaab se chalayein.
